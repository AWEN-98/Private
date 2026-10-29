#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface DLBrowserController : UIViewController <WKNavigationDelegate, UIWebViewDelegate, UITextFieldDelegate>
@property(nonatomic,strong) WKWebView *web;
@property(nonatomic,strong) UIWebView *legacy;
@property(nonatomic,strong) UITextField *address;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) NSURL *initialURL;
@property(nonatomic,assign) NSUInteger requestGeneration;
@property(nonatomic,strong) UIView *failurePanel;
@property(nonatomic,strong) UILabel *failureText;
@end
@implementation DLBrowserController
- (instancetype)initWithURL:(NSURL *)url { if((self=[super init]))self.initialURL=url;return self; }
- (BOOL)prefersStatusBarHidden { return NO; }
- (void)viewDidLoad {
 [super viewDidLoad];
 self.view.backgroundColor=[UIColor colorWithWhite:.07 alpha:1];
 CGFloat w=self.view.bounds.size.width;
 UIView *bar=[[UIView alloc]initWithFrame:CGRectMake(0,20,w,44)];
 bar.backgroundColor=[UIColor colorWithWhite:.12 alpha:1];bar.autoresizingMask=UIViewAutoresizingFlexibleWidth;
 [self.view addSubview:bar];
 UIButton *back=[UIButton buttonWithType:UIButtonTypeSystem];back.frame=CGRectMake(0,0,45,44);
 [back setTitle:@"关闭" forState:UIControlStateNormal];[back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];[bar addSubview:back];
 self.address=[[UITextField alloc]initWithFrame:CGRectMake(47,5,w-94,34)];
 self.address.borderStyle=UITextBorderStyleRoundedRect;self.address.font=[UIFont systemFontOfSize:12];
 self.address.autocapitalizationType=UITextAutocapitalizationTypeNone;self.address.autocorrectionType=UITextAutocorrectionTypeNo;
 self.address.keyboardType=UIKeyboardTypeURL;self.address.returnKeyType=UIReturnKeyGo;self.address.delegate=self;
 self.address.text=self.initialURL.absoluteString;self.address.autoresizingMask=UIViewAutoresizingFlexibleWidth;[bar addSubview:self.address];
 UIButton *go=[UIButton buttonWithType:UIButtonTypeSystem];go.frame=CGRectMake(w-45,0,44,44);
 go.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;[go setTitle:@"前往" forState:UIControlStateNormal];
 [go addTarget:self action:@selector(openAddress) forControlEvents:UIControlEventTouchUpInside];[bar addSubview:go];
 CGRect frame=CGRectMake(0,64,w,MAX(100,self.view.bounds.size.height-112));
 if(NSClassFromString(@"WKWebView")) {
   WKWebViewConfiguration *configuration=[WKWebViewConfiguration new];
   configuration.allowsInlineMediaPlayback=YES;
   self.web=[[WKWebView alloc]initWithFrame:frame configuration:configuration];
   self.web.navigationDelegate=self;self.web.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
   [self.view addSubview:self.web];
 }else{
   self.legacy=[[UIWebView alloc]initWithFrame:frame];self.legacy.delegate=self;
   self.legacy.mediaPlaybackRequiresUserAction=NO;self.legacy.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
   [self.view addSubview:self.legacy];
 }
 UIView *footer=[[UIView alloc]initWithFrame:CGRectMake(0,self.view.bounds.size.height-48,w,48)];
 footer.backgroundColor=[UIColor colorWithWhite:.1 alpha:1];
 footer.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth;
 [self.view addSubview:footer];
 NSArray *names=@[@"‹",@"›",@"刷新",@"首页",@"直播"];
 SEL sels[]={@selector(goBack),@selector(goForward),@selector(reloadPage),@selector(openHome),@selector(openLive)};
 for(NSInteger i=0;i<names.count;i++){
   UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=CGRectMake(w*i/5.0,0,w/5.0,45);
   b.autoresizingMask=UIViewAutoresizingFlexibleWidth;
   [b setTitle:names[i] forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:14];
   [b addTarget:self action:sels[i] forControlEvents:UIControlEventTouchUpInside];[footer addSubview:b];
 }
 [self installFailurePanel];
 [self openURL:self.initialURL];
}
- (void)installFailurePanel {
 CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
 UIView *v=[[UIView alloc]initWithFrame:CGRectMake(12,MAX(76,(h-245)/2),w-24,245)];
 v.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
 v.backgroundColor=[UIColor colorWithWhite:.11 alpha:.97];v.layer.cornerRadius=12;
 UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(16,12,w-56,105)];
 label.autoresizingMask=UIViewAutoresizingFlexibleWidth;label.textColor=[UIColor whiteColor];
 label.numberOfLines=0;label.textAlignment=NSTextAlignmentCenter;label.font=[UIFont systemFontOfSize:13];
 label.text=@"正在加载抖音网页…";[v addSubview:label];self.failureText=label;
 NSArray *titles=@[@"重新加载",@"Safari 打开",@"返回原生视频"];
 SEL actions[]={@selector(reloadPage),@selector(openSafari),@selector(close)};
 for(NSInteger i=0;i<3;i++){
  UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
  b.frame=CGRectMake(16,124+i*37,w-56,32);b.autoresizingMask=UIViewAutoresizingFlexibleWidth;
  [b setTitle:titles[i] forState:UIControlStateNormal];b.titleLabel.font=[UIFont boldSystemFontOfSize:14];
  [b addTarget:self action:actions[i] forControlEvents:UIControlEventTouchUpInside];[v addSubview:b];
 }
 v.hidden=YES;[self.view addSubview:v];self.failurePanel=v;
}
- (void)openSafari {NSURL *url=[NSURL URLWithString:self.address.text?:@""];if(url)[[UIApplication sharedApplication] openURL:url];}
- (void)showFailureMessage:(NSString *)msg {
 self.failureText.text=msg;
 self.failurePanel.hidden=NO;
}
- (void)checkLoadingTimeout:(NSNumber *)generation {
 if(generation.unsignedIntegerValue!=self.requestGeneration)return;
 [self showFailureMessage:@"网页长时间没有完成加载。iOS 8 的 WebKit 可能无法执行新版抖音所需的 JavaScript，也可能发生 TLS 或网络请求失败。你可以重试、用 Safari 测试，或返回原生视频列表。"];
}
- (void)finishLoading {
 self.requestGeneration++;
 self.failurePanel.hidden=YES;
}
- (void)close {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)openURL:(NSURL *)url{
 if(!url || !([url.scheme isEqualToString:@"https"]||[url.scheme isEqualToString:@"http"]))return;
 self.address.text=url.absoluteString;
 self.failurePanel.hidden=YES;
 NSUInteger generation=++self.requestGeneration;
 [self performSelector:@selector(checkLoadingTimeout:) withObject:@(generation) afterDelay:18];
 NSURLRequest *request=[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:20];
 if(self.web)[self.web loadRequest:request];else if(self.legacy)[self.legacy loadRequest:request];
}
- (void)openAddress{
 [self.address resignFirstResponder];
 NSString *value=[self.address.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
 if(![value hasPrefix:@"https://"]&&![value hasPrefix:@"http://"])value=[@"https://" stringByAppendingString:value];
 [self openURL:[NSURL URLWithString:value]];
}
- (BOOL)textFieldShouldReturn:(UITextField *)field {[self openAddress];return YES;}
- (void)goBack {if(self.web && self.web.canGoBack)[self.web goBack];else if(self.legacy && self.legacy.canGoBack)[self.legacy goBack];}
- (void)goForward {if(self.web && self.web.canGoForward)[self.web goForward];else if(self.legacy && self.legacy.canGoForward)[self.legacy goForward];}
- (void)reloadPage {if(self.web)[self.web reload];else[self.legacy reload];}
- (void)openHome {[self openURL:[NSURL URLWithString:@"https://www.douyin.com/"]];}
- (void)openLive {[self openURL:[NSURL URLWithString:@"https://live.douyin.com/"]];}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {self.address.text=webView.URL.absoluteString;[self finishLoading];}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {[self showError:error];}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {[self showError:error];}
- (void)webViewDidFinishLoad:(UIWebView *)webView {self.address.text=webView.request.URL.absoluteString;[self finishLoading];}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {[self showError:error];}
- (void)showError:(NSError *)error {
 if(error.code==NSURLErrorCancelled)return;
 self.requestGeneration++;
 [self showFailureMessage:[NSString stringWithFormat:@"网页加载失败（错误 %ld）：%@\n可尝试 Safari 打开。如果 Safari 同样无法访问，旧系统浏览器兼容性可能是原因。",(long)error.code,error.localizedDescription?:@"未知错误"]];
}
@end
