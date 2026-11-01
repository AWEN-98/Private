#import <UIKit/UIKit.h>
#import "DLAccountSession.h"

// Standalone on-device official webpage login trial for iOS 8.
// UIWebView shares NSHTTPCookieStorage with the native NSURLSession.
// Never asks for credentials inside our own views and never logs cookies.
static BOOL DLPhoneOfficialPage(NSURL *url) {
 if(!url || ![url.scheme.lowercaseString isEqualToString:@"https"] ||
    url.user.length || url.password.length || (url.port && url.port.integerValue!=443))return NO;
 NSString *host=url.host.lowercaseString?:@"";
 for(NSString *domain in @[@"douyin.com",@"iesdouyin.com",@"snssdk.com",@"amemv.com",@"bytedance.com",@"toutiao.com"]){
  if([host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]])return YES;
 }
 return NO;
}

@interface DLPhoneWebLoginController : UIViewController <UIWebViewDelegate>
@property(nonatomic,strong) UIWebView *web;
@property(nonatomic,strong) UILabel *state;
@property(nonatomic,strong) UILabel *address;
@property(nonatomic,strong) UIActivityIndicatorView *busy;
@property(nonatomic,assign) NSUInteger generation;
@property(nonatomic,assign) BOOL verifying;
@property(nonatomic,assign) BOOL verified;
@end
@implementation DLPhoneWebLoginController
- (BOOL)prefersStatusBarHidden{return NO;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskPortrait;}
- (UIButton *)button:(NSString *)caption action:(SEL)action frame:(CGRect)rect parent:(UIView *)parent{
 UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
 b.frame=rect;b.autoresizingMask=UIViewAutoresizingFlexibleWidth;
 b.titleLabel.font=[UIFont systemFontOfSize:12];
 [b setTitle:caption forState:UIControlStateNormal];
 [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
 [parent addSubview:b];return b;
}
- (void)viewDidLoad {
 [super viewDidLoad];
 self.view.backgroundColor=[UIColor colorWithWhite:.08 alpha:1];
 CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
 UIView *top=[[UIView alloc]initWithFrame:CGRectMake(0,20,w,44)];
 top.backgroundColor=[UIColor colorWithWhite:.13 alpha:1];
 top.autoresizingMask=UIViewAutoresizingFlexibleWidth;[self.view addSubview:top];
 [self button:@"关闭" action:@selector(close) frame:CGRectMake(2,1,48,42) parent:top];
 UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(54,1,w-108,42)];
 title.text=@"纯手机 · 抖音官网登录";title.textAlignment=NSTextAlignmentCenter;
 title.font=[UIFont boldSystemFontOfSize:14];title.textColor=UIColor.whiteColor;
 title.autoresizingMask=UIViewAutoresizingFlexibleWidth;[top addSubview:title];

 self.web=[[UIWebView alloc]initWithFrame:CGRectMake(0,64,w,MAX(90,h-164))];
 self.web.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 self.web.delegate=self;self.web.scalesPageToFit=YES;
 self.web.dataDetectorTypes=UIDataDetectorTypeNone;
 self.web.mediaPlaybackRequiresUserAction=YES;
 [self.view addSubview:self.web];

 UIView *bottom=[[UIView alloc]initWithFrame:CGRectMake(0,h-100,w,100)];
 bottom.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth;
 bottom.backgroundColor=[UIColor colorWithWhite:.12 alpha:1];
 [self.view addSubview:bottom];
 NSArray *labels=@[@"官网首页",@"账号页面",@"返回",@"刷新",@"检查登录"];
 SEL selectors[]={@selector(home),@selector(account),@selector(back),@selector(reload),@selector(verify)};
 for(NSInteger i=0;i<5;i++){
  UIButton *b=[self button:labels[i] action:selectors[i] frame:CGRectMake((w*i)/5.0,0,w/5.0,37) parent:bottom];
  b.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
 }
 self.address=[[UILabel alloc]initWithFrame:CGRectMake(12,38,w-24,17)];
 self.address.textColor=UIColor.lightGrayColor;self.address.font=[UIFont systemFontOfSize:10];
 self.address.lineBreakMode=NSLineBreakByTruncatingMiddle;
 self.address.autoresizingMask=UIViewAutoresizingFlexibleWidth;
 [bottom addSubview:self.address];
 self.state=[[UILabel alloc]initWithFrame:CGRectMake(12,55,w-24,43)];
 self.state.textColor=UIColor.whiteColor;self.state.font=[UIFont systemFontOfSize:11];
 self.state.numberOfLines=2;self.state.autoresizingMask=UIViewAutoresizingFlexibleWidth;
 [bottom addSubview:self.state];
 self.busy=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
 self.busy.frame=CGRectMake(w-31,20,25,25);self.busy.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
 [top addSubview:self.busy];

 self.state.text=@"请在抖音官方网站操作登录。若网页空白，可点账号页面尝试。";
 [self home];
}
- (void)open:(NSString *)address{
 NSURL *url=[NSURL URLWithString:address];
 if(!DLPhoneOfficialPage(url)){
  self.state.text=@"已拦截非官方登录网页。";return;
 }
 [self.web stopLoading];
 self.address.text=url.host;
 [self.busy startAnimating];
 [self.web loadRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:25]];
 NSUInteger generation=++self.generation;
 [self performSelector:@selector(timeout:) withObject:@(generation) afterDelay:25.0];
}
- (void)home{[self open:@"https://www.douyin.com/"];}
- (void)account{[self open:@"https://www.douyin.com/user/self"];}
- (void)back{if(self.web.canGoBack)[self.web goBack];}
- (void)reload{if(self.web.request.URL)[self open:self.web.request.URL.absoluteString];else[self home];}
- (void)timeout:(NSNumber *)generation{
 if(generation.unsignedIntegerValue!=self.generation)return;
 [self.busy stopAnimating];
 self.state.text=@"加载超时。iOS 8 可能无法运行当前网页脚本，也可能是网络或证书问题。";
}
- (void)verify{
 if(self.verifying)return;
 self.verifying=YES;
 [self.busy startAnimating];
 if(!DLAccountSession.shared.hasSession){
  self.verifying=NO;[self.busy stopAnimating];
  self.state.text=@"尚未发现登录会话。请在网页里完成官方验证后再检查。";
  return;
 }
 self.state.text=@"已检测到会话 Cookie，正在请求账号信息验证…";
 [DLAccountSession.shared verifyAccount:^(BOOL ok,NSString *message){
  self.verifying=NO;[self.busy stopAnimating];
  self.verified=ok;
  self.state.text=ok?@"账号验证成功，已尝试安全保存会话；可以关闭并返回首页。":
      [NSString stringWithFormat:@"会话尚未验证成功：%@",message?:@"官方账号接口未确认登录"];
 }];
}
- (void)close{
 ++self.generation;
 [self.web stopLoading];
 // Trigger verification only if the official site supplied a session; never
 // infer success from UIWebView's page title or from a page being loaded.
 if(!self.verifying && DLAccountSession.shared.hasSession){
  [DLAccountSession.shared verifyAccount:^(BOOL ok,NSString *message){}];
 }
 [self dismissViewControllerAnimated:YES completion:nil];
}
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)type{
 NSURL *url=request.URL;
 if([url.scheme.lowercaseString isEqualToString:@"about"])return YES;
 if(!DLPhoneOfficialPage(url)){
  self.state.text=@"已拦截外部地址，账号操作仅允许在抖音相关官方域名内进行。";
  return NO;
 }
 self.address.text=url.host.lowercaseString;
 return YES;
}
- (void)webViewDidStartLoad:(UIWebView *)webView{
 ++self.generation;[self.busy startAnimating];
 self.state.text=@"正在加载官方网页，登录时请使用抖音提供的真实验证页面。";
}
- (void)webViewDidFinishLoad:(UIWebView *)webView{
 ++self.generation;
 [self.busy stopAnimating];
 NSURL *url=webView.request.URL;
 if(url)self.address.text=url.host.lowercaseString;
 if(DLAccountSession.shared.hasSession){
  self.state.text=@"检测到本机会话，点击「检查登录」核对账号状态。";
 }else{
  self.state.text=@"网页已加载。请在网页中完成登录，再点击「检查登录」。";
 }
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error{
 if(error.code==NSURLErrorCancelled)return;
 ++self.generation;[self.busy stopAnimating];
 self.state.text=[NSString stringWithFormat:@"网页加载失败 (%ld)：%@。iOS 8 浏览器可能不兼容。",(long)error.code,error.localizedDescription?:@"未知错误"];
}
- (void)dealloc{[NSObject cancelPreviousPerformRequestsWithTarget:self];self.web.delegate=nil;}
@end
