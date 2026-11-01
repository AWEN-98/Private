#import <UIKit/UIKit.h>
#import "DLAccountSession.h"
#import <WebKit/WebKit.h>

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

@interface DLPhoneWebLoginController : UIViewController <UIWebViewDelegate, WKNavigationDelegate>
@property(nonatomic,strong) UIWebView *web;
@property(nonatomic,strong) WKWebView *modern;
@property(nonatomic,assign) BOOL usingWK;
@property(nonatomic,assign) BOOL didCompleteWebNavigation;
@property(nonatomic,copy) NSString *diagnostics;
@property(nonatomic,assign) NSUInteger probeGeneration;
@property(nonatomic,copy) NSString *lastRequestedURL;
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

 self.web=[[UIWebView alloc]initWithFrame:CGRectMake(0,64,w,MAX(90,h-203))];
 self.web.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 self.web.delegate=self;self.web.scalesPageToFit=YES;
 self.web.dataDetectorTypes=UIDataDetectorTypeNone;
 self.web.mediaPlaybackRequiresUserAction=YES;
 [self.view addSubview:self.web];

 UIView *bottom=[[UIView alloc]initWithFrame:CGRectMake(0,h-139,w,139)];
 bottom.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth;
 bottom.backgroundColor=[UIColor colorWithWhite:.12 alpha:1];
 [self.view addSubview:bottom];
 NSArray *labels=@[@"官网首页",@"个人页",@"刷新",@"检查登录"];
 SEL selectors[]={@selector(home),@selector(account),@selector(reload),@selector(verify)};
 for(NSInteger i=0;i<4;i++){
  UIButton *b=[self button:labels[i] action:selectors[i] frame:CGRectMake((w*i)/4.0,0,w/4.0,34) parent:bottom];
  b.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
 }
 [self button:@"切换网页内核" action:@selector(switchEngine) frame:CGRectMake(4,34,w/2-8,30) parent:bottom];
 [self button:@"检测网页连接" action:@selector(probe) frame:CGRectMake(w/2+4,34,w/2-8,30) parent:bottom];
 self.address=[[UILabel alloc]initWithFrame:CGRectMake(12,65,w-24,16)];
 self.address.textColor=UIColor.lightGrayColor;self.address.font=[UIFont systemFontOfSize:10];
 self.address.lineBreakMode=NSLineBreakByTruncatingMiddle;
 self.address.autoresizingMask=UIViewAutoresizingFlexibleWidth;
 [bottom addSubview:self.address];
 self.state=[[UILabel alloc]initWithFrame:CGRectMake(12,81,w-24,56)];
 self.state.textColor=UIColor.whiteColor;self.state.font=[UIFont systemFontOfSize:11];
 self.state.numberOfLines=3;self.state.autoresizingMask=UIViewAutoresizingFlexibleWidth;
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
 [self.modern stopLoading];
 self.didCompleteWebNavigation=NO;
 self.lastRequestedURL=url.absoluteString;
 self.address.text=[NSString stringWithFormat:@"%@ · %@",self.usingWK?@"WKWebView":@"UIWebView",url.host];
 [self.busy startAnimating];
 NSURLRequest *request=[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:25];
 if(self.usingWK)[self.modern loadRequest:request];
 else [self.web loadRequest:request];
 NSUInteger generation=++self.generation;
 [self performSelector:@selector(timeout:) withObject:@(generation) afterDelay:25.0];
}
- (void)home{[self open:@"https://www.douyin.com/"];}
- (void)account{[self open:@"https://www.douyin.com/user/self"];}
- (void)back{if(self.usingWK){if(self.modern.canGoBack)[self.modern goBack];}else if(self.web.canGoBack)[self.web goBack];}
- (void)reload{NSString *address=self.lastRequestedURL;if(address.length)[self open:address];else[self home];}
- (void)timeout:(NSNumber *)generation{
 if(generation.unsignedIntegerValue!=self.generation)return;
 [self.busy stopAnimating];
 self.state.text=[NSString stringWithFormat:@"网页加载超过25秒。可点「检测网页连接」，确认是网络/证书还是旧版网页内核问题。%@ ",self.usingWK?@"当前使用WKWebView。":@"可切换网页内核重试。"];
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
 [self.web stopLoading];[self.modern stopLoading];
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
 self.didCompleteWebNavigation=YES;
 NSURL *url=webView.request.URL;
 if(url)self.address.text=[NSString stringWithFormat:@"UIWebView · %@",url.host.lowercaseString];
 NSString *body=[webView stringByEvaluatingJavaScriptFromString:@"(document.body && document.body.innerText || '').trim().substring(0,120)"];
 if(body.length<4 && !DLAccountSession.shared.hasSession)
  self.state.text=@"UIWebView 已结束加载但页面可能空白。可切换网页内核，或检测HTTP状态。";
 else if(DLAccountSession.shared.hasSession){
  self.state.text=@"检测到本机会话，点击「检查登录」核对账号状态。";
 }else{
  self.state.text=@"网页已加载。请在网页中完成登录，再点击「检查登录」。";
 }
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error{
 if(error.code==NSURLErrorCancelled)return;
 ++self.generation;[self.busy stopAnimating];
 self.state.text=[NSString stringWithFormat:@"UIWebView 失败 %ld（%@）。可切换 WKWebView 或检测网页连接。",(long)error.code,error.domain?:@"网络错误"];
}
- (void)switchEngine {
 if(!self.modern){
  WKWebViewConfiguration *configuration=[WKWebViewConfiguration new];
  configuration.preferences.javaScriptEnabled=YES;
  self.modern=[[WKWebView alloc]initWithFrame:self.web.frame configuration:configuration];
  self.modern.navigationDelegate=self;
  self.modern.autoresizingMask=self.web.autoresizingMask;
  self.modern.hidden=YES;
  [self.view insertSubview:self.modern aboveSubview:self.web];
 }
 self.usingWK=!self.usingWK;
 self.modern.hidden=!self.usingWK;
 self.web.hidden=self.usingWK;
 self.state.text=self.usingWK?
  @"已切到WKWebView。iOS 8 WK Cookie 与原生会话可能隔离，页面可显示也不保证能取得登录凭据。":
  @"已切到UIWebView。此内核支持本机共享Cookie，但可能无法运行抖音新版本网页。";
 [self reload];
}
- (void)probe {
 NSString *address=self.lastRequestedURL.length?self.lastRequestedURL:@"https://www.douyin.com/";
 NSURL *url=[NSURL URLWithString:address];
 if(!DLPhoneOfficialPage(url)){self.state.text=@"仅允许检测抖音官方 HTTPS 页面。";return;}
 self.state.text=@"正在检查网页HTTP状态与TLS连接…";
 NSUInteger generation=++self.probeGeneration;
 NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:16];
 [req setValue:@"text/html,application/xhtml+xml,application/json" forHTTPHeaderField:@"Accept"];
 NSURLSessionConfiguration *config=[NSURLSessionConfiguration ephemeralSessionConfiguration];
 config.timeoutIntervalForRequest=16;
 NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
 NSURLSessionDataTask *task=[session dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
  dispatch_async(dispatch_get_main_queue(),^{
   if(self.probeGeneration!=generation)return;
   if(error){
    NSString *hint=@"网络连接失败";
    if(error.code==NSURLErrorServerCertificateUntrusted || error.code==NSURLErrorServerCertificateHasBadDate ||
       error.code==NSURLErrorSecureConnectionFailed || error.code==NSURLErrorServerCertificateHasUnknownRoot)
       hint=@"TLS或证书验证失败；请检查系统时间和证书，不要跳过证书校验";
    self.state.text=[NSString stringWithFormat:@"%@（%ld，%@）。",hint,(long)error.code,error.domain?:@"网络"];
    return;
   }
   NSHTTPURLResponse *http=[response isKindOfClass:NSHTTPURLResponse.class]?(id)response:nil;
   NSInteger status=http.statusCode;
   NSString *mime=response.MIMEType?:@"未知";
   NSString *hint=(status>=400)?@"服务端拒绝请求":
      (([mime rangeOfString:@"html" options:NSCaseInsensitiveSearch].location==NSNotFound)?@"非HTML响应":@"HTTP连接正常，网页仍空白可能是旧WebKit脚本不兼容");
   NSString *snippet=[[NSString alloc]initWithData:[data subdataWithRange:NSMakeRange(0,MIN((NSUInteger)8192,data.length))] encoding:NSUTF8StringEncoding];
   if([snippet rangeOfString:@"4031"].location!=NSNotFound ||
      [snippet rangeOfString:@"captcha" options:NSCaseInsensitiveSearch].location!=NSNotFound ||
      [snippet rangeOfString:@"verify" options:NSCaseInsensitiveSearch].location!=NSNotFound){
     hint=@"响应可能包含平台验证/访问限制，请通过官方页面验证";
   }
   self.state.text=[NSString stringWithFormat:@"HTTP %ld，%@，%lu字节。%@",(long)status,mime,(unsigned long)data.length,hint];
  });
 }];
 [task resume];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler{
 NSURL *url=action.request.URL;
 if([url.scheme.lowercaseString isEqualToString:@"about"] || DLPhoneOfficialPage(url)){
  self.address.text=[NSString stringWithFormat:@"WKWebView · %@",url.host?:@""];
  decisionHandler(WKNavigationActionPolicyAllow);
 }else{
  self.state.text=@"已拦截非官方地址。";
  decisionHandler(WKNavigationActionPolicyCancel);
 }
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation{
 ++self.generation;
 [self.busy startAnimating];self.state.text=@"WKWebView正在加载官方网页…";
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation{
 ++self.generation;
 [self.busy stopAnimating];self.didCompleteWebNavigation=YES;
 [webView evaluateJavaScript:@"(document.body && document.body.innerText || '').trim().substring(0,120)" completionHandler:^(id result,NSError *error){
  if(!self.usingWK)return;
  NSString *text=[result isKindOfClass:NSString.class]?result:@"";
  self.state.text=text.length<4?@"WKWebView加载结束但内容为空。可能是新版网页脚本不兼容。":
    @"WKWebView已加载部分网页。登录Cookie可能无法同步到iOS 8原生模块。";
 }];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error{
 if(error.code==NSURLErrorCancelled)return;
 ++self.generation;[self.busy stopAnimating];
 self.state.text=[NSString stringWithFormat:@"WKWebView连接失败 %ld（%@），可检测网页连接。",(long)error.code,error.domain?:@"网络错误"];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error{
 if(error.code==NSURLErrorCancelled)return;
 ++self.generation;[self.busy stopAnimating];
 self.state.text=[NSString stringWithFormat:@"WKWebView加载失败 %ld（%@）。",(long)error.code,error.domain?:@"网络错误"];
}
- (void)dealloc{[NSObject cancelPreviousPerformRequestsWithTarget:self];self.web.delegate=nil;self.modern.navigationDelegate=nil;}
@end
