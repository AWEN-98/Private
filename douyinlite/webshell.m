#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface DLBrowser : UIViewController <WKNavigationDelegate, WKUIDelegate>
@property(nonatomic,strong) WKWebView *web;
@property(nonatomic,strong) UIView *toolbar;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *modeButton;
@property(nonatomic,assign) BOOL desktop;
@end
@implementation DLBrowser
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont systemFontOfSize:12];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor blackColor];
    self.desktop=[[NSUserDefaults standardUserDefaults] boolForKey:@"dl_web_desktop"];
    WKWebViewConfiguration *configuration=[WKWebViewConfiguration new];
    configuration.allowsInlineMediaPlayback=YES;
    configuration.mediaPlaybackRequiresUserAction=NO;
    self.web=[[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.web.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.web.navigationDelegate=self;
    self.web.UIDelegate=self;
    self.web.opaque=NO;
    self.web.backgroundColor=[UIColor blackColor];
    self.web.scrollView.backgroundColor=[UIColor blackColor];
    [self.view addSubview:self.web];
    self.toolbar=[[UIView alloc] initWithFrame:CGRectZero];
    self.toolbar.backgroundColor=[UIColor colorWithWhite:0 alpha:.82];
    self.toolbar.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.toolbar];
    NSArray *titles=@[@"返回",@"前进",@"刷新",@"首页",@"电脑版",@"隐藏"];
    SEL selectors[]={@selector(back),@selector(forward),@selector(refresh),@selector(home),@selector(toggleDesktop),@selector(toggleBar)};
    for(NSInteger i=0;i<titles.count;i++){
        UIButton *b=[self button:titles[i] action:selectors[i]];
        b.tag=100+i;
        [self.toolbar addSubview:b];
        if(i==4)self.modeButton=b;
    }
    self.status=[[UILabel alloc] initWithFrame:CGRectZero];
    self.status.font=[UIFont systemFontOfSize:11];
    self.status.textColor=[UIColor whiteColor];
    self.status.backgroundColor=[UIColor colorWithWhite:0 alpha:.72];
    self.status.textAlignment=NSTextAlignmentCenter;
    self.status.numberOfLines=2;
    [self.view addSubview:self.status];
    [self applyAgent];
    [self home];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    BOOL hidden=self.toolbar.hidden;
    self.toolbar.frame=CGRectMake(0,h-38,w,38);
    for(NSInteger i=0;i<6;i++){
        UIView *b=[self.toolbar viewWithTag:100+i];
        b.frame=CGRectMake(i*w/6.0,0,w/6.0,38);
    }
    self.status.frame=CGRectMake(8,8,w-16,40);
    self.web.frame=self.view.bounds;
    if(hidden)self.toolbar.hidden=YES;
}
- (void)applyAgent {
    // Desktop mode changes only the user agent. Modern JS remains limited by iOS 8 WebKit.
    NSString *agent=self.desktop?
    @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15":
    @"Mozilla/5.0 (iPhone; CPU iPhone OS 8_4_1 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Version/8.0 Mobile/12H321 Safari/600.1.4";
    if([self.web respondsToSelector:@selector(setCustomUserAgent:)])
        self.web.customUserAgent=agent;
    [self.modeButton setTitle:(self.desktop?@"手机版":@"电脑版") forState:UIControlStateNormal];
}
- (void)home {
    [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.douyin.com/"] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:25]];
}
- (void)back {if(self.web.canGoBack)[self.web goBack];}
- (void)forward {if(self.web.canGoForward)[self.web goForward];}
- (void)refresh {[self.web reload];}
- (void)toggleDesktop {
    self.desktop=!self.desktop;
    [[NSUserDefaults standardUserDefaults] setBool:self.desktop forKey:@"dl_web_desktop"];
    [self applyAgent];
    [self.web reload];
}
- (void)toggleBar {
    self.toolbar.hidden=YES;
    UIButton *restore=[self.view viewWithTag:555];
    if(!restore){
        restore=[self button:@"☰" action:@selector(showBar)];
        restore.tag=555;
        restore.frame=CGRectMake(4,self.view.bounds.size.height-42,38,38);
        restore.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleRightMargin;
        restore.backgroundColor=[UIColor colorWithWhite:0 alpha:.55];
        [self.view addSubview:restore];
    }
    restore.hidden=NO;
}
- (void)showBar {
    self.toolbar.hidden=NO;
    [self.view viewWithTag:555].hidden=YES;
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    self.status.hidden=NO;self.status.text=@"正在打开抖音网页版…";
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.status.hidden=YES;
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self showError:error];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self showError:error];
}
- (void)showError:(NSError *)error {
    if(error.code==NSURLErrorCancelled)return;
    self.status.hidden=NO;
    self.status.text=[NSString stringWithFormat:@"网页加载失败 (%ld)：%@。可点刷新或切换模式。",(long)error.code,error.localizedDescription];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url=action.request.URL;
    NSString *scheme=[url.scheme lowercaseString];
    if(![@[@"http",@"https",@"about"] containsObject:scheme]){
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}
@end
@interface DLApp : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation DLApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController=[DLBrowser new];
    self.window.backgroundColor=[UIColor blackColor];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass([DLApp class]));}}
