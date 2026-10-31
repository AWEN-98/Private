#import "DLAccountSession.h"
#import <CoreImage/CoreImage.h>
#import <math.h>

static NSString *DLLoginText(id v){return [v isKindOfClass:NSString.class]?v:([v respondsToSelector:@selector(stringValue)]?[v stringValue]:@"");}
@interface DLLoginController ()
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIImageView *qr;
@property(nonatomic,strong) UIButton *refresh;
@property(nonatomic,strong) NSTimer *pollTimer;
@property(nonatomic,copy) NSString *token;
@property(nonatomic,assign) NSUInteger generation;
@property(nonatomic,assign) NSInteger provider;
@property(nonatomic,copy) NSString *qrFailureReason;
@property(nonatomic,assign) BOOL polling;
@property(nonatomic,assign) BOOL scanned;
@property(nonatomic,assign) BOOL completing;
@property(nonatomic,strong) NSDate *deadline;
@end
@implementation DLLoginController
- (BOOL)prefersStatusBarHidden{return NO;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskPortrait;}
- (UIButton *)button:(NSString *)title action:(SEL)action frame:(CGRect)frame parent:(UIView *)parent{
 UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=frame;b.autoresizingMask=UIViewAutoresizingFlexibleWidth;
 [b setTitle:title forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:14];[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];[parent addSubview:b];return b;
}
- (void)viewDidLoad{
 [super viewDidLoad];self.view.backgroundColor=[UIColor colorWithWhite:.07 alpha:1];CGFloat w=self.view.bounds.size.width;
 [self button:@"关闭" action:@selector(close) frame:CGRectMake(8,23,52,36) parent:self.view];
 UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(65,23,w-130,36)];title.text=@"抖音账号";title.textColor=UIColor.whiteColor;title.textAlignment=NSTextAlignmentCenter;title.autoresizingMask=UIViewAutoresizingFlexibleWidth;[self.view addSubview:title];
 UIScrollView *scroll=[[UIScrollView alloc]initWithFrame:CGRectMake(0,64,w,self.view.bounds.size.height-64)];scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;scroll.contentSize=CGSizeMake(w,428);[self.view addSubview:scroll];
 UILabel *hint=[[UILabel alloc]initWithFrame:CGRectMake(20,5,w-40,40)];hint.numberOfLines=2;hint.text=@"无需登录也可以浏览公开视频\n扫码登录可获取账号相关内容";hint.font=[UIFont systemFontOfSize:13];hint.textAlignment=NSTextAlignmentCenter;hint.textColor=UIColor.lightGrayColor;hint.autoresizingMask=UIViewAutoresizingFlexibleWidth;[scroll addSubview:hint];
 self.qr=[[UIImageView alloc]initWithFrame:CGRectMake((w-192)/2,53,192,192)];self.qr.backgroundColor=UIColor.whiteColor;self.qr.contentMode=UIViewContentModeScaleAspectFit;self.qr.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;[scroll addSubview:self.qr];
 self.status=[[UILabel alloc]initWithFrame:CGRectMake(20,253,w-40,70)];self.status.numberOfLines=0;self.status.font=[UIFont systemFontOfSize:13];self.status.textColor=UIColor.whiteColor;self.status.textAlignment=NSTextAlignmentCenter;self.status.autoresizingMask=UIViewAutoresizingFlexibleWidth;[scroll addSubview:self.status];
 self.refresh=[self button:@"生成 / 刷新二维码" action:@selector(startLogin) frame:CGRectMake(20,330,w-40,38) parent:scroll];
 [self button:@"已确认登录，检查账号" action:@selector(verify) frame:CGRectMake(20,370,w-40,36) parent:scroll];
  [self button:@"退出并重新扫码" action:@selector(logout) frame:CGRectMake(20,409,w-40,36) parent:scroll];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(suspend) name:UIApplicationDidEnterBackgroundNotification object:nil];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resume) name:UIApplicationDidBecomeActiveNotification object:nil];
 if(DLAccountSession.shared.hasSession){self.status.text=@"本机保存了账号会话，正在检查…";[self verify];}else [self startLogin];
}
- (void)close{[self suspend];[self dismissViewControllerAnimated:YES completion:nil];}
- (void)suspend{self.generation++;[self.pollTimer invalidate];self.pollTimer=nil;self.polling=NO;self.completing=NO;self.refresh.enabled=YES;}
- (void)resume{if(self.presentedViewController)return;if(self.token.length&&self.deadline.timeIntervalSinceNow>0&&!self.completing){[self.pollTimer invalidate];self.pollTimer=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(poll) userInfo:nil repeats:YES];[self poll];}}
- (void)viewWillDisappear:(BOOL)animated{[self suspend];[super viewWillDisappear:animated];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];[self resume];}
- (NSString *)params{
 NSString *stamp=[NSString stringWithFormat:@"%.0f",floor(NSDate.date.timeIntervalSince1970*1000)];
 if(self.provider==0)return [NSString stringWithFormat:@"aid=10006&service=https%%3A%%2F%%2Fwww.douyin.com%%2Fpay&t=%@",stamp];
 return [NSString stringWithFormat:@"aid=6383&account_sdk_source=web&sdk_version=2.2.7&language=zh&is_new_login=1&need_logo=false&need_short_url=true&service=https%%3A%%2F%%2Fwww.douyin.com%%2F&next=https%%3A%%2F%%2Fwww.douyin.com%%2F&t=%@",stamp];
}
- (void)startLogin{
 [self suspend];self.token=nil;self.qr.image=nil;self.provider=0;self.qrFailureReason=nil;self.scanned=NO;self.completing=NO;self.refresh.enabled=NO;self.status.text=@"正在向抖音申请登录二维码…";
 NSUInteger generation=self.generation;
 [DLAccountSession.shared prepareLogin:^{if(generation==self.generation)[self createQRForGeneration:generation];}];
}
- (void)createQRForGeneration:(NSUInteger)generation{
 // Two bounded official request variants on the same login service. Older
 // www/sso routes often redirect to an HTML challenge rather than JSON.
 NSString *base=self.provider==0?@"https://sso.douyin.com/get_qrcode/?":@"https://login.douyin.com/passport/web/get_qrcode/?";
 [DLAccountSession.shared requestJSON:[DLAccountSession.shared loginRequest:[base stringByAppendingString:[self params]]] completion:^(NSDictionary *json,NSString *problem){
  if(generation!=self.generation)return;
  NSDictionary *data=[json[@"data"] isKindOfClass:NSDictionary.class]?json[@"data"]:@{};
  NSString *token=DLLoginText(data[@"token"]),*url=DLLoginText(data[@"qrcode_index_url"]);
  if(!url.length)url=DLLoginText(data[@"frontend_show_qrcode"]);
  NSString *encoded=DLLoginText(data[@"qrcode"]);
  NSData *rawImage=encoded.length?[[NSData alloc]initWithBase64EncodedString:encoded options:0]:nil;
  UIImage *qrImage=rawImage.length?[UIImage imageWithData:rawImage]:nil;
  if(!token.length){
    NSString *code=DLLoginText(data[@"error_code"]);
    if(!code.length)code=DLLoginText(json[@"status_code"]);
    NSString *message=DLLoginText(data[@"description"]);
    if(!message.length)message=DLLoginText(json[@"message"]);
    self.qrFailureReason=problem.length?problem:
        [NSString stringWithFormat:@"接口没有返回有效登录令牌%@%@",code.length?[@"，错误码 " stringByAppendingString:code]:@"",message.length?[@"：" stringByAppendingString:message]:@""];
  }

  NSURL *qrURL=[NSURL URLWithString:url];NSString *h=qrURL.host.lowercaseString;BOOL allowed=NO;
  for(NSString *domain in @[@"douyin.com",@"snssdk.com",@"amemv.com",@"iesdouyin.com"])if([h isEqualToString:domain]||[h hasSuffix:[@"." stringByAppendingString:domain]])allowed=YES;
  if(!token.length||(!qrImage&&(!allowed||![qrURL.scheme.lowercaseString isEqualToString:@"https"]))){
   if(self.provider==0){self.provider=1;[self createQRForGeneration:generation];return;}
   self.refresh.enabled=YES;
   self.status.text=[NSString stringWithFormat:@"扫码登录暂不可用。%@\n游客视频不受影响。",self.qrFailureReason?:problem?:@"登录服务没有提供可用的二维码。"];
   return;
  }
  if(qrImage){self.qr.image=qrImage;}
  else{
    CIFilter *filter=[CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:[url dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *output=filter.outputImage;
    CIContext *context=[CIContext contextWithOptions:nil];
    CGImageRef raw=[context createCGImage:output fromRect:output.extent];
    if(!raw){self.refresh.enabled=YES;self.status.text=@"二维码绘制失败，请刷新重试。";return;}
    CGFloat modules=CGImageGetWidth(raw),scale=MAX(1,floor(352/modules));
    CGSize size=CGSizeMake((modules+8)*scale,(modules+8)*scale);
    UIGraphicsBeginImageContextWithOptions(size,YES,1);
    CGContextRef ctx=UIGraphicsGetCurrentContext();
    [UIColor.whiteColor setFill];UIRectFill(CGRectMake(0,0,size.width,size.height));
    CGContextSetInterpolationQuality(ctx,kCGInterpolationNone);
    [[UIImage imageWithCGImage:raw] drawInRect:CGRectMake(4*scale,4*scale,modules*scale,modules*scale)];
    self.qr.image=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();CGImageRelease(raw);
  }
  self.token=token;self.deadline=[NSDate dateWithTimeIntervalSinceNow:120];self.refresh.enabled=YES;self.status.text=@"等待扫码，请在抖音中确认登录。";[self resume];
 }];
}
- (void)poll{
 if(self.polling||self.completing||!self.token.length)return;
 if(self.deadline.timeIntervalSinceNow<=0){[self suspend];self.qr.image=nil;self.status.text=@"二维码已过期，点击刷新重新获取。";return;}
 self.polling=YES;NSUInteger generation=self.generation;
 NSString *query=nil,*base=nil;
 if(self.provider==0){
  base=@"https://sso.douyin.com/check_qrconnect/?";
  query=[NSString stringWithFormat:@"aid=10006&token=%@&service=https%%3A%%2F%%2Fwww.douyin.com%%2Fpay&t=%.0f",
         DLFormEncode(self.token),floor(NSDate.date.timeIntervalSince1970*1000)];
 }else{
  base=@"https://login.douyin.com/passport/web/check_qrconnect/?";
  query=[NSString stringWithFormat:@"aid=6383&token=%@&t=%.0f",
         DLFormEncode(self.token),floor(NSDate.date.timeIntervalSince1970*1000)];
 }
 NSMutableURLRequest *r=[DLAccountSession.shared loginRequest:[base stringByAppendingString:query]];
 if(self.provider==1){
  r.HTTPMethod=@"POST";
  NSString *body=[NSString stringWithFormat:@"need_logo=false&is_frontier=true&token=%@&is_new_login=1&next=https%%3A%%2F%%2Fwww.douyin.com&need_short_url=true",DLFormEncode(self.token)];
  r.HTTPBody=[body dataUsingEncoding:NSUTF8StringEncoding];
  [r setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
 }
 [DLAccountSession.shared requestJSON:r completion:^(NSDictionary *json,NSString *problem){
  if(generation!=self.generation)return;self.polling=NO;
  if(problem){
   if(self.provider==0&&[problem rangeOfString:@"HTTP 403"].location!=NSNotFound){
    self.provider=1;self.token=nil;self.qr.image=nil;self.scanned=NO;
    self.status.text=@"当前登录入口拒绝请求，正在切换备用登录入口…";
    [self createQRForGeneration:generation];return;
   }
   self.status.text=problem;return;
  }
  NSDictionary *data=[json[@"data"] isKindOfClass:NSDictionary.class]?json[@"data"]:@{};
  NSString *serverCode=DLLoginText(data[@"error_code"]);
  if(!serverCode.length)serverCode=DLLoginText(json[@"error_code"]);
  if(!serverCode.length)serverCode=DLLoginText(json[@"status_code"]);
  if([serverCode isEqualToString:@"4031"]){
   if(self.provider==0){
    self.provider=1;self.token=nil;self.qr.image=nil;self.scanned=NO;
    self.status.text=@"当前登录入口拒绝请求，正在切换备用登录入口…";
    [self createQRForGeneration:generation];return;
   }
   [self suspend];
   self.status.text=@"备用登录入口也返回 4031。请稍后重试，或先在 Safari 登录抖音后返回本应用。";
   return;
  }
  NSString *status=DLLoginText(data[@"status"]),*redirect=DLLoginText(data[@"redirect_url"]);
  if(!redirect.length)redirect=DLLoginText(json[@"redirect_url"]);
  if(redirect.length){
   NSURL *callback=[NSURL URLWithString:redirect];
   if(!DLIsOfficialLoginURL(callback)){
    [self suspend];self.status.text=@"抖音返回了非官方登录回调地址，已停止跳转以保护账号安全。";return;
   }
   [self suspend];self.completing=YES;self.status.text=@"已确认，正在完成登录回调…";
   NSUInteger finishGeneration=self.generation;
   [DLAccountSession.shared finishLoginAtURL:callback completion:^(BOOL ok,NSString *message){
    if(finishGeneration!=self.generation)return;
    self.completing=NO;self.status.text=message;
    if(ok){self.token=nil;self.qr.image=nil;}
   }];
   return;
  }
  if([@[@"1",@"wait",@"waiting"] containsObject:status]){
   self.status.text=@"等待扫码，请在抖音中确认登录。";return;
  }
  if([@[@"2",@"scanned",@"scanning"] containsObject:status]){
   self.scanned=YES;self.status.text=@"已扫码，请在抖音中点击确认。";return;
  }
  if([@[@"3",@"confirmed",@"success"] containsObject:status]){
   self.scanned=YES;self.status.text=@"已确认，正在等待抖音返回登录回调…";return;
  }
  if([@[@"5",@"4",@"expired",@"expire",@"refused",@"cancelled",@"canceled"] containsObject:status]){
   [self suspend];self.qr.image=nil;self.status.text=@"二维码已失效，请刷新后重新扫码。";return;
  }
  NSString *message=DLLoginText(data[@"description"]);
  if(!message.length)message=DLLoginText(json[@"message"]);
  self.status.text=message.length?[NSString stringWithFormat:@"登录状态：%@。%@",status.length?status:@"未知",message]:
      [NSString stringWithFormat:@"登录状态：%@，继续等待确认。",status.length?status:@"未知"];
 }];
}
- (void)verify{
 [self suspend];self.status.text=@"正在校验账号会话…";NSUInteger generation=self.generation;
 [DLAccountSession.shared verifyAccount:^(BOOL ok,NSString *message){if(generation!=self.generation)return;self.status.text=message;if(ok){self.token=nil;self.qr.image=nil;}else [self startLogin];}];
}
- (void)logout{
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"退出抖音账号" message:@"将清除这台设备保存的抖音会话。" preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"退出" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[self suspend];self.token=nil;self.qr.image=nil;[DLAccountSession.shared logout];self.status.text=@"已退出账号，正在重新申请二维码…";[self startLogin];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)dealloc{[self.pollTimer invalidate];[[NSNotificationCenter defaultCenter] removeObserver:self];}
@end
