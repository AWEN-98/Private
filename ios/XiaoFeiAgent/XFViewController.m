#import "XFViewController.h"
#import "XFModelsController.h"
#import "XFChatStore.h"
#import "XFHistoryController.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

@interface XFViewController () <UIImagePickerControllerDelegate,UINavigationControllerDelegate,AVAudioRecorderDelegate,UIDocumentPickerDelegate,NSURLConnectionDataDelegate>
@property(nonatomic,strong) UITextView *chat;
@property(nonatomic,strong) UITextField *message;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *sendButton;
@property(nonatomic,strong) UIScrollView *tools;
@property(nonatomic,strong) NSMutableArray *history;
@property(nonatomic,copy) NSString *conversationID;
@property(nonatomic,strong) UIImage *pendingImage;
@property(nonatomic,copy) NSString *pendingFileText;
@property(nonatomic,copy) NSString *lastAnswer;
@property(nonatomic,strong) AVAudioRecorder *recorder;
@property(nonatomic,strong) AVAudioPlayer *player;
@property(nonatomic,strong) NSURLConnection *connection;
@property(nonatomic,strong) NSMutableData *streamBuffer;
@property(nonatomic,strong) NSMutableString *streamText;
@property(nonatomic,copy) NSString *sendingContent;
@property(nonatomic,assign) NSInteger httpCode;
@property(nonatomic,assign) BOOL isWorking;
@property(nonatomic,assign) BOOL isRecording;
@end

@implementation XFViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor colorWithRed:0.96 green:0.97 blue:0.985 alpha:1];
    self.history=[NSMutableArray array];
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;

    UIButton *sessions=[UIButton buttonWithType:UIButtonTypeSystem];
    sessions.frame=CGRectMake(5,24,62,40);
    [sessions setTitle:@"会话" forState:UIControlStateNormal];
    [sessions addTarget:self action:@selector(historyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:sessions];

    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(69,24,w-138,40)];
    title.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    title.font=[UIFont boldSystemFontOfSize:19];
    title.textAlignment=NSTextAlignmentCenter;title.text=@"小斐 AI";
    [self.view addSubview:title];

    UIButton *models=[UIButton buttonWithType:UIButtonTypeSystem];
    models.frame=CGRectMake(w-70,24,68,40);
    models.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
    [models setTitle:@"模型" forState:UIControlStateNormal];
    [models addTarget:self action:@selector(modelsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:models];

    self.status=[[UILabel alloc] initWithFrame:CGRectMake(12,65,w-24,20)];
    self.status.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.status.font=[UIFont systemFontOfSize:11];self.status.textColor=[UIColor darkGrayColor];
    [self.view addSubview:self.status];

    self.chat=[[UITextView alloc] initWithFrame:CGRectMake(9,89,w-18,h-237)];
    self.chat.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.chat.editable=NO;self.chat.font=[UIFont systemFontOfSize:15];
    self.chat.backgroundColor=[UIColor whiteColor];
    self.chat.layer.cornerRadius=7;
    self.chat.text=@"欢迎使用小斐 AI。\n先到「模型」添加文字模型，再发送问题。\n图片、语音、联网、绘图可配置不同的 API。";
    [self.view addSubview:self.chat];

    self.tools=[[UIScrollView alloc] initWithFrame:CGRectMake(5,h-139,w-10,48)];
    self.tools.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth;
    self.tools.showsHorizontalScrollIndicator=NO;
    [self.view addSubview:self.tools];
    NSArray *items=@[@[@"新对话",@"new"],@[@"图片",@"photo"],@[@"文本",@"file"],
      @[@"录音",@"record"],@[@"朗读",@"tts"],@[@"生图",@"image"],@[@"联网",@"web"]];
    CGFloat x=2;
    for(NSArray *it in items) {
        UIButton *btn=[UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame=CGRectMake(x,4,59,37);
        btn.titleLabel.font=[UIFont systemFontOfSize:14];
        [btn setTitle:it[0] forState:UIControlStateNormal];
        btn.layer.borderWidth=0.5;
        btn.layer.borderColor=[UIColor lightGrayColor].CGColor;
        btn.layer.cornerRadius=6;
        [btn setAccessibilityIdentifier:it[1]];
        [btn addTarget:self action:@selector(toolTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.tools addSubview:btn];
        x+=63;
    }
    self.tools.contentSize=CGSizeMake(x+2,48);

    self.message=[[UITextField alloc] initWithFrame:CGRectMake(10,h-83,w-93,49)];
    self.message.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth;
    self.message.borderStyle=UITextBorderStyleRoundedRect;
    self.message.font=[UIFont systemFontOfSize:15];
    self.message.placeholder=@"输入问题或生图描述";
    self.message.delegate=self;
    [self.view addSubview:self.message];

    self.sendButton=[UIButton buttonWithType:UIButtonTypeSystem];
    self.sendButton.frame=CGRectMake(w-76,h-83,69,49);
    self.sendButton.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleTopMargin;
    [self.sendButton setTitle:@"发送" forState:UIControlStateNormal];
    [self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.sendButton];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
      name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
      name:UIKeyboardWillHideNotification object:nil];

    NSArray *existing=[XFChatStore conversations];
    self.conversationID=existing.count?existing[0][@"id"]:[XFChatStore createConversation];
    [self loadConversation:self.conversationID];
    [self refreshStatus];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.connection cancel];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStatus];
}
- (void)refreshStatus {
    NSDictionary *profile=[XFModelsController activeProfileForCapability:@"chat"];
    NSString *name=profile[@"name"];
    self.status.text=name.length?[NSString stringWithFormat:@"聊天模型：%@ · %@",name,self.isWorking?@"处理中":@"已就绪"]:@"尚未选择聊天模型，点击右上角「模型」";
}
- (void)keyboardWillShow:(NSNotification *)n {
    CGRect key=[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat keyboardHeight=MIN(key.size.height,self.view.bounds.size.height/2);
    [self layoutForKeyboard:keyboardHeight];
}
- (void)keyboardWillHide:(NSNotification *)n {[self layoutForKeyboard:0];}
- (void)layoutForKeyboard:(CGFloat)height {
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    self.tools.frame=CGRectMake(5,h-139-height,w-10,48);
    self.message.frame=CGRectMake(10,h-83-height,w-93,49);
    self.sendButton.frame=CGRectMake(w-76,h-83-height,69,49);
    self.chat.frame=CGRectMake(9,89,w-18,MAX(100,h-237-height));
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { [self sendTapped];return NO;}
- (void)showAlert:(NSString *)title detail:(NSString *)detail {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)modelsTapped {
    [self.message resignFirstResponder];
    XFModelsController *m=[[XFModelsController alloc] initWithStyle:UITableViewStyleGrouped];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:m];
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)historyTapped {
    [self.message resignFirstResponder];
    XFHistoryController *controller=[[XFHistoryController alloc] initWithStyle:UITableViewStylePlain];
    controller.onChoose=^(NSString *cid){[self loadConversation:cid];};
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)loadConversation:(NSString *)cid {
    self.conversationID=cid;
    NSDictionary *item=[XFChatStore conversationForID:cid];
    self.history=[item[@"messages"] mutableCopy]?:[NSMutableArray array];
    self.lastAnswer=nil;
    NSMutableString *display=[NSMutableString string];
    for(NSDictionary *m in self.history) {
        NSString *role=[m[@"role"] isEqualToString:@"user"]?@"我":@"小斐";
        [display appendFormat:@"%@：%@\n\n",role,m[@"content"]];
        if([m[@"role"] isEqualToString:@"assistant"]) self.lastAnswer=m[@"content"];
    }
    self.chat.text=display.length?display:@"新对话已创建，可以开始聊天。";
    self.pendingFileText=nil;self.pendingImage=nil;
}
- (void)appendLine:(NSString *)line {
    self.chat.text=[self.chat.text stringByAppendingFormat:@"\n\n%@",line];
    [self.chat scrollRangeToVisible:NSMakeRange(self.chat.text.length,0)];
}
- (void)addExchange:(NSString *)question answer:(NSString *)answer {
    if(question.length) [self.history addObject:@{@"role":@"user",@"content":question}];
    if(answer.length) [self.history addObject:@{@"role":@"assistant",@"content":answer}];
    [XFChatStore saveConversationID:self.conversationID messages:self.history];
    if(answer.length) self.lastAnswer=answer;
}
- (void)setWorking:(BOOL)value {
    self.isWorking=value;
    [self.sendButton setTitle:value?@"停止":@"发送" forState:UIControlStateNormal];
}
- (void)toolTapped:(UIButton *)button {
    NSString *name=[button accessibilityIdentifier];
    [self.message resignFirstResponder];
    if([name isEqualToString:@"new"]) {[self loadConversation:[XFChatStore createConversation]];return;}
    if([name isEqualToString:@"photo"]) {[self pickImage];return;}
    if([name isEqualToString:@"file"]) {[self pickFile];return;}
    if([name isEqualToString:@"record"]) {[self toggleRecord];return;}
    if([name isEqualToString:@"tts"]) {[self speakLastAnswer];return;}
    if([name isEqualToString:@"image"]) {[self generateImage];return;}
    if([name isEqualToString:@"web"]) {[self sendAsSearch];return;}
}
- (NSDictionary *)profileFor:(NSString *)capability {
    NSDictionary *p=[XFModelsController activeProfileForCapability:capability];
    if(!p) [self showAlert:@"尚未配置" detail:[NSString stringWithFormat:@"请点击「模型」，添加并选择 %@ 的 API。",capability]];
    return p;
}
- (NSString *)secretFor:(NSDictionary *)profile {
    return [XFModelsController secretForProfile:profile];
}
- (NSMutableURLRequest *)requestForProfile:(NSDictionary *)p {
    NSURL *url=[NSURL URLWithString:p[@"endpoint"]];
    if(![[url scheme] isEqualToString:@"https"] || !url.host.length) {
        [self showAlert:@"接口地址无效" detail:@"请在模型管理中填写完整 HTTPS 接口地址。"];return nil;
    }
    NSString *key=[self secretFor:p];
    if(!key.length){[self showAlert:@"缺少密钥" detail:@"请编辑模型配置并填写 API Key。"];return nil;}
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod=@"POST";req.timeoutInterval=120;
    [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    return req;
}
- (void)sendTapped {
    if(self.isWorking) {
        [self.connection cancel];self.connection=nil;
        [self setWorking:NO];self.status.text=@"已停止请求";
        return;
    }
    [self sendChat:NO];
}
- (void)sendAsSearch {
    if(self.isWorking)return;
    [self sendChat:YES];
}
- (void)sendChat:(BOOL)web {
    NSDictionary *profile=[self profileFor:web?@"web":(self.pendingImage?@"vision":@"chat")];
    if(!profile)return;
    NSString *msg=[self.message.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!msg.length && self.pendingImage) msg=@"请详细描述这张图片";
    if(!msg.length && self.pendingFileText.length) msg=@"请分析这份文档";
    if(!msg.length) {self.status.text=@"请先输入问题";return;}
    NSString *sent=msg;
    if(self.pendingFileText.length) {
        msg=[NSString stringWithFormat:@"%@\n\n以下为文档内容：\n%@",msg,self.pendingFileText];
        sent=[sent stringByAppendingString:@" [文本文件]"];
    }
    NSMutableArray *messages=[NSMutableArray arrayWithObject:@{@"role":@"system",@"content":@"你是小斐，中文智能助手。准确回答问题，信息不确定时如实说明。"}];
    NSUInteger start=self.history.count>18?self.history.count-18:0;
    for(NSUInteger i=start;i<self.history.count;i++) [messages addObject:self.history[i]];
    if(self.pendingImage) {
        UIImage *image=self.pendingImage;
        CGFloat maxDimension=640;
        CGFloat scale=MIN(1.0,maxDimension/MAX(image.size.width,image.size.height));
        CGSize target=CGSizeMake(MAX(1,image.size.width*scale),MAX(1,image.size.height*scale));
        UIGraphicsBeginImageContextWithOptions(target,YES,1);
        [image drawInRect:CGRectMake(0,0,target.width,target.height)];
        UIImage *resized=UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSString *encoded=[UIImageJPEGRepresentation(resized,0.64) base64EncodedStringWithOptions:0];
        NSString *uri=[@"data:image/jpeg;base64," stringByAppendingString:encoded];
        [messages addObject:@{@"role":@"user",@"content":@[
            @{@"type":@"text",@"text":msg},
            @{@"type":@"image_url",@"image_url":@{@"url":uri}}
        ]}];
        sent=[sent stringByAppendingString:@" [图片]"];
    } else {
        [messages addObject:@{@"role":@"user",@"content":msg}];
    }
    NSMutableURLRequest *req=[self requestForProfile:profile];if(!req)return;
    NSMutableDictionary *payload=[@{@"model":profile[@"model"],@"messages":messages,@"stream":@YES} mutableCopy];
    if(web) payload[@"web_search_options"]=@{};
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    self.sendingContent=sent;
    [self.message resignFirstResponder];self.message.text=@"";
    self.pendingFileText=nil;self.pendingImage=nil;
    [self appendLine:[NSString stringWithFormat:@"我：%@",sent]];
    self.streamBuffer=[NSMutableData data];self.streamText=[NSMutableString string];self.httpCode=0;
    [self setWorking:YES];self.status.text=web?@"正在联网搜索…":@"正在生成回复…";
    self.connection=[[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:YES];
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    self.httpCode=[response isKindOfClass:[NSHTTPURLResponse class]]?[(NSHTTPURLResponse *)response statusCode]:0;
    [self.streamBuffer setLength:0];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.streamBuffer appendData:data];
    if(self.httpCode>=400)return;
    NSData *separator=[@"\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    while(self.streamBuffer.length) {
        NSRange boundary=[self.streamBuffer rangeOfData:separator options:0 range:NSMakeRange(0,self.streamBuffer.length)];
        if(boundary.location==NSNotFound) break;
        NSData *part=[self.streamBuffer subdataWithRange:NSMakeRange(0,boundary.location)];
        NSUInteger consumed=boundary.location+boundary.length;
        NSData *remaining=[self.streamBuffer subdataWithRange:NSMakeRange(consumed,self.streamBuffer.length-consumed)];
        self.streamBuffer=[remaining mutableCopy];
        NSString *event=[[NSString alloc] initWithData:part encoding:NSUTF8StringEncoding];
        NSArray *lines=[event componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for(NSString *line in lines) {
            if(![line hasPrefix:@"data:"])continue;
            NSString *raw=[[line substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if([raw isEqualToString:@"[DONE]"])continue;
            NSData *jsonData=[raw dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *json=[NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
            NSArray *choices=[json isKindOfClass:[NSDictionary class]]?json[@"choices"]:nil;
            if(![choices isKindOfClass:[NSArray class]] || !choices.count)continue;
            NSDictionary *choice=choices[0];
            NSDictionary *delta=[choice[@"delta"] isKindOfClass:[NSDictionary class]]?choice[@"delta"]:nil;
            NSString *chunk=[delta[@"content"] isKindOfClass:[NSString class]]?delta[@"content"]:nil;
            if(chunk.length){
                [self.streamText appendString:chunk];
                [self showStreamingAnswer];
            }
        }
    }
}
- (void)showStreamingAnswer {
    NSString *txt=[self.chat.text copy];
    NSRange r=[txt rangeOfString:@"\n\n小斐（回复中）："];
    if(r.location!=NSNotFound) txt=[txt substringToIndex:r.location];
    self.chat.text=[txt stringByAppendingFormat:@"\n\n小斐（回复中）：%@",self.streamText];
    [self.chat scrollRangeToVisible:NSMakeRange(self.chat.text.length,0)];
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if(connection!=self.connection)return;
    self.connection=nil;[self setWorking:NO];
    self.status.text=[NSString stringWithFormat:@"网络失败 %ld；旧 iOS 可能不兼容厂商 HTTPS",(long)error.code];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if(connection!=self.connection)return;
    self.connection=nil;[self setWorking:NO];
    if(self.httpCode>=400) {
        NSDictionary *error=[NSJSONSerialization JSONObjectWithData:self.streamBuffer options:0 error:NULL];
        NSString *reason=nil;
        if([error isKindOfClass:[NSDictionary class]]) {
            NSDictionary *details=error[@"error"];
            if([details isKindOfClass:[NSDictionary class]])reason=details[@"message"];
        }
        self.status.text=[NSString stringWithFormat:@"API 错误 HTTP %ld %@",(long)self.httpCode,
            [reason isKindOfClass:[NSString class]]?[reason substringToIndex:MIN((NSUInteger)70,reason.length)]:@""];
        return;
    }
    NSString *answer=[self.streamText copy];
    if(!answer.length) {
        NSDictionary *json=[NSJSONSerialization JSONObjectWithData:self.streamBuffer options:0 error:NULL];
        NSArray *choices=[json isKindOfClass:[NSDictionary class]]?json[@"choices"]:nil;
        if([choices isKindOfClass:[NSArray class]] && choices.count) {
            NSDictionary *first=choices[0];
            NSDictionary *message=first[@"message"];
            if([message isKindOfClass:[NSDictionary class]] && [message[@"content"] isKindOfClass:[NSString class]])
                answer=message[@"content"];
        }
    }
    if(!answer.length) {self.status.text=@"API 未返回可用文字，请检查模型是否支持 Chat Completions";return;}
    NSString *txt=[self.chat.text copy];
    NSRange r=[txt rangeOfString:@"\n\n小斐（回复中）："];
    if(r.location!=NSNotFound) txt=[txt substringToIndex:r.location];
    self.chat.text=[txt stringByAppendingFormat:@"\n\n小斐：%@",answer];
    [self.chat scrollRangeToVisible:NSMakeRange(self.chat.text.length,0)];
    [self addExchange:self.sendingContent answer:answer];
    self.status.text=@"回复完成，已保存到历史对话";
}
- (void)pickImage {
    UIImagePickerController *picker=[[UIImagePickerController alloc] init];
    picker.delegate=self;
    picker.sourceType=UIImagePickerControllerSourceTypePhotoLibrary;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *img=info[UIImagePickerControllerOriginalImage];
    self.pendingImage=img;
    [picker dismissViewControllerAnimated:YES completion:nil];
    self.status.text=img?@"已选择图片，发送问题时将使用视觉模型":@"图片读取失败";
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
- (void)pickFile {
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]
         initWithDocumentTypes:@[@"public.plain-text",@"public.text"] inMode:UIDocumentPickerModeImport];
    picker.delegate=self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    NSData *bytes=[NSData dataWithContentsOfURL:url options:0 error:NULL];
    if(!bytes || bytes.length>512*1024) {
        [self showAlert:@"文件过大或无法读取" detail:@"目前只支持 TXT / MD 等纯文本文件，单文件不得超过 512KB。"];return;
    }
    NSString *text=[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
    if(!text) text=[[NSString alloc] initWithData:bytes encoding:NSUTF16StringEncoding];
    if(!text) {[self showAlert:@"文件格式不支持" detail:@"当前版本暂不支持 PDF 的文本提取。"];return;}
    if(text.length>12000) text=[text substringToIndex:12000];
    self.pendingFileText=text;self.status.text=@"文本已添加，发送问题即可分析";
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {}

- (void)toggleRecord {
    if(self.isRecording) {
        [self.recorder stop];self.isRecording=NO;
        [self transcribeRecording];return;
    }
    NSDictionary *p=[self profileFor:@"stt"];if(!p)return;
    AVAudioSession *session=[AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:NULL];
    [session setActive:YES error:NULL];
    [session requestRecordPermission:^(BOOL granted) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if(!granted){[self showAlert:@"没有麦克风权限" detail:@"请在系统设置中允许小斐 AI 录音。"];return;}
            NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"xf-recording.m4a"];
            NSDictionary *settings=@{AVFormatIDKey:@(kAudioFormatMPEG4AAC),
                AVSampleRateKey:@16000,AVNumberOfChannelsKey:@1,
                AVEncoderAudioQualityKey:@(AVAudioQualityMedium)};
            self.recorder=[[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:path] settings:settings error:NULL];
            if(![self.recorder prepareToRecord] || ![self.recorder recordForDuration:60]){
                [self showAlert:@"录音失败" detail:@"请检查系统麦克风权限与存储空间。"];return;
            }
            self.isRecording=YES;self.status.text=@"正在录音，点击「录音」结束，最长 60 秒";
        }];
    }];
}
- (void)transcribeRecording {
    NSDictionary *p=[self profileFor:@"stt"];if(!p)return;
    NSData *audio=[NSData dataWithContentsOfURL:self.recorder.url];
    if(!audio.length) {self.status.text=@"录音文件为空";return;}
    NSMutableURLRequest *req=[self requestForProfile:p];if(!req)return;
    NSString *boundary=[[NSUUID UUID] UUIDString];
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary] forHTTPHeaderField:@"Content-Type"];
    NSMutableData *body=[NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n%@\r\n",boundary,p[@"model"]] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:audio];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    req.HTTPBody=body;
    self.status.text=@"正在语音识别…";
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *resp,NSData *data,NSError *err){
        if(err){self.status.text=[NSString stringWithFormat:@"语音请求失败 %ld",(long)err.code];return;}
        NSInteger code=[(NSHTTPURLResponse *)resp statusCode];
        NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSString *text=[json isKindOfClass:[NSDictionary class]]?json[@"text"]:nil;
        if(code>=300 || ![text isKindOfClass:[NSString class]]){
            self.status.text=[NSString stringWithFormat:@"语音识别失败 HTTP %ld",(long)code];return;
        }
        self.message.text=text;self.status.text=@"已识别语音，点击发送";
    }];
}
- (void)speakLastAnswer {
    if(!self.lastAnswer.length){self.status.text=@"当前没有可朗读的回答";return;}
    NSDictionary *p=[self profileFor:@"tts"];if(!p)return;
    NSMutableURLRequest *req=[self requestForProfile:p];if(!req)return;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"model":p[@"model"],@"input":[self.lastAnswer substringToIndex:MIN((NSUInteger)2500,self.lastAnswer.length)],
       @"voice":@"alloy",@"response_format":@"mp3"} options:0 error:NULL];
    self.status.text=@"生成语音…";
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *resp,NSData *data,NSError *err){
        if(err){self.status.text=[NSString stringWithFormat:@"朗读连接失败 %ld",(long)err.code];return;}
        NSInteger status=[(NSHTTPURLResponse *)resp statusCode];
        if(status>=300 || !data.length){self.status.text=[NSString stringWithFormat:@"朗读接口 HTTP %ld",(long)status];return;}
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
        self.player=[[AVAudioPlayer alloc] initWithData:data error:NULL];
        if(![self.player play]) {self.status.text=@"语音格式无法播放";return;}
        self.status.text=@"正在朗读";
    }];
}
- (void)generateImage {
    if(self.isWorking) return;
    NSDictionary *p=[self profileFor:@"image"];if(!p)return;
    NSString *prompt=[self.message.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!prompt.length) {self.status.text=@"请先输入生图描述";return;}
    NSMutableURLRequest *req=[self requestForProfile:p];if(!req)return;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"model":p[@"model"],@"prompt":prompt,
       @"n":@1,@"size":@"1024x1024"} options:0 error:NULL];
    self.status.text=@"正在生成图片…";
    [self setWorking:YES];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *resp,NSData *data,NSError *err){
        [self setWorking:NO];
        if(err){self.status.text=[NSString stringWithFormat:@"生图网络失败 %ld",(long)err.code];return;}
        NSInteger code=[(NSHTTPURLResponse *)resp statusCode];
        NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSArray *results=[json isKindOfClass:[NSDictionary class]]?json[@"data"]:nil;
        NSDictionary *first=[results isKindOfClass:[NSArray class]] && results.count?results[0]:nil;
        NSString *base64=first[@"b64_json"];
        if(code>=300 || ![base64 isKindOfClass:[NSString class]]) {
            self.status.text=[NSString stringWithFormat:@"生图失败 HTTP %ld（要求返回 b64_json）",(long)code];return;
        }
        NSData *bytes=[[NSData alloc] initWithBase64EncodedString:base64 options:0];
        UIImage *image=[UIImage imageWithData:bytes];
        if(!image){self.status.text=@"图片解码失败";return;}
        [self showGeneratedImage:image];
        [self appendLine:[NSString stringWithFormat:@"已生成图片：%@",prompt]];
        self.status.text=@"图片已生成，可保存到相册";
    }];
}
- (void)showGeneratedImage:(UIImage *)image {
    UIViewController *viewer=[[UIViewController alloc] init];
    viewer.view.backgroundColor=[UIColor blackColor];
    UIImageView *iv=[[UIImageView alloc] initWithFrame:viewer.view.bounds];
    iv.image=image;iv.contentMode=UIViewContentModeScaleAspectFit;
    iv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [viewer.view addSubview:iv];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:viewer];
    viewer.title=@"生成图片";
    viewer.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(closeImageViewer)];
    viewer.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"保存相册" style:UIBarButtonItemStylePlain
        target:self action:@selector(saveGeneratedImage)];
    objc_setAssociatedObject(viewer,@"XFGeneratedImage",image,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)closeImageViewer {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)saveGeneratedImage {
    UIViewController *vc=((UINavigationController *)self.presentedViewController).topViewController;
    UIImage *image=objc_getAssociatedObject(vc,@"XFGeneratedImage");
    if(image){UIImageWriteToSavedPhotosAlbum(image,nil,NULL,NULL);vc.title=@"已请求保存到相册";}
}
@end
