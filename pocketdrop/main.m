#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <unistd.h>
#import <signal.h>

#define PD_PORT 8765
#define PD_MAX_UPLOAD (25*1024*1024)

static NSString *PDDir(void) {
    NSString *dir=@"/var/mobile/Documents/PocketDrop";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}
static NSString *PDIP(void){
    struct ifaddrs *all=NULL;
    if(getifaddrs(&all)!=0)return @"无 Wi-Fi";
    NSString *out=@"无 Wi-Fi";
    for(struct ifaddrs *it=all;it;it=it->ifa_next){
        if(it->ifa_addr && it->ifa_addr->sa_family==AF_INET && [[NSString stringWithUTF8String:it->ifa_name] isEqualToString:@"en0"]){
            char addr[INET_ADDRSTRLEN]={0};
            inet_ntop(AF_INET,&((struct sockaddr_in *)it->ifa_addr)->sin_addr,addr,sizeof(addr));
            out=[NSString stringWithUTF8String:addr];break;
        }
    }
    freeifaddrs(all);return out;
}
static NSString *PDParam(NSString *path,NSString *key){
    NSRange q=[path rangeOfString:@"?"];if(q.location==NSNotFound)return nil;
    for(NSString *part in [[path substringFromIndex:q.location+1] componentsSeparatedByString:@"&"]){
        NSRange r=[part rangeOfString:@"="];
        if(r.location==NSNotFound)continue;
        if([[part substringToIndex:r.location] isEqualToString:key]){
            return [[[part substringFromIndex:r.location+1] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
        }
    }return nil;
}
static NSString *PDSafeName(NSString *name){
    if(![name isKindOfClass:[NSString class]])return nil;
    NSString *text=[name lastPathComponent];
    NSMutableString *safe=[NSMutableString string];
    NSCharacterSet *illegal=[NSCharacterSet characterSetWithCharactersInString:@"/\\:\r\n\t"];
    for(NSUInteger i=0;i<MIN((NSUInteger)120,text.length);i++){
        unichar c=[text characterAtIndex:i];
        if(c<32 || [illegal characterIsMember:c]) [safe appendString:@"_"];
        else [safe appendFormat:@"%C",c];
    }
    if(!safe.length || [safe hasPrefix:@"."] || [safe isEqualToString:@".."])return nil;
    return safe;
}
static BOOL PDSend(int fd,const void *bytes,size_t length){
    const char *p=bytes;
    while(length){
        ssize_t n=send(fd,p,length>16384?16384:length,0);
        if(n<=0)return NO;
        p+=n;length-=n;
    }
    return YES;
}
static void PDReply(int fd,int code,NSString *type,NSData *body){
    NSString *reason=code==200?@"OK":code==400?@"Bad Request":code==401?@"Unauthorized":
       code==404?@"Not Found":code==413?@"Payload Too Large":code==409?@"Conflict":@"Error";
    NSString *header=[NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: %@\r\nContent-Length: %lu\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n",
      code,reason,type?:@"text/plain; charset=utf-8",(unsigned long)body.length];
    NSData *h=[header dataUsingEncoding:NSUTF8StringEncoding];PDSend(fd,h.bytes,h.length);
    if(body.length)PDSend(fd,body.bytes,body.length);
}
static void PDText(int fd,int code,NSString *text){
    PDReply(fd,code,@"text/plain; charset=utf-8",[text dataUsingEncoding:NSUTF8StringEncoding]);
}
static NSString *PDHTML(void){
    return @"<!doctype html><html lang='zh-CN'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<title>PocketDrop</title><style>body{font-family:system-ui,-apple-system,sans-serif;max-width:640px;margin:24px auto;padding:0 18px;color:#24304b;background:#f5f7fc}"
    "h1{font-size:27px;color:#4e60cc}p{color:#65718a}section{background:white;padding:18px;margin:15px 0;border-radius:16px;border:1px solid #e7ebf3}"
    "button,input,textarea{font:inherit;box-sizing:border-box}button{background:#5366d3;color:white;border:0;border-radius:9px;padding:10px 15px;margin:4px;cursor:pointer}"
    "button:disabled{opacity:.5}input,textarea{width:100%;padding:10px;border:1px solid #d5daeb;border-radius:8px;margin:8px 0}"
    "li{padding:8px;border-bottom:1px solid #edf0f6;word-break:break-all}a{color:#5366d3}small{color:#69778e}</style>"
    "<h1>↔ PocketDrop</h1><p>电脑 ⇄ iPhone 4S · 同一 Wi-Fi · 局域网传输</p>"
    "<section><b>① 输入手机显示的 6 位配对码</b><input id='code' placeholder='配对码' maxlength='6' inputmode='numeric'>"
    "<button onclick='connect()'>连接手机</button><span id='status'></span></section>"
    "<section><b>② 电脑发送文件到手机</b><p><small>单文件最大 25 MB，文件保存在 /var/mobile/Documents/PocketDrop/</small></p>"
    "<input type='file' id='file'><button onclick='upload()'>上传文件</button><div id='progress'></div></section>"
    "<section><b>③ 传文字 / 链接</b><textarea id='text' rows='3' placeholder='复制文字、网址或安装说明'></textarea>"
    "<button onclick='sendText()'>发送到手机剪贴板</button><button onclick='readText()'>读取手机共享文字</button></section>"
    "<section><b>④ 从手机下载文件</b><button onclick='refresh()'>刷新列表</button><ul id='files'></ul></section>"
    "<p><small>请只在自己的可信 Wi-Fi 使用；本机 HTTP 传输未加密，退出 App 或关闭服务即可停止分享。</small></p>"
    "<script>let key=sessionStorage.getItem('pdcode')||'';document.getElementById('code').value=key;"
    "function h(){return {'X-Pocket-Key':key}}"
    "async function connect(){key=document.getElementById('code').value.trim();if(!/^\\d{6}$/.test(key)){alert('请输入6位配对码');return}sessionStorage.setItem('pdcode',key);await refresh()}"
    "async function refresh(){try{let r=await fetch('/api/files',{headers:h()});if(!r.ok)throw new Error('HTTP '+r.status);"
    "let data=await r.json();document.getElementById('status').textContent=' 已连接';"
    "document.getElementById('files').innerHTML='';for(let f of data.files){let li=document.createElement('li');let a=document.createElement('a');"
    "a.href='/file?name='+encodeURIComponent(f.name)+'&key='+encodeURIComponent(key);a.textContent=f.name+' ('+Math.ceil(f.size/1024)+' KB)';"
    "li.appendChild(a);document.getElementById('files').appendChild(li)}}catch(e){document.getElementById('status').textContent=' 连接失败：'+e.message}}"
    "async function upload(){let f=document.getElementById('file').files[0];if(!f)return alert('选择文件');if(f.size>25*1024*1024)return alert('文件不能超过25MB');"
    "document.getElementById('progress').textContent='正在上传…';try{let r=await fetch('/upload?name='+encodeURIComponent(f.name),{method:'POST',headers:h(),body:f});"
    "if(!r.ok)throw new Error(await r.text());document.getElementById('progress').textContent='上传成功';refresh()}catch(e){document.getElementById('progress').textContent='失败：'+e.message}}"
    "async function sendText(){let r=await fetch('/api/text',{method:'POST',headers:h(),body:document.getElementById('text').value});"
    "alert(r.ok?'发送成功':'发送失败：'+r.status)}"
    "async function readText(){let r=await fetch('/api/text',{headers:h()});if(r.ok)document.getElementById('text').value=await r.text();else alert('读取失败：'+r.status)}"
    "if(key)refresh();</script></html>";
}
@interface PDApp : UIResponder <UIApplicationDelegate,UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIViewController *root;
@property(nonatomic,strong) UILabel *address;
@property(nonatomic,strong) UILabel *state;
@property(nonatomic,strong) UILabel *codeLabel;
@property(nonatomic,strong) UIButton *toggle;
@property(nonatomic,strong) UITextView *textBox;
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,strong) NSMutableArray *items;
@property(nonatomic,strong) UIDocumentInteractionController *document;
@property(nonatomic,copy) NSString *sharedText;
@property(nonatomic,copy) NSString *code;
@property(nonatomic,assign) int listener;
@property(nonatomic,assign) BOOL serving;
@end
@implementation PDApp
- (void)notice:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(),^{self.state.text=message;});
}
- (void)reloadFiles{
    NSArray *list=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:PDDir() error:NULL];
    NSMutableArray *files=[NSMutableArray array];
    for(NSString *name in list)if(![name hasPrefix:@"."]){
        NSString *path=[PDDir() stringByAppendingPathComponent:name];
        BOOL isDirectory=NO;
        if([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]&&!isDirectory)[files addObject:name];
    }
    [files sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.items=files;[self.table reloadData];
}
- (void)sendFile:(int)client name:(NSString *)name {
    NSString *safe=PDSafeName(name);
    NSString *path=safe?[PDDir() stringByAppendingPathComponent:safe]:nil;
    NSDictionary *attr=path?[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL]:nil;
    if(!attr || ![attr.fileType isEqualToString:NSFileTypeRegular]){PDText(client,404,@"File not found");return;}
    unsigned long long size=[attr fileSize];
    NSString *header=[NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: %llu\r\nContent-Disposition: attachment; filename=\"%@\"\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n",size,[safe stringByReplacingOccurrencesOfString:@"\"" withString:@"_"]];
    NSData *h=[header dataUsingEncoding:NSUTF8StringEncoding];
    if(!PDSend(client,h.bytes,h.length))return;
    NSFileHandle *input=[NSFileHandle fileHandleForReadingAtPath:path];
    @try{
        while(YES){
            NSData *part=[input readDataOfLength:16384];
            if(!part.length || !PDSend(client,part.bytes,part.length))break;
        }
    }@catch(NSException *e){}
    [input closeFile];
}
- (void)serveClient:(int)client {
    @autoreleasepool {
        struct timeval timeout={20,0};
        setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
        NSMutableData *received=[NSMutableData data];
        NSRange boundary=NSMakeRange(NSNotFound,0);
        NSData *ending=[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
        char buffer[8192];
        while(received.length<16000){
            ssize_t n=recv(client,buffer,sizeof(buffer),0);
            if(n<=0)break;
            [received appendBytes:buffer length:(NSUInteger)n];
            boundary=[received rangeOfData:ending options:0 range:NSMakeRange(0,received.length)];
            if(boundary.location!=NSNotFound)break;
        }
        if(boundary.location==NSNotFound){PDText(client,400,@"Missing header");close(client);return;}
        NSData *headerBytes=[received subdataWithRange:NSMakeRange(0,boundary.location)];
        NSString *header=[[NSString alloc] initWithData:headerBytes encoding:NSUTF8StringEncoding];
        NSArray *lines=[header componentsSeparatedByString:@"\r\n"];
        NSArray *parts=lines.count?[[lines[0] componentsSeparatedByString:@" "] copy]:@[];
        if(parts.count<2){PDText(client,400,@"Invalid request");close(client);return;}
        NSString *method=parts[0],*path=parts[1];
        NSMutableDictionary *headers=[NSMutableDictionary dictionary];
        for(NSUInteger i=1;i<lines.count;i++){
            NSRange idx=[lines[i] rangeOfString:@":"];
            if(idx.location==NSNotFound)continue;
            NSString *key=[[lines[i] substringToIndex:idx.location] lowercaseString];
            headers[key]=[[lines[i] substringFromIndex:idx.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        NSString *base=[[path componentsSeparatedByString:@"?"] firstObject];
        if([method isEqualToString:@"GET"] && [base isEqualToString:@"/"]){
            PDReply(client,200,@"text/html; charset=utf-8",[PDHTML() dataUsingEncoding:NSUTF8StringEncoding]);
            close(client);return;
        }
        NSString *provided=headers[@"x-pocket-key"]?:PDParam(path,@"key");
        if(!provided || ![provided isEqualToString:self.code]){PDText(client,401,@"Pairing code required");close(client);return;}
        if([method isEqualToString:@"GET"] && [base isEqualToString:@"/api/files"]){
            NSMutableArray *files=[NSMutableArray array];
            NSArray *all=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:PDDir() error:NULL];
            for(NSString *name in all){
                if([name hasPrefix:@"."])continue;
                NSDictionary *attr=[[NSFileManager defaultManager] attributesOfItemAtPath:[PDDir() stringByAppendingPathComponent:name] error:NULL];
                if([attr.fileType isEqualToString:NSFileTypeRegular]) [files addObject:@{@"name":name,@"size":@([attr fileSize])}];
            }
            NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"files":files} options:0 error:NULL];
            PDReply(client,200,@"application/json; charset=utf-8",json);close(client);return;
        }
        if([method isEqualToString:@"GET"] && [base isEqualToString:@"/file"]){
            [self sendFile:client name:PDParam(path,@"name")];close(client);return;
        }
        if([method isEqualToString:@"GET"] && [base isEqualToString:@"/api/text"]){
            __block NSString *current=nil;
            dispatch_sync(dispatch_get_main_queue(),^{current=[self.sharedText copy]?:@"";});
            PDText(client,200,current);close(client);return;
        }
        if([method isEqualToString:@"POST"] && ([base isEqualToString:@"/api/text"]||[base isEqualToString:@"/upload"])){
            NSString *lengthText=headers[@"content-length"];
            NSScanner *scanner=[NSScanner scannerWithString:lengthText?:@""];
            long long total=-1;
            if(![scanner scanLongLong:&total]||!scanner.isAtEnd||total<0||total>PD_MAX_UPLOAD){
                PDText(client,413,@"Invalid size or >25MB");close(client);return;
            }
            NSString *safe=nil,*file=nil;
            NSFileHandle *output=nil;
            if([base isEqualToString:@"/upload"]){
                safe=PDSafeName(PDParam(path,@"name"));
                if(!safe){PDText(client,400,@"Invalid filename");close(client);return;}
                NSString *dest=[PDDir() stringByAppendingPathComponent:safe];
                if([[NSFileManager defaultManager] fileExistsAtPath:dest]){
                    NSString *ext=[safe pathExtension],*stem=[safe stringByDeletingPathExtension];
                    safe=[NSString stringWithFormat:@"%@-%u%@%@",stem,arc4random_uniform(99999),
                      ext.length?@".":@"",ext.length?ext:@""];
                }
                file=[PDDir() stringByAppendingPathComponent:[@"." stringByAppendingString:safe]];
                [[NSFileManager defaultManager] createFileAtPath:file contents:nil attributes:nil];
                output=[NSFileHandle fileHandleForWritingAtPath:file];
                if(!output){PDText(client,500,@"Cannot write file");close(client);return;}
            }
            NSMutableData *body=[NSMutableData data];
            NSUInteger offset=boundary.location+ending.length;
            NSUInteger available=received.length-offset;
            long long remaining=total;
            if(available){
                NSUInteger first=(NSUInteger)MIN((long long)available,remaining);
                NSData *chunk=[received subdataWithRange:NSMakeRange(offset,first)];
                if(output)[output writeData:chunk];else[body appendData:chunk];
                remaining-=first;
            }
            while(remaining>0){
                ssize_t n=recv(client,buffer,(size_t)MIN((long long)sizeof(buffer),remaining),0);
                if(n<=0)break;
                NSData *chunk=[NSData dataWithBytes:buffer length:(NSUInteger)n];
                if(output)[output writeData:chunk];else[body appendData:chunk];
                remaining-=n;
            }
            if(output)[output closeFile];
            if(remaining!=0){if(file)[[NSFileManager defaultManager] removeItemAtPath:file error:NULL];PDText(client,400,@"Incomplete upload");close(client);return;}
            if(file){
                NSString *dest=[PDDir() stringByAppendingPathComponent:safe];
                NSError *err=nil;
                [[NSFileManager defaultManager] moveItemAtPath:file toPath:dest error:&err];
                PDText(client,err?500:200,err?@"File save failed":@"Uploaded");
                dispatch_async(dispatch_get_main_queue(),^{[self reloadFiles];});
            }else{
                NSString *text=[[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
                if(!text){PDText(client,400,@"Expected UTF-8");close(client);return;}
                dispatch_async(dispatch_get_main_queue(),^{self.sharedText=text;self.textBox.text=text;[UIPasteboard generalPasteboard].string=text;self.state.text=@"收到电脑发来的文字，已复制到手机剪贴板";});
                PDText(client,200,@"Text received");
            }
            close(client);return;
        }
        PDText(client,404,@"Not found");close(client);
    }
}
- (void)start {
    if(self.serving)return;
    NSString *ip=PDIP();
    if([ip isEqualToString:@"无 Wi-Fi"]){self.state.text=@"请先连接 Wi-Fi";return;}
    int fd=socket(AF_INET,SOCK_STREAM,0);
    if(fd<0){self.state.text=@"无法创建网络服务";return;}
    int yes=1;setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));
    struct sockaddr_in a;memset(&a,0,sizeof(a));a.sin_family=AF_INET;a.sin_port=htons(PD_PORT);a.sin_addr.s_addr=INADDR_ANY;
    if(bind(fd,(struct sockaddr *)&a,sizeof(a))!=0 || listen(fd,3)!=0){
        close(fd);self.state.text=@"端口 8765 已被占用";return;
    }
    self.code=[NSString stringWithFormat:@"%06u",100000+arc4random_uniform(900000)];
    self.codeLabel.text=[@"配对码  " stringByAppendingString:self.code];
    self.address.text=[NSString stringWithFormat:@"http://%@:%d",ip,PD_PORT];
    self.listener=fd;self.serving=YES;
    [self.toggle setTitle:@"停止传输" forState:UIControlStateNormal];
    self.state.text=@"已启动。电脑浏览器打开上方地址。";
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{
        while(self.serving && self.listener==fd){
            struct sockaddr_in remote;socklen_t len=sizeof(remote);
            int client=accept(fd,(struct sockaddr *)&remote,&len);
            if(client<0){if(!self.serving)break;continue;}
            if(!self.serving){close(client);break;}
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{[self serveClient:client];});
        }
    });
}
- (void)stop {
    self.serving=NO;
    if(self.listener>=0){int fd=self.listener;self.listener=-1;shutdown(fd,SHUT_RDWR);close(fd);}
    self.code=@"";
    self.codeLabel.text=@"配对码  ••••••";
    [self.toggle setTitle:@"开始传输" forState:UIControlStateNormal];
    self.state.text=@"服务已停止";
}
- (void)toggleServer {
    if(self.serving)[self stop];else[self start];
}
- (void)copyAddress {
    if(!self.serving){self.state.text=@"请先开始传输";return;}
    [UIPasteboard generalPasteboard].string=self.address.text;
    self.state.text=@"已复制浏览器地址";
}
- (void)shareClipboard {
    NSString *text=[UIPasteboard generalPasteboard].string;
    if(text.length){self.sharedText=text;self.textBox.text=text;self.state.text=@"手机文字已更新，电脑可点「读取」";}else self.state.text=@"剪贴板为空";
}
- (void)copyReceived {
    if(self.textBox.text.length){self.sharedText=self.textBox.text;[UIPasteboard generalPasteboard].string=self.textBox.text;self.state.text=@"文字已复制";}
}
- (UIButton *)button:(NSString *)title frame:(CGRect)rect action:(SEL)selector on:(UIView *)parent {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];b.frame=rect;
    b.backgroundColor=[UIColor colorWithRed:.31 green:.38 blue:.79 alpha:1];
    b.layer.cornerRadius=9;[b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];b.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    [b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [parent addSubview:b];return b;
}
- (UILabel *)label:(NSString *)value frame:(CGRect)frame font:(UIFont *)font on:(UIView *)parent {
    UILabel *label=[[UILabel alloc] initWithFrame:frame];label.text=value;label.font=font;
    label.textColor=[UIColor colorWithRed:.18 green:.23 blue:.34 alpha:1];label.numberOfLines=0;
    [parent addSubview:label];return label;
}
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    signal(SIGPIPE,SIG_IGN);
    self.listener=-1;self.sharedText=@"";
    PDDir();
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.root=[UIViewController new];
    self.root.view.backgroundColor=[UIColor colorWithRed:.96 green:.97 blue:.99 alpha:1];
    CGFloat w=self.window.bounds.size.width;
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:self.root.view.bounds];
    scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.root.view addSubview:scroll];
    [self label:@"PocketDrop" frame:CGRectMake(15,23,w-30,40) font:[UIFont boldSystemFontOfSize:25] on:scroll];
    [self label:@"iPhone 4S · 轻量传输" frame:CGRectMake(15,59,w-30,22) font:[UIFont systemFontOfSize:12] on:scroll];
    self.address=[self label:@"http://连接 Wi-Fi 后显示地址" frame:CGRectMake(15,92,w-30,31) font:[UIFont boldSystemFontOfSize:18] on:scroll];
    self.codeLabel=[self label:@"配对码  ••••••" frame:CGRectMake(15,129,w-30,29) font:[UIFont boldSystemFontOfSize:19] on:scroll];
    self.toggle=[self button:@"开始传输" frame:CGRectMake(15,170,w-110,43) action:@selector(toggleServer) on:scroll];
    [self button:@"复制地址" frame:CGRectMake(w-91,170,76,43) action:@selector(copyAddress) on:scroll];
    self.state=[self label:@"仅在可信 Wi-Fi 使用 · 退出 App 即停止传输" frame:CGRectMake(15,219,w-30,42) font:[UIFont systemFontOfSize:12] on:scroll];
    [self label:@"共享文字" frame:CGRectMake(15,265,w-30,26) font:[UIFont boldSystemFontOfSize:17] on:scroll];
    self.textBox=[[UITextView alloc] initWithFrame:CGRectMake(15,295,w-30,76)];
    self.textBox.backgroundColor=[UIColor whiteColor];self.textBox.layer.cornerRadius=8;
    self.textBox.font=[UIFont systemFontOfSize:14];[scroll addSubview:self.textBox];
    [self button:@"读取剪贴板" frame:CGRectMake(15,378,133,37) action:@selector(shareClipboard) on:scroll];
    [self button:@"复制文字" frame:CGRectMake(157,378,113,37) action:@selector(copyReceived) on:scroll];
    [self label:@"传输文件（轻点可预览 / 分享）" frame:CGRectMake(15,431,w-30,25) font:[UIFont boldSystemFontOfSize:15] on:scroll];
    self.table=[[UITableView alloc] initWithFrame:CGRectMake(15,460,w-30,190) style:UITableViewStylePlain];
    self.table.layer.cornerRadius=8;self.table.dataSource=self;self.table.delegate=self;self.table.rowHeight=47;
    [scroll addSubview:self.table];scroll.contentSize=CGSizeMake(w,688);
    [self reloadFiles];self.window.rootViewController=self.root;[self.window makeKeyAndVisible];
    return YES;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section{return self.items.count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *cell=[t dequeueReusableCellWithIdentifier:@"file"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"file"];
    NSString *name=self.items[p.row];cell.textLabel.text=name;
    cell.textLabel.font=[UIFont systemFontOfSize:13];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    NSDictionary *attrs=[[NSFileManager defaultManager] attributesOfItemAtPath:[PDDir() stringByAppendingPathComponent:name] error:NULL];
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%.1f KB",[attrs fileSize]/1024.0];
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES];
    NSString *file=[PDDir() stringByAppendingPathComponent:self.items[p.row]];
    self.document=[UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:file]];
    if(![self.document presentOptionsMenuFromRect:[t rectForRowAtIndexPath:p] inView:t animated:YES])
        self.state.text=@"可通过 iFile 打开 /var/mobile/Documents/PocketDrop";
}
- (void)applicationWillTerminate:(UIApplication *)app {[self stop];}
- (void)applicationDidEnterBackground:(UIApplication *)app {[self stop];}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass([PDApp class]));}}
