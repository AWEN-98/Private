#import "XFViewController.h"
#import <Security/Security.h>

@interface XFViewController ()
@property(nonatomic,strong) UITextView *chat;
@property(nonatomic,strong) UITextField *message;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *sendButton;
@property(nonatomic,strong) NSMutableArray *history;
@end

@implementation XFViewController

- (NSArray *)providers {
    return @[
      @{@"id":@"deepseek", @"name":@"DeepSeek", @"url":@"https://api.deepseek.com/chat/completions", @"model":@"deepseek-flash"},
      @{@"id":@"qwen", @"name":@"通义千问", @"url":@"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", @"model":@"qwen-plus"},
      @{@"id":@"kimi", @"name":@"Kimi", @"url":@"https://api.moonshot.cn/v1/chat/completions", @"model":@"moonshot-v1-8k"},
      @{@"id":@"glm", @"name":@"智谱 GLM", @"url":@"https://open.bigmodel.cn/api/paas/v4/chat/completions", @"model":@"glm-4-flash"},
      @{@"id":@"minimax", @"name":@"MiniMax", @"url":@"https://api.minimax.io/v1/chat/completions", @"model":@"MiniMax-M2"},
      @{@"id":@"custom", @"name":@"自定义兼容 API", @"url":@"", @"model":@""}
    ];
}

- (NSDictionary *)selectedProvider {
    NSString *providerId = [[NSUserDefaults standardUserDefaults] stringForKey:@"direct_provider"];
    for (NSDictionary *provider in [self providers]) {
        if ([provider[@"id"] isEqualToString:providerId]) return provider;
    }
    return [self providers][0];
}

- (BOOL)isDirect {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"connect_mode"] isEqualToString:@"direct"];
}

- (NSMutableDictionary *)keychainQueryForProvider:(NSString *)provider {
    return [@{
       (__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
       (__bridge id)kSecAttrService:@"com.finn.xiaofeiagent.api",
       (__bridge id)kSecAttrAccount:provider
    } mutableCopy];
}

- (NSString *)keyForProvider:(NSString *)provider {
    NSMutableDictionary *query=[self keychainQueryForProvider:provider];
    query[(__bridge id)kSecReturnData]=@YES;
    query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
    CFTypeRef found=NULL;
    OSStatus result=SecItemCopyMatching((__bridge CFDictionaryRef)query,&found);
    if(result!=errSecSuccess || !found) return nil;
    NSData *data=(__bridge_transfer NSData *)found;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (BOOL)saveKey:(NSString *)key forProvider:(NSString *)provider {
    SecItemDelete((__bridge CFDictionaryRef)[self keychainQueryForProvider:provider]);
    if (!key.length) return YES;
    NSMutableDictionary *query=[self keychainQueryForProvider:provider];
    query[(__bridge id)kSecValueData]=[key dataUsingEncoding:NSUTF8StringEncoding];
    query[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)query,NULL)==errSecSuccess;
}

- (void)refreshStatus {
    if ([self isDirect]) {
       NSDictionary *p=[self selectedProvider];
       self.status.text=[NSString stringWithFormat:@"直连：%@ · %@",p[@"name"],[self keyForProvider:p[@"id"]]?@"已保存密钥":@"请填写密钥"];
    } else {
       self.status.text=@"电脑服务端模式 · 点击设置连接";
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.history=[NSMutableArray array];
    self.view.backgroundColor=[UIColor colorWithWhite:0.96 alpha:1];
    UILabel *heading=[[UILabel alloc] initWithFrame:CGRectMake(14,25,180,37)];
    heading.text=@"小斐 AI"; heading.font=[UIFont boldSystemFontOfSize:23]; [self.view addSubview:heading];
    UIButton *settings=[UIButton buttonWithType:UIButtonTypeSystem];
    settings.frame=CGRectMake(self.view.bounds.size.width-78,25,70,37);
    settings.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
    [settings setTitle:@"设置" forState:UIControlStateNormal];
    [settings addTarget:self action:@selector(settingsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:settings];
    self.status=[[UILabel alloc] initWithFrame:CGRectMake(14,64,self.view.bounds.size.width-28,22)];
    self.status.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.status.font=[UIFont systemFontOfSize:12]; [self.view addSubview:self.status];
    self.chat=[[UITextView alloc] initWithFrame:CGRectMake(10,91,self.view.bounds.size.width-20,self.view.bounds.size.height-165)];
    self.chat.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.chat.editable=NO; self.chat.font=[UIFont systemFontOfSize:16];
    self.chat.text=@"欢迎使用小斐 AI。\n点击「设置」，选择国产模型直连。只需配置一次密钥，以后直接打开就能聊天。";
    [self.view addSubview:self.chat];
    self.message=[[UITextField alloc] initWithFrame:CGRectMake(10,self.view.bounds.size.height-64,self.view.bounds.size.width-87,42)];
    self.message.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth;
    self.message.borderStyle=UITextBorderStyleRoundedRect; self.message.placeholder=@"输入中文问题";
    self.message.delegate=self; [self.view addSubview:self.message];
    self.sendButton=[UIButton buttonWithType:UIButtonTypeSystem];
    self.sendButton.frame=CGRectMake(self.view.bounds.size.width-73,self.view.bounds.size.height-64,66,42);
    self.sendButton.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleTopMargin;
    [self.sendButton setTitle:@"发送" forState:UIControlStateNormal];
    [self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.sendButton];
    [self refreshStatus];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [self sendTapped]; return NO;
}

- (void)settingsTapped {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"连接方式"
       message:@"推荐国产 AI 直连：无需电脑，使用手机网络即可聊天"
       preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:@"国产 AI 直连（推荐）"
       style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self selectProvider];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"电脑服务端（旧方式）"
       style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self showComputerSettings];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)selectProvider {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"选择 AI 模型"
       message:@"需要对应厂商的 API Key，API 调用可能收费。"
       preferredStyle:UIAlertControllerStyleAlert];
    for (NSDictionary *provider in [self providers]) {
        [sheet addAction:[UIAlertAction actionWithTitle:provider[@"name"]
          style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self configureProvider:provider];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)configureProvider:(NSDictionary *)provider {
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    NSString *pid=provider[@"id"];
    NSString *name=provider[@"name"];
    NSString *storedModel=[defaults stringForKey:[@"model_" stringByAppendingString:pid]];
    NSString *storedURL=[defaults stringForKey:@"direct_url_custom"];
    BOOL custom=[pid isEqualToString:@"custom"];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"配置 %@",name]
       message:@"API Key 存储在手机钥匙串中，不会显示在聊天记录里。"
       preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
       f.placeholder=@"模型名称"; f.text=storedModel.length?storedModel:provider[@"model"];
       f.autocorrectionType=UITextAutocorrectionTypeNo;
       f.autocapitalizationType=UITextAutocapitalizationTypeNone;
    }];
    if (custom) {
       [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
          f.placeholder=@"https://域名/v1/chat/completions";
          f.text=storedURL; f.autocorrectionType=UITextAutocorrectionTypeNo;
          f.autocapitalizationType=UITextAutocapitalizationTypeNone;
          f.keyboardType=UIKeyboardTypeURL;
       }];
    }
    BOOL already=[self keyForProvider:pid].length>0;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder=already?@"已保存密钥，留空则不修改":@"粘贴 API Key";
        f.secureTextEntry=YES; f.autocapitalizationType=UITextAutocapitalizationTypeNone;
        f.autocorrectionType=UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (already) {
       [alert addAction:[UIAlertAction actionWithTitle:@"删除此模型密钥" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
          [self saveKey:@"" forProvider:pid];
          [self refreshStatus];
       }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"保存并使用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *model=[alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *url=custom?[alert.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]:provider[@"url"];
        NSString *newKey=alert.textFields[custom?2:1].text;
        if (!model.length || ![url hasPrefix:@"https://"]) {
           self.status.text=@"模型不能为空，接口必须使用 HTTPS"; return;
        }
        if (newKey.length && ![self saveKey:newKey forProvider:pid]) {
           self.status.text=@"保存密钥失败，请检查系统钥匙串"; return;
        }
        if (![self keyForProvider:pid].length) {
           self.status.text=@"请先填写 API Key"; return;
        }
        [defaults setObject:@"direct" forKey:@"connect_mode"];
        [defaults setObject:pid forKey:@"direct_provider"];
        [defaults setObject:model forKey:[@"model_" stringByAppendingString:pid]];
        if(custom) [defaults setObject:url forKey:@"direct_url_custom"];
        [defaults synchronize];
        [self.history removeAllObjects];
        [self refreshStatus];
        self.chat.text=[self.chat.text stringByAppendingFormat:@"\n\n已选择 %@，现在可以直接发送消息。",name];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showComputerSettings {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"连接 Windows AI 服务端"
       message:@"仅限可信的家庭 Wi-Fi；密钥保存在电脑端。"
       preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder=@"http://192.168.1.2:8765";
        f.text=[[NSUserDefaults standardUserDefaults] stringForKey:@"server"];
        f.autocapitalizationType=UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder=@"配对码";
        f.text=[[NSUserDefaults standardUserDefaults] stringForKey:@"pair"];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *url=[alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *pair=alert.textFields[1].text;
        if (![url hasPrefix:@"http://"] || !pair.length) {
            self.status.text=@"需要电脑局域网地址和配对码"; return;
        }
        NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
        [d setObject:url forKey:@"server"];
        [d setObject:pair forKey:@"pair"];
        [d setObject:@"computer" forKey:@"connect_mode"];
        [d synchronize];
        [self.history removeAllObjects];
        [self refreshStatus];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)sendTapped {
    NSString *content=[self.message.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!content.length) return;
    if (![self isDirect] && ![[[NSUserDefaults standardUserDefaults] stringForKey:@"server"] length]) {
        [self settingsTapped]; return;
    }
    if ([self isDirect] && ![[self keyForProvider:[self selectedProvider][@"id"]] length]) {
        [self selectProvider]; return;
    }
    [self.message resignFirstResponder];
    self.message.text=@"";
    self.chat.text=[self.chat.text stringByAppendingFormat:@"\n\n我：%@",content];
    self.status.text=@"正在请求 AI…";
    self.sendButton.enabled=NO;
    if ([self isDirect]) [self sendDirect:content];
    else [self sendComputer:content];
}

- (void)request:(NSMutableURLRequest *)request finishedForMessage:(NSString *)content direct:(BOOL)direct {
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        self.sendButton.enabled=YES;
        if (error) {
           if (error.code==NSURLErrorSecureConnectionFailed ||
               error.code==NSURLErrorServerCertificateUntrusted ||
               error.code==NSURLErrorServerCertificateHasBadDate ||
               error.code==NSURLErrorServerCertificateHasUnknownRoot) {
               self.status.text=@"iOS 8 无法验证 HTTPS 证书，请使用电脑服务端模式";
           } else {
               self.status.text=[NSString stringWithFormat:@"网络错误：%ld",(long)error.code];
           }
           return;
        }
        NSError *parseError=nil;
        id parsed=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError]:nil;
        if (![parsed isKindOfClass:[NSDictionary class]]) {
            self.status.text=@"服务器返回了无效数据"; return;
        }
        NSDictionary *json=(NSDictionary *)parsed;
        NSInteger status=[response isKindOfClass:[NSHTTPURLResponse class]]?[(NSHTTPURLResponse *)response statusCode]:200;
        NSString *reply=nil;
        if (direct) {
            id choices=json[@"choices"];
            if ([choices isKindOfClass:[NSArray class]] && [choices count]>0) {
                id first=[choices objectAtIndex:0];
                if ([first isKindOfClass:[NSDictionary class]]) {
                    id message=first[@"message"];
                    if ([message isKindOfClass:[NSDictionary class]]) {
                        id body=message[@"content"];
                        if ([body isKindOfClass:[NSString class]]) reply=body;
                    }
                }
            }
        } else {
            if ([json[@"reply"] isKindOfClass:[NSString class]]) reply=json[@"reply"];
        }
        if (status<200 || status>=300) {
            NSString *details=nil;
            id e=json[@"error"];
            if ([e isKindOfClass:[NSDictionary class]]) details=e[@"message"];
            if (![details isKindOfClass:[NSString class]]) details=json[@"detail"];
            self.status.text=[NSString stringWithFormat:@"接口错误 HTTP %ld：%@",(long)status,
                [details isKindOfClass:[NSString class]]?[details substringToIndex:MIN((NSUInteger)36,details.length)]:@"请检查模型和密钥"];
            return;
        }
        if (![reply isKindOfClass:[NSString class]] || !reply.length) {
            self.status.text=@"模型没有返回可用的文本"; return;
        }
        if (direct) {
            [self.history addObject:@{@"role":@"user",@"content":content}];
            [self.history addObject:@{@"role":@"assistant",@"content":reply}];
            while (self.history.count>12) [self.history removeObjectAtIndex:0];
        }
        self.chat.text=[self.chat.text stringByAppendingFormat:@"\n\n小斐：%@",reply];
        self.status.text=@"完成";
        [self.chat scrollRangeToVisible:NSMakeRange(self.chat.text.length,0)];
    }];
}

- (void)sendDirect:(NSString *)content {
    NSDictionary *provider=[self selectedProvider];
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    NSString *pid=provider[@"id"];
    NSString *urlStr=[pid isEqualToString:@"custom"]?[d stringForKey:@"direct_url_custom"]:provider[@"url"];
    NSString *model=[d stringForKey:[@"model_" stringByAppendingString:pid]];
    if (!model.length) model=provider[@"model"];
    NSURL *url=[NSURL URLWithString:urlStr];
    if (!url || ![[url scheme] isEqualToString:@"https"] || !model.length) {
        self.status.text=@"模型接口地址无效"; self.sendButton.enabled=YES; return;
    }
    NSMutableArray *messages=[NSMutableArray arrayWithObject:@{@"role":@"system",@"content":@"你是小斐，用简洁自然的中文回答用户。"}];
    [messages addObjectsFromArray:self.history];
    [messages addObject:@{@"role":@"user",@"content":content}];
    NSDictionary *body=@{@"model":model,@"messages":messages,@"stream":@NO};
    NSData *json=[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    if (!json) { self.status.text=@"消息编码失败"; self.sendButton.enabled=YES; return; }
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod=@"POST"; req.timeoutInterval=100; req.HTTPBody=json;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[@"Bearer " stringByAppendingString:[self keyForProvider:pid]] forHTTPHeaderField:@"Authorization"];
    [self request:req finishedForMessage:content direct:YES];
}

- (void)sendComputer:(NSString *)content {
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    NSString *base=[d stringForKey:@"server"];
    NSString *code=[d stringForKey:@"pair"];
    if (!base.length || !code.length) { self.status.text=@"先填写电脑地址和配对码"; self.sendButton.enabled=YES; return; }
    NSURL *url=[NSURL URLWithString:[base stringByAppendingString:@"/api/chat"]];
    if (!url) { self.status.text=@"电脑地址无效"; self.sendButton.enabled=YES; return; }
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod=@"POST"; req.timeoutInterval=100;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:code forHTTPHeaderField:@"X-Access-Token"];
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"text":content,@"mode":@"chat"} options:0 error:NULL];
    [self request:req finishedForMessage:content direct:NO];
}
@end
