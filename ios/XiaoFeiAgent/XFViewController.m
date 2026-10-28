#import "XFViewController.h"
@interface XFViewController ()
@property(nonatomic,strong) UITextView *chat;
@property(nonatomic,strong) UITextField *message;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *sendButton;
@end
@implementation XFViewController
- (void)viewDidLoad {
 [super viewDidLoad];
 self.view.backgroundColor=[UIColor colorWithWhite:0.96 alpha:1];
 UILabel *heading=[[UILabel alloc] initWithFrame:CGRectMake(14,25,180,37)];
 heading.text=@"小斐 AI"; heading.font=[UIFont boldSystemFontOfSize:23]; [self.view addSubview:heading];
 UIButton *settings=[UIButton buttonWithType:UIButtonTypeSystem];
 settings.frame=CGRectMake(self.view.bounds.size.width-78,25,70,37);
 settings.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
 [settings setTitle:@"设置" forState:UIControlStateNormal]; [settings addTarget:self action:@selector(settingsTapped) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:settings];
 self.status=[[UILabel alloc] initWithFrame:CGRectMake(14,64,self.view.bounds.size.width-28,22)];
 self.status.autoresizingMask=UIViewAutoresizingFlexibleWidth; self.status.font=[UIFont systemFontOfSize:12];
 self.status.text=@"请先设置电脑 IP 和配对码"; [self.view addSubview:self.status];
 self.chat=[[UITextView alloc] initWithFrame:CGRectMake(10,91,self.view.bounds.size.width-20,self.view.bounds.size.height-165)];
 self.chat.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 self.chat.editable=NO; self.chat.font=[UIFont systemFontOfSize:16];
 self.chat.text=@"欢迎使用小斐 AI。\n在设置中填写你的 Windows AI 服务端地址及配对码。";
 [self.view addSubview:self.chat];
 self.message=[[UITextField alloc] initWithFrame:CGRectMake(10,self.view.bounds.size.height-64,self.view.bounds.size.width-87,42)];
 self.message.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth;
 self.message.borderStyle=UITextBorderStyleRoundedRect; self.message.placeholder=@"输入中文问题";
 self.message.delegate=self; [self.view addSubview:self.message];
 self.sendButton=[UIButton buttonWithType:UIButtonTypeSystem];
 self.sendButton.frame=CGRectMake(self.view.bounds.size.width-73,self.view.bounds.size.height-64,66,42);
 self.sendButton.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleTopMargin;
 [self.sendButton setTitle:@"发送" forState:UIControlStateNormal]; [self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:self.sendButton];
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { [self sendTapped]; return NO; }
- (void)settingsTapped {
 UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"连接 Windows AI 服务端" message:@"仅限可信的家庭 Wi-Fi；密钥保存在电脑端。" preferredStyle:UIAlertControllerStyleAlert];
 [alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder=@"http://192.168.1.2:8765"; f.text=[[NSUserDefaults standardUserDefaults] stringForKey:@"server"]; f.autocapitalizationType=UITextAutocapitalizationTypeNone; }];
 [alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder=@"配对码"; f.text=[[NSUserDefaults standardUserDefaults] stringForKey:@"pair"]; }];
 [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
 [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
  NSString *url=[alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (![url hasPrefix:@"http://"]) { self.status.text=@"地址必须以 http:// 开头"; return; }
  NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
  [d setObject:url forKey:@"server"]; [d setObject:alert.textFields[1].text forKey:@"pair"]; [d synchronize];
  self.status.text=@"设置已保存"; }]];
 [self presentViewController:alert animated:YES completion:nil];
}
- (void)sendTapped {
 NSString *content=[self.message.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
 if (!content.length) return;
 NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
 NSString *base=[d stringForKey:@"server"]; NSString *code=[d stringForKey:@"pair"];
 if (!base.length || !code.length) { [self settingsTapped]; return; }
 [self.message resignFirstResponder]; self.message.text=@"";
 self.chat.text=[self.chat.text stringByAppendingFormat:@"\n\n我：%@",content];
 self.status.text=@"正在请求 AI…"; self.sendButton.enabled=NO;
 NSURL *url=[NSURL URLWithString:[base stringByAppendingString:@"/api/chat"]];
 if (!url) { self.status.text=@"地址错误"; self.sendButton.enabled=YES; return; }
 NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];
 request.HTTPMethod=@"POST"; request.timeoutInterval=120;
 [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
 [request setValue:code forHTTPHeaderField:@"X-Access-Token"];
 request.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"text":content,@"mode":@"chat"} options:0 error:NULL];
 [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
   self.sendButton.enabled=YES;
   if (error) { self.status.text=@"连接失败，检查 Wi-Fi 和电脑服务端"; return; }
   NSDictionary *json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
   if (![(id)json isKindOfClass:[NSDictionary class]]) { self.status.text=@"服务端返回数据有误"; return; }
   NSString *reply=[json objectForKey:@"reply"];
   if (![reply isKindOfClass:[NSString class]]) reply=[json objectForKey:@"detail"];
   if (![reply isKindOfClass:[NSString class]]) reply=@"服务器没有返回有效回答";
   self.chat.text=[self.chat.text stringByAppendingFormat:@"\n\n小斐：%@",reply];
   self.status.text=@"完成";
 }];
}
@end
