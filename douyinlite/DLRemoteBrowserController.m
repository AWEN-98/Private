#import "DLRemoteBrowserController.h"
#import <MediaPlayer/MediaPlayer.h>

@interface DLRemoteBrowserController ()
@property(nonatomic,copy) NSString *feedURLString;
@property(nonatomic,copy) NSString *apiKey;
@property(nonatomic,strong) UIScrollView *scrollView;
@property(nonatomic,strong) UIImageView *frameImage;
@property(nonatomic,strong) UILabel *statusText;
@property(nonatomic,strong) NSTimer *pollTimer;
@property(nonatomic,assign) BOOL frameLoading;
@property(nonatomic,assign) NSUInteger generation;
@property(nonatomic,strong) MPMoviePlayerViewController *remotePlayer;
@end

@implementation DLRemoteBrowserController

- (instancetype)initWithFeedURL:(NSURL *)url apiKey:(NSString *)key {
    if((self=[super init])){
        self.feedURLString=url.absoluteString;
        self.apiKey=[key copy];
    }
    return self;
}
- (BOOL)prefersStatusBarHidden{return NO;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskPortrait;}

- (NSURL *)endpoint:(NSString *)action {
    NSURL *base=[NSURL URLWithString:self.feedURLString];
    if(![[base.scheme lowercaseString] isEqualToString:@"https"]||!base.host.length)return nil;
    NSURLComponents *parts=[NSURLComponents componentsWithURL:base resolvingAgainstBaseURL:NO];
    NSString *path=parts.path?:@"";
    if(![path hasSuffix:@"/api/feed"])return nil;
    parts.path=[[path substringToIndex:path.length-4] stringByAppendingString:[@"browser/" stringByAppendingString:action]];
    parts.query=nil;parts.fragment=nil;
    return parts.URL;
}
- (NSMutableURLRequest *)request:(NSString *)action method:(NSString *)method payload:(NSDictionary *)payload {
    NSURL *url=[self endpoint:action];
    if(!url)return nil;
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:14];
    req.HTTPMethod=method;
    [req setValue:[@"Bearer " stringByAppendingString:self.apiKey?:@""] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
    if(payload){
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        req.HTTPBody=[NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    }
    return req;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor colorWithWhite:.06 alpha:1];
    CGFloat width=self.view.bounds.size.width, height=self.view.bounds.size.height;
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];
    close.frame=CGRectMake(8,21,48,36);[close setTitle:@"返回" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeViewer) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:close];

    UILabel *heading=[[UILabel alloc]initWithFrame:CGRectMake(60,21,width-120,36)];
    heading.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    heading.textAlignment=NSTextAlignmentCenter;
    heading.text=@"云端 Chrome";heading.font=[UIFont boldSystemFontOfSize:15];heading.textColor=[UIColor whiteColor];[self.view addSubview:heading];

    self.statusText=[[UILabel alloc]initWithFrame:CGRectMake(10,57,width-20,36)];
    self.statusText.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.statusText.text=@"正在连接云端浏览器…";
    self.statusText.numberOfLines=2;self.statusText.font=[UIFont systemFontOfSize:11];
    self.statusText.textColor=[UIColor colorWithWhite:.8 alpha:1];
    self.statusText.textAlignment=NSTextAlignmentCenter;[self.view addSubview:self.statusText];

    CGFloat viewerHeight=MAX(170,height-157);
    self.scrollView=[[UIScrollView alloc]initWithFrame:CGRectMake(0,95,width,viewerHeight)];
    self.scrollView.backgroundColor=[UIColor blackColor];
    self.scrollView.delegate=self;self.scrollView.minimumZoomScale=1;self.scrollView.maximumZoomScale=4;
    self.scrollView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];

    self.frameImage=[[UIImageView alloc]initWithFrame:CGRectMake(0,0,width,width*800.0/1280.0)];
    self.frameImage.contentMode=UIViewContentModeScaleToFill;
    self.frameImage.userInteractionEnabled=YES;self.frameImage.backgroundColor=[UIColor blackColor];
    [self.scrollView addSubview:self.frameImage];
    self.scrollView.contentSize=self.frameImage.bounds.size;
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapFrame:)];
    [self.frameImage addGestureRecognizer:tap];
    UITapGestureRecognizer *zoom=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(doubleTapFrame:)];
    zoom.numberOfTapsRequired=2;[self.frameImage addGestureRecognizer:zoom];
    [tap requireGestureRecognizerToFail:zoom];

    UIView *bar=[[UIView alloc]initWithFrame:CGRectMake(0,height-59,width,59)];
    bar.backgroundColor=[UIColor colorWithWhite:.11 alpha:1];
    bar.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:bar];
    UIButton *play=[UIButton buttonWithType:UIButtonTypeSystem];
    play.frame=CGRectMake(width-72,21,65,36);
    play.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
    [play setTitle:@"预览播放" forState:UIControlStateNormal];
    play.titleLabel.font=[UIFont systemFontOfSize:12];
    [play addTarget:self action:@selector(startStream) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:play];
    NSArray *titles=@[@"首页",@"后退",@"上滑",@"下滑"];
    SEL actions[]={@selector(openHome),@selector(goBack),@selector(scrollDown),@selector(scrollUp)};
    for(NSUInteger i=0;i<titles.count;i++){
        UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
        button.frame=CGRectMake(width*(CGFloat)i/4.0,9,width/4.0,43);
        button.autoresizingMask=UIViewAutoresizingFlexibleWidth;
        button.titleLabel.font=[UIFont systemFontOfSize:14];
        [button setTitle:titles[i] forState:UIControlStateNormal];
        [button addTarget:self action:actions[i] forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:button];
    }
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView{return self.frameImage;}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];self.generation++;
    [self.pollTimer invalidate];
    self.pollTimer=[NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refreshFrame) userInfo:nil repeats:YES];
    [self refreshFrame];
}
- (void)viewWillDisappear:(BOOL)animated {
    [self.pollTimer invalidate];self.pollTimer=nil;self.generation++;
    if(self.remotePlayer)[self stopCloudStream];
    [super viewWillDisappear:animated];
}
- (void)closeViewer {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)refreshFrame {
    if(self.frameLoading)return;
    NSMutableURLRequest *req=[self request:@"frame" method:@"GET" payload:nil];
    if(!req){self.statusText.text=@"请先配置有效的 DouyinBridge 地址";return;}
    self.frameLoading=YES;NSUInteger token=self.generation;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSHTTPURLResponse *http=[response isKindOfClass:[NSHTTPURLResponse class]]?(NSHTTPURLResponse *)response:nil;
        UIImage *image=(http.statusCode==200 && data.length<2000000)?[UIImage imageWithData:data]:nil;
        dispatch_async(dispatch_get_main_queue(),^{
            if(token!=self.generation)return;
            self.frameLoading=NO;
            if(image){
                self.frameImage.image=image;
                self.statusText.text=@"这是云端 Chrome 的实时截图。单击操作；双击放大，按钮滚动。";
            }else if(http.statusCode==401){
                self.statusText.text=@"云端密钥错误，请返回重新配置";
            }else{
                self.statusText.text=error.localizedDescription?:[NSString stringWithFormat:@"云端截图不可用（HTTP %ld）",(long)http.statusCode];
            }
        });
    }] resume];
}
- (void)sendAction:(NSString *)name payload:(NSDictionary *)payload {
    NSMutableURLRequest *req=[self request:name method:@"POST" payload:payload];
    if(!req)return;
    NSUInteger token=self.generation;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSHTTPURLResponse *http=[response isKindOfClass:[NSHTTPURLResponse class]]?(NSHTTPURLResponse *)response:nil;
        dispatch_async(dispatch_get_main_queue(),^{
            if(token!=self.generation)return;
            if(error||http.statusCode!=200)self.statusText.text=error.localizedDescription?:[NSString stringWithFormat:@"操作失败（HTTP %ld）",(long)http.statusCode];
            else [self refreshFrame];
        });
    }] resume];
}
- (void)tapFrame:(UITapGestureRecognizer *)gesture {
    if(!self.frameImage.image)return;
    CGPoint p=[gesture locationInView:self.frameImage];
    CGFloat w=self.frameImage.bounds.size.width,h=self.frameImage.bounds.size.height;
    if(w<1||h<1||p.x<0||p.y<0||p.x>w||p.y>h)return;
    [self sendAction:@"tap" payload:@{@"x":@(MAX(0,MIN(1280,p.x/w*1280))),@"y":@(MAX(0,MIN(800,p.y/h*800)))}];
}
- (void)doubleTapFrame:(UITapGestureRecognizer *)gesture {
    CGFloat zoom=self.scrollView.zoomScale>1.1?1.0:2.5;
    [self.scrollView setZoomScale:zoom animated:YES];
}
- (void)openHome {[self sendAction:@"home" payload:nil];}
- (void)goBack {[self sendAction:@"back" payload:nil];}
- (void)scrollDown {[self sendAction:@"scroll" payload:@{@"dy":@750}];}
- (void)scrollUp {[self sendAction:@"scroll" payload:@{@"dy":@-750}];}
- (void)startStream {
    NSMutableURLRequest *req=[self request:@"stream/start" method:@"POST" payload:nil];
    if(!req)return;
    self.statusText.text=@"正在准备云端视频画面（暂不含声音）…";
    NSUInteger token=self.generation;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSDictionary *body=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
        NSString *streamURL=[body isKindOfClass:[NSDictionary class]]?body[@"url"]:nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if(token!=self.generation)return;
            if(![streamURL isKindOfClass:[NSString class]]||![streamURL hasPrefix:@"https://"]){
                self.statusText.text=error.localizedDescription?:@"云端视频流未就绪，请检查服务器 ffmpeg";
                return;
            }
            self.remotePlayer=[[MPMoviePlayerViewController alloc]initWithContentURL:[NSURL URLWithString:streamURL]];
            self.remotePlayer.moviePlayer.controlStyle=MPMovieControlStyleFullscreen;
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(streamPlaybackFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:self.remotePlayer.moviePlayer];
            [self presentMoviePlayerViewControllerAnimated:self.remotePlayer];
            [self.remotePlayer.moviePlayer play];
        });
    }] resume];
}
- (void)streamPlaybackFinished:(NSNotification *)notification {
    [self stopCloudStream];
}
- (void)stopCloudStream {
    NSMutableURLRequest *request=[self request:@"stream/stop" method:@"POST" payload:nil];
    if(request)[[[NSURLSession sharedSession] dataTaskWithRequest:request] resume];
    if(self.remotePlayer){
        [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:self.remotePlayer.moviePlayer];
        self.remotePlayer=nil;
    }
}
- (void)dealloc {
    [self.pollTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end
