#import "DLAccountSession.h"
#import <CoreImage/CoreImage.h>
#import <math.h>

@interface DLBrowserController : UIViewController
- (instancetype)initWithURL:(NSURL *)url;
@end
static NSString *DLLoginText(id v){return [v isKindOfClass:NSString.class]?v:([v respondsToSelector:@selector(stringValue)]?[v stringValue]:@"");}
@interface DLLoginController ()
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIImageView *qr;
@property(nonatomic,strong) UIButton *refresh;
@property(nonatomic,strong) NSTimer *pollTimer;
@property(nonatomic,copy) NSString *token;
@property(nonatomic,assign) NSUInteger generation;
@property(nonatomic,assign) NSInteger provider;
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
 UIScrollView *scroll=[[UIScrollView alloc]initWithFrame:CGRectMake(0,64,w,self.view.bounds.size.height-64)];scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;scroll.contentSize=CGSizeMake(w,490);[self.view addSubview:scroll];
 UILabel *hint=[[UILabel alloc]initWithFrame:CGRectMake(20,5,w-40,40)];hint.numberOfLines=2;hint.text=@"用另一台设备的抖音扫码并确认\n登录完成后返回原生播放器";hint.font=[UIFont systemFontOfSize:13];hint.textAlignment=NSTextAlignmentCenter;hint.textColor=UIColor.lightGrayColor;hint.autoresizingMask=UIViewAutoresizingFlexibleWidth;[scroll addSubview:hint];
 self.qr=[[UIImageView alloc]initWithFrame:CGRectMake((w-192)/2,53,192,192)];self.qr.backgroundColor=UIColor.whiteColor;self.qr.contentMode=UIViewContentModeScaleAspectFit;self.qr.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;[scroll addSubview:self.qr];
 self.status=[[UILabel alloc]initWithFrame:CGRectMake(20,253,w-40,70)];self.status.numberOfLines=0;self.status.font=[UIFont systemFontOfSize:13];self.status.textColor=UIColor.whiteColor;self.status.textAlignment=NSTextAlignmentCenter;self.status.autoresizingMask=UIViewAutoresizingFlexibleWidth;[scroll addSubview:self.status];
 self.refresh=[self button:@"生成 / 刷新二维码" action:@selector(startLogin) frame:CGRectMake(20,330,w-40,38) parent:scroll];
 [self button:@"已确认登录，检查账号" action:@selector(verify) frame:CGRectMake(20,370,w-40,36) parent:scroll];
 [self button:@"打开官方页面完成登录或验证" action:@selector(openWebsite) frame:CGRectMake(20,409,w-40,36) parent:scroll];
 [self button:@"退出账号并清除本机会话" action:@selector(logout) frame:CGRectMake(20,450,w-40,36) parent:scroll];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(suspend) name:UIApplicationDidEnterBackgroundNotification object:nil];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resume) name:UIApplicationDidBecomeActiveNotification object:nil];
 if(DLAccountSession.shared.hasSession){self.status.text=@"本机保存了账号会话，正在检查…";[self verify];}else [self startLogin];
}
- (void)close{[self suspend];[self dismissViewControllerAnimated:YES completion:nil];}
- (void)suspend{self.generation++;[self.pollTimer invalidate];self.pollTimer=nil;self.polling=NO;self.completing=NO;self.refresh.enabled=YES;}
- (void)resume{if(self.presentedViewController)return;if(self.token.length&&self.deadline.timeIntervalSinceNow>0&&!self.completing){[self.pollTimer invalidate];self.pollTimer=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(poll) userInfo:nil repeats:YES];[self poll];}}
- (void)viewWillDisappear:(BOOL)animated{[self suspend];[super viewWillDisappear:animated];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];[self resume];}
- (NSString *)params{return @"aid=6383&account_sdk_source=web&sdk_version=2.2.7&language=zh&is_new_login=1&need_logo=false&need_short_url=true&is_frontier=0&service=https%3A%2F%2Fwww.douyin.com%2F&next=https%3A%2F%2Fwww.douyin.com%2F";}
- (void)startLogin{
 [self suspend];self.token=nil;self.qr.image=nil;self.provider=0;self.scanned=NO;self.completing=NO;self.refresh.enabled=NO;self.status.text=@"正在向抖音申请登录二维码…";
 NSUInteger generation=self.generation;
 [DLAccountSession.shared prepareLogin:^{if(generation==self.generation)[self createQRForGeneration:generation];}];
}
- (void)createQRForGeneration:(NSUInteger)generation{
 NSString *base=self.provider==0?@"https://login.douyin.com/passport/web/get_qrcode/?":@"https://sso.douyin.com/get_qrcode/?";
 [DLAccountSession.shared requestJSON:[DLAccountSession.shared webRequest:[base stringByAppendingString:[self params]]] completion:^(NSDictionary *json,NSString *problem){
  if(generation!=self.generation)return;
  NSDictionary *data=[json[@"data"] isKindOfClass:NSDictionary.class]?json[@"data"]:@{};
  NSString *token=DLLoginText(data[@"token"]),*url=DLLoginText(data[@"qrcode_index_url"]);if(!url.length)url=DLLoginText(data[@"frontend_show_qrcode"]);
  NSURL *qrURL=[NSURL URLWithString:url];NSString *h=qrURL.host.lowercaseString;BOOL allowed=NO;
  for(NSString *domain in @[@"douyin.com",@"snssdk.com",@"amemv.com",@"iesdouyin.com"])if([h isEqualToString:domain]||[h hasSuffix:[@"." stringByAppendingString:domain]])allowed=YES;
  if(!token.length||!allowed||![qrURL.scheme.lowercaseString isEqualToString:@"https"]){
   if(self.provider==0){self.provider=1;[self createQRForGeneration:generation];return;}
   self.refresh.enabled=YES;self.status.text=problem?:@"未取得登录二维码。请刷新或打开官方页面完成验证。";return;
  }
  CIFilter *filter=[CIFilter filterWithName:@"CIQRCodeGenerator"];[filter setValue:[url dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];[filter setValue:@"M" forKey:@"inputCorrectionLevel"];
  CIImage *output=filter.outputImage;CIContext *context=[CIContext contextWithOptions:nil];CGImageRef raw=[context createCGImage:output fromRect:output.extent];
  // Render an integer number of physical pixels per module, with a quiet border.
  if(!raw){self.refresh.enabled=YES;self.status.text=@"二维码绘制失败，请刷新重试。";return;}
  CGFloat modules=CGImageGetWidth(raw),scale=MAX(1,floor(352/modules));CGSize size=CGSizeMake((modules+8)*scale,(modules+8)*scale);
  UIGraphicsBeginImageContextWithOptions(size,YES,1);CGContextRef ctx=UIGraphicsGetCurrentContext();[UIColor.whiteColor setFill];UIRectFill(CGRectMake(0,0,size.width,size.height));CGContextSetInterpolationQuality(ctx,kCGInterpolationNone);
  [[UIImage imageWithCGImage:raw] drawInRect:CGRectMake(4*scale,4*scale,modules*scale,modules*scale)];self.qr.image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();CGImageRelease(raw);
  self.token=token;self.deadline=[NSDate dateWithTimeIntervalSinceNow:120];self.refresh.enabled=YES;self.status.text=@"等待扫码，请在抖音中确认登录。";[self resume];
 }];
}
- (void)poll{
 if(self.polling||self.completing||!self.token.length)return;
 if(self.deadline.timeIntervalSinceNow<=0){[self suspend];self.qr.image=nil;self.status.text=@"二维码已过期，点击刷新重新获取。";return;}
 self.polling=YES;NSUInteger generation=self.generation;
 NSString *base=self.provider==0?@"https://login.douyin.com/passport/web/check_qrconnect/?":@"https://sso.douyin.com/check_qrconnect/?";
 NSString *query=[[self params] stringByAppendingFormat:@"&token=%@",DLFormEncode(self.token)];
 NSMutableURLRequest *r=[DLAccountSession.shared webRequest:[base stringByAppendingString:query]];
 if(self.provider==0){r.HTTPMethod=@"POST";r.HTTPBody=[query dataUsingEncoding:NSUTF8StringEncoding];[r setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];}
 [DLAccountSession.shared requestJSON:r completion:^(NSDictionary *json,NSString *problem){
  if(generation!=self.generation)return;self.polling=NO;
  if(problem){self.status.text=problem;return;}
  NSDictionary *data=[json[@"data"] isKindOfClass:NSDictionary.class]?json[@"data"]:@{};
  NSString *status=[DLLoginText(data[@"status"]) lowercaseString],*redirect=DLLoginText(data[@"redirect_url"]);
  if([DLLoginText(data[@"error_code"]) isEqualToString:@"2046"]||[DLLoginText(json[@"error_code"]) isEqualToString:@"2046"]){[self suspend];self.status.text=@"账号需要额外验证，请打开官方页面完成。";return;}
  if(redirect.length){[self suspend];self.completing=YES;self.status.text=@"已确认，正在完成登录回调…";NSUInteger finishGeneration=self.generation;
   [DLAccountSession.shared finishLoginAtURL:[NSURL URLWithString:redirect] completion:^(BOOL ok,NSString *message){if(finishGeneration!=self.generation)return;self.completing=NO;self.status.text=message;if(ok)self.qr.image=nil;}];return;
  }
  if([@[@"3",@"confirmed",@"success"] containsObject:status]){[self suspend];self.status.text=@"已确认扫码，正在校验账号会话…";[self verify];return;}
  if([@[@"4",@"5",@"expired",@"expire",@"refused",@"cancelled",@"canceled"] containsObject:status]){[self suspend];self.qr.image=nil;self.status.text=@"二维码已失效，请刷新后重新扫码。";return;}
  if([@[@"2",@"scanned",@"scanning"] containsObject:status])self.scanned=YES;
  self.status.text=self.scanned?@"已扫码，请在抖音中点击确认。":@"等待扫码，请在抖音中确认登录。";
 }];
}
- (void)verify{
 [self suspend];self.status.text=@"正在校验账号会话…";NSUInteger generation=self.generation;
 [DLAccountSession.shared verifyAccount:^(BOOL ok,NSString *message){if(generation!=self.generation)return;self.status.text=message;if(ok){self.token=nil;self.qr.image=nil;}else [self resume];}];
}
- (void)openWebsite{[self suspend];DLBrowserController *b=[[DLBrowserController alloc]initWithURL:[NSURL URLWithString:@"https://www.douyin.com/"]];[self presentViewController:b animated:YES completion:nil];}
- (void)logout{
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"退出抖音账号" message:@"将清除这台设备保存的抖音会话。" preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"退出" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[self suspend];self.token=nil;self.qr.image=nil;[DLAccountSession.shared logout];self.status.text=@"已退出账号。";}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)dealloc{[self.pollTimer invalidate];[[NSNotificationCenter defaultCenter] removeObserver:self];}
@end
