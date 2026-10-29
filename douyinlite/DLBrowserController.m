#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface DLBrowserController : UIViewController <WKNavigationDelegate, UIWebViewDelegate, UITextFieldDelegate>
@property(nonatomic,strong) WKWebView *web;
@property(nonatomic,strong) UIWebView *legacy;
@property(nonatomic,strong) UITextField *address;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) NSURL *initialURL;
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
 [self openURL:self.initialURL];
}
- (void)close {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)openURL:(NSURL *)url{
 if(!url || !([url.scheme isEqualToString:@"https"]||[url.scheme isEqualToString:@"http"]))return;
 self.address.text=url.absoluteString;
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
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {self.address.text=webView.URL.absoluteString;}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {[self showError:error];}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {[self showError:error];}
- (void)webViewDidFinishLoad:(UIWebView *)webView {self.address.text=webView.request.URL.absoluteString;}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {[self showError:error];}
- (void)showError:(NSError *)error {
 if(error.code==NSURLErrorCancelled)return;
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"网页加载失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
 if(self.presentedViewController==nil)[self presentViewController:a animated:YES completion:nil];
}
@end
