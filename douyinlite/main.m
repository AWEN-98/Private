#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>

static UIColor *DLBG(void){return [UIColor colorWithRed:.055 green:.064 blue:.082 alpha:1];}
static UIColor *DLAccent(void){return [UIColor colorWithRed:.14 green:.88 blue:.85 alpha:1];}
static NSString *DLText(id value){return [value isKindOfClass:[NSString class]]?value:(value?[value description]:@"");}
static BOOL DLPlayableFile(NSString *file){
    NSString *ext=[[file pathExtension] lowercaseString];
    return [@[@"mp4",@"mov",@"m4v",@"m3u8"] containsObject:ext];
}
static BOOL DLDouyinHost(NSString *host){
    NSString *h=[host lowercaseString];
    return [h isEqualToString:@"douyin.com"]||[h hasSuffix:@".douyin.com"]||
        [h isEqualToString:@"iesdouyin.com"]||[h hasSuffix:@".iesdouyin.com"];
}
static NSString *DLFindURL(NSString *input){
    if(!input.length)return nil;
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"https?://[^\\s<>，。]+"
        options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *m=[re firstMatchInString:input options:0 range:NSMakeRange(0,input.length)];
    if(!m)return nil;
    NSString *url=[input substringWithRange:m.range];
    NSCharacterSet *bad=[NSCharacterSet characterSetWithCharactersInString:@"，。,;；.!！？）)]】\"'"];
    while(url.length && [bad characterIsMember:[url characterAtIndex:url.length-1]])
        url=[url substringToIndex:url.length-1];
    return url;
}
static NSString *DLPublicVideoFromHTML(NSString *html){
    if(!html.length)return nil;
    // Only use an openly published video tag or metadata URL.
    NSArray *patterns=@[
      @"<meta[^>]+property=['\\\"]og:video(?::url)?['\\\"][^>]+content=['\\\"]([^'\\\"]+)['\\\"]",
      @"<meta[^>]+content=['\\\"]([^'\\\"]+)['\\\"][^>]+property=['\\\"]og:video(?::url)?['\\\"]",
      @"<video[^>]+src=['\\\"]([^'\\\"]+)['\\\"]"
    ];
    for(NSString *pattern in patterns){
        NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:pattern
            options:NSRegularExpressionCaseInsensitive error:NULL];
        NSTextCheckingResult *m=[re firstMatchInString:html options:0 range:NSMakeRange(0,html.length)];
        if(!m||[m rangeAtIndex:1].location==NSNotFound)continue;
        NSString *candidate=[html substringWithRange:[m rangeAtIndex:1]];
        candidate=[candidate stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        candidate=[candidate stringByReplacingOccurrencesOfString:@"&#38;" withString:@"&"];
        if([candidate hasPrefix:@"https://"]||[candidate hasPrefix:@"http://"])return candidate;
    }
    return nil;
}


// Parse only metadata that a public Douyin share page actually returns.
// No session cookie, signed private endpoint, or anti-bot challenge is bypassed.
static NSDictionary *DLPublicInfoInTree(id node,NSInteger depth) {
    if(depth>16)return nil;
    if([node isKindOfClass:[NSDictionary class]]){
        NSDictionary *d=node;
        id info=d[@"videoInfoRes"];
        if([info isKindOfClass:[NSDictionary class]]){
            NSArray *items=[info[@"item_list"] isKindOfClass:[NSArray class]]?info[@"item_list"]:@[];
            if(items.count && [items[0] isKindOfClass:[NSDictionary class]])return items[0];
        }
        id detail=d[@"aweme_detail"];
        if([detail isKindOfClass:[NSDictionary class]])return detail;
        id details=d[@"item_list"];
        if([details isKindOfClass:[NSArray class]] && [details count] && [details[0] isKindOfClass:[NSDictionary class]]){
            NSDictionary *first=details[0];
            if([first[@"video"] isKindOfClass:[NSDictionary class]])return first;
        }
        for(id key in d){
            NSDictionary *found=DLPublicInfoInTree(d[key],depth+1);
            if(found)return found;
        }
    }else if([node isKindOfClass:[NSArray class]]){
        for(id v in node){
            NSDictionary *found=DLPublicInfoInTree(v,depth+1);
            if(found)return found;
        }
    }
    return nil;
}
static NSDictionary *DLJSONDictionaryAfterMarker(NSString *html,NSString *marker) {
    NSRange p=[html rangeOfString:marker];
    if(p.location==NSNotFound)return nil;
    NSUInteger i=p.location+p.length,n=html.length;
    // SSR values are assigned after '='; script data may be URI-encoded.
    while(i<n && [html characterAtIndex:i]!='{')i++;
    if(i>=n)return nil;
    NSUInteger begin=i;
    NSInteger level=0;
    BOOL quoted=NO,escaped=NO;
    for(;i<n;i++){
        unichar c=[html characterAtIndex:i];
        if(quoted){
            if(escaped){escaped=NO;continue;}
            if(c=='\\'){escaped=YES;continue;}
            if(c=='"')quoted=NO;
        }else{
            if(c=='"'){quoted=YES;continue;}
            if(c=='{')level++;
            else if(c=='}' && --level==0){
                if(i-begin>1800000)return nil;
                NSString *chunk=[html substringWithRange:NSMakeRange(begin,i-begin+1)];
                NSData *data=[chunk dataUsingEncoding:NSUTF8StringEncoding];
                id decoded=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                return [decoded isKindOfClass:[NSDictionary class]]?decoded:nil;
            }
        }
    }
    return nil;
}
static NSDictionary *DLPublicInfoFromHTML(NSString *html) {
    if(!html.length)return nil;
    for(NSString *marker in @[@"window._ROUTER_DATA",@"_ROUTER_DATA",@"window.__UNIVERSAL_DATA_FOR_REHYDRATION__"]){
        NSDictionary *data=DLJSONDictionaryAfterMarker(html,marker);
        NSDictionary *item=DLPublicInfoInTree(data,0);
        if(item)return item;
    }
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"<script[^>]*id=['\\\"]RENDER_DATA['\\\"][^>]*>([^<]+)</script>"
        options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *m=[re firstMatchInString:html options:0 range:NSMakeRange(0,html.length)];
    if(m && [m rangeAtIndex:1].location!=NSNotFound){
        NSString *encoded=[html substringWithRange:[m rangeAtIndex:1]];
        NSString *plain=[encoded stringByRemovingPercentEncoding]?:encoded;
        id json=[NSJSONSerialization JSONObjectWithData:[plain dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        return DLPublicInfoInTree(json,0);
    }
    return nil;
}
static NSString *DLPublicPlaybackURL(NSDictionary *item) {
    NSDictionary *video=[item[@"video"] isKindOfClass:[NSDictionary class]]?item[@"video"]:@{};
    NSDictionary *play=[video[@"play_addr"] isKindOfClass:[NSDictionary class]]?video[@"play_addr"]:@{};
    NSArray *urls=[play[@"url_list"] isKindOfClass:[NSArray class]]?play[@"url_list"]:@[];
    for(id candidate in urls){
        NSString *link=DLText(candidate);
        if([[link lowercaseString] hasPrefix:@"https://"]||[[link lowercaseString] hasPrefix:@"http://"])return link;
    }
    NSArray *rates=[video[@"bit_rate"] isKindOfClass:[NSArray class]]?video[@"bit_rate"]:@[];
    // Favor H.264 to maximize compatibility with iPhone 4S.
    for(id entry in rates){
        if(![entry isKindOfClass:[NSDictionary class]])continue;
        NSDictionary *rate=entry;
        NSString *codec=[DLText(rate[@"codec_type"]) lowercaseString];
        if(codec.length && ![codec containsString:@"264"] && ![codec isEqualToString:@"h264"])continue;
        NSDictionary *rplay=[rate[@"play_addr"] isKindOfClass:[NSDictionary class]]?rate[@"play_addr"]:@{};
        NSArray *rurls=[rplay[@"url_list"] isKindOfClass:[NSArray class]]?rplay[@"url_list"]:@[];
        for(id candidate in rurls){
            NSString *link=DLText(candidate);
            if([[link lowercaseString] hasPrefix:@"https://"]||[[link lowercaseString] hasPrefix:@"http://"])return link;
        }
    }
    return nil;
}
static NSDictionary *DLVideoDetails(NSString *html){
    NSDictionary *item=DLPublicInfoFromHTML(html);
    NSString *url=DLPublicPlaybackURL(item);
    if(!url.length)url=DLPublicVideoFromHTML(html);
    if(!url.length)return nil;
    NSString *caption=DLText(item[@"desc"]);
    NSDictionary *author=[item[@"author"] isKindOfClass:[NSDictionary class]]?item[@"author"]:@{};
    NSString *nickname=DLText(author[@"nickname"]);
    if(caption.length>70)caption=[[caption substringToIndex:70] stringByAppendingString:@"…"];
    NSString *title=caption.length?caption:(nickname.length?[@"@" stringByAppendingString:nickname]:@"抖音公开视频");
    return @{@"url":url,@"title":title,@"source":@"public-share"};
}

@interface DLVideoSurface : UIView @end
@implementation DLVideoSurface
+ (Class)layerClass{return [AVPlayerLayer class];}
@end

@interface DLFeedController : UIViewController <UIGestureRecognizerDelegate>
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) AVPlayerItem *item;
@property(nonatomic,strong) DLVideoSurface *surface;
@property(nonatomic,strong) NSMutableArray *videos;
@property(nonatomic,strong) NSMutableArray *favorites;
@property(nonatomic,strong) NSMutableArray *history;
@property(nonatomic,strong) NSArray *demoVideos;
@property(nonatomic,strong) AVURLAsset *nextAsset;
@property(nonatomic,copy) NSString *nextURL;
@property(nonatomic,copy) NSString *preloadSourceURL;
@property(nonatomic,strong) UIActivityIndicatorView *loadingIndicator;
@property(nonatomic,assign) BOOL animationsEnabled;
@property(nonatomic,assign) BOOL preloadEnabled;
@property(nonatomic,assign) BOOL autoplayNext;
@property(nonatomic,assign) BOOL transitioning;
@property(nonatomic,assign) NSUInteger transitionID;
@property(nonatomic,assign) BOOL demoMode;
@property(nonatomic,assign) BOOL scanning;
@property(nonatomic,assign) NSInteger failedDemoCount;
@property(nonatomic,strong) UIView *rightRail;
@property(nonatomic,strong) UIButton *likeButton;
@property(nonatomic,strong) UIButton *muteButton;
@property(nonatomic,strong) UIButton *playButton;
@property(nonatomic,strong) UILabel *titleText;
@property(nonatomic,strong) UILabel *subtitleText;
@property(nonatomic,strong) UILabel *topText;
@property(nonatomic,strong) UILabel *message;
@property(nonatomic,strong) UILabel *countText;
@property(nonatomic,strong) UIProgressView *progress;
@property(nonatomic,strong) NSTimer *uiTimer;
@property(nonatomic,assign) NSInteger index;
@property(nonatomic,assign) BOOL observing;
@property(nonatomic,assign) BOOL loading;
@property(nonatomic,assign) BOOL muted;
@property(nonatomic,assign) BOOL holdingSpeed;
@property(nonatomic,assign) BOOL wasPlaying;
@property(nonatomic,assign) BOOL favoritesOnly;
@property(nonatomic,assign) BOOL historyOnly;
@end
@implementation DLFeedController
- (BOOL)prefersStatusBarHidden{return YES;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskPortrait;}
- (BOOL)shouldAutorotate{return NO;}
- (UIButton *)button:(NSString *)title action:(SEL)action font:(CGFloat)size {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];
    b.titleLabel.font=[UIFont boldSystemFontOfSize:size];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.shadowColor=[UIColor blackColor];
    b.titleLabel.shadowOffset=CGSizeMake(0,1);
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    b.accessibilityLabel=title;
    return b;
}
- (UILabel *)label:(CGFloat)size {
    UILabel *l=[UILabel new];l.textColor=[UIColor whiteColor];
    l.font=[UIFont systemFontOfSize:size];
    l.shadowColor=[UIColor blackColor];l.shadowOffset=CGSizeMake(0,1);
    return l;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=DLBG();
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    self.videos=[[[defaults arrayForKey:@"dl_library_v1"]?:@[] mutableCopy] mutableCopy];
    self.favorites=[[[defaults arrayForKey:@"dl_favorites_v1"]?:@[] mutableCopy] mutableCopy];
    self.history=[[[defaults arrayForKey:@"dl_history_v1"]?:@[] mutableCopy] mutableCopy];
    self.animationsEnabled=![[defaults objectForKey:@"dl_animations_enabled_v1"] isEqual:@NO];
    self.preloadEnabled=![[defaults objectForKey:@"dl_preload_enabled_v1"] isEqual:@NO];
    self.autoplayNext=![[defaults objectForKey:@"dl_autonext_enabled_v1"] isEqual:@NO];
    self.index=0;
    // Real open-licensed sample MP4s are a clearly labeled playback test
    // source. They are never misrepresented as a Douyin recommendation feed.
    self.demoVideos=@[
      @{@"url":@"https://raw.githubusercontent.com/kodewright/dummy-data/main/videos/sample-video-portrait-480p.mp4",@"title":@"演示素材 · 越野车航拍",@"source":@"demo"},
      @{@"url":@"https://raw.githubusercontent.com/kodewright/dummy-data/main/videos/sample-video-landscape-480p.mp4",@"title":@"演示素材 · 城市桥梁",@"source":@"demo"},
      @{@"url":@"https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4",@"title":@"演示素材 · 花朵（CC0）",@"source":@"demo"}
    ];
    self.demoMode=self.videos.count==0;
    self.index=[[defaults objectForKey:self.demoMode?@"dl_demo_index_v1":@"dl_library_index_v1"] integerValue];
    self.surface=[[DLVideoSurface alloc] initWithFrame:self.view.bounds];
    self.surface.backgroundColor=DLBG();
    self.surface.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    ((AVPlayerLayer *)self.surface.layer).videoGravity=AVLayerVideoGravityResizeAspect;
    [self.view addSubview:self.surface];
    self.player=[AVPlayer new];
    ((AVPlayerLayer *)self.surface.layer).player=self.player;
    self.player.actionAtItemEnd=AVPlayerActionAtItemEndPause;
    [self.player setMuted:NO];
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapVideo:)];
    tap.delegate=self;tap.cancelsTouchesInView=NO;
    [self.surface addGestureRecognizer:tap];
    UISwipeGestureRecognizer *up=[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipe:)];
    up.direction=UISwipeGestureRecognizerDirectionUp;[self.view addGestureRecognizer:up];
    UISwipeGestureRecognizer *down=[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipe:)];
    down.direction=UISwipeGestureRecognizerDirectionDown;[self.view addGestureRecognizer:down];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdVideo:)];
    hold.minimumPressDuration=.43;hold.cancelsTouchesInView=NO;
    [self.surface addGestureRecognizer:hold];
    UITapGestureRecognizer *doubleTap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapVideo:)];
    doubleTap.numberOfTapsRequired=2;
    [self.surface addGestureRecognizer:doubleTap];
    [tap requireGestureRecognizerToFail:doubleTap];

    UIView *top=[[UIView alloc] initWithFrame:CGRectZero];
    top.tag=100;top.backgroundColor=[UIColor colorWithWhite:0 alpha:.18];
    top.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:top];
    self.topText=[self label:17];self.topText.font=[UIFont boldSystemFontOfSize:17];
    self.topText.textAlignment=NSTextAlignmentCenter;
    [top addSubview:self.topText];
    UIButton *add=[self button:@"＋" action:@selector(addVideo) font:29];
    add.tag=101;[top addSubview:add];
    UIButton *menu=[self button:@"⋯" action:@selector(openMenu) font:28];
    menu.tag=102;[top addSubview:menu];

    self.rightRail=[[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.rightRail];
    self.likeButton=[self button:@"♡" action:@selector(toggleFavorite) font:38];
    [self.rightRail addSubview:self.likeButton];
    UILabel *likeLabel=[self label:10];likeLabel.text=@"收藏";
    likeLabel.textAlignment=NSTextAlignmentCenter;likeLabel.tag=111;[self.rightRail addSubview:likeLabel];
    UIButton *share=[self button:@"↗" action:@selector(copyLink) font:35];
    [self.rightRail addSubview:share];share.tag=112;
    UILabel *shareLabel=[self label:10];shareLabel.text=@"复制";
    shareLabel.textAlignment=NSTextAlignmentCenter;shareLabel.tag=113;[self.rightRail addSubview:shareLabel];
    self.muteButton=[self button:@"♪" action:@selector(toggleMute) font:26];
    [self.rightRail addSubview:self.muteButton];
    UILabel *muteLabel=[self label:10];muteLabel.text=@"声音";
    muteLabel.textAlignment=NSTextAlignmentCenter;muteLabel.tag=114;[self.rightRail addSubview:muteLabel];

    self.playButton=[self button:@"▶" action:@selector(togglePlay) font:48];
    self.playButton.backgroundColor=[UIColor colorWithWhite:0 alpha:.28];
    self.playButton.layer.cornerRadius=41;
    [self.view addSubview:self.playButton];

    self.titleText=[self label:16];self.titleText.font=[UIFont boldSystemFontOfSize:16];
    self.titleText.numberOfLines=2;[self.view addSubview:self.titleText];
    self.subtitleText=[self label:12];self.subtitleText.numberOfLines=2;
    [self.view addSubview:self.subtitleText];
    self.countText=[self label:11];self.countText.textAlignment=NSTextAlignmentRight;
    [self.view addSubview:self.countText];

    self.message=[self label:14];self.message.numberOfLines=0;
    self.message.textAlignment=NSTextAlignmentCenter;
    [self.view addSubview:self.message];
    self.loadingIndicator=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.loadingIndicator.hidesWhenStopped=YES;
    [self.view addSubview:self.loadingIndicator];

    self.progress=[UIProgressView new];self.progress.progressTintColor=DLAccent();
    self.progress.trackTintColor=[UIColor colorWithWhite:1 alpha:.3];
    [self.view addSubview:self.progress];

    self.uiTimer=[NSTimer scheduledTimerWithTimeInterval:.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self layoutScreen];
    [self reloadCurrent];
}
- (void)viewDidLayoutSubviews {[super viewDidLayoutSubviews];[self layoutScreen];}
- (void)layoutScreen {
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    UIView *top=[self.view viewWithTag:100];top.frame=CGRectMake(0,0,w,60);
    self.topText.frame=CGRectMake(54,13,MAX(100,w-108),38);
    [top viewWithTag:101].frame=CGRectMake(w-49,10,43,43);
    [top viewWithTag:102].frame=CGRectMake(6,10,43,43);
    self.rightRail.frame=CGRectMake(w-64,MAX(100,h-307),59,205);
    self.likeButton.frame=CGRectMake(2,0,55,45);
    [self.rightRail viewWithTag:111].frame=CGRectMake(2,42,55,22);
    [self.rightRail viewWithTag:112].frame=CGRectMake(2,68,55,45);
    [self.rightRail viewWithTag:113].frame=CGRectMake(2,111,55,22);
    self.muteButton.frame=CGRectMake(2,142,55,39);
    [self.rightRail viewWithTag:114].frame=CGRectMake(2,181,55,20);
    self.playButton.frame=CGRectMake((w-82)/2,(h-82)/2,82,82);
    self.titleText.frame=CGRectMake(14,h-124,MAX(100,w-93),42);
    self.subtitleText.frame=CGRectMake(14,h-82,MAX(100,w-93),43);
    self.countText.frame=CGRectMake(MAX(140,w-96),h-43,80,22);
    self.message.frame=CGRectMake(20,MAX(85,(h-100)/2),w-40,110);
    self.loadingIndicator.center=CGPointMake(w/2,MAX(78,h/2-49));
    self.progress.frame=CGRectMake(0,h-3,w,3);
}
- (NSArray *)visibleVideos {
    if(self.demoMode && !self.favoritesOnly && !self.historyOnly)return self.demoVideos;
    if(self.favoritesOnly){
        NSMutableArray *result=[NSMutableArray array];
        // Demo clips are eligible for favorites as well as user-imported clips.
        for(NSDictionary *v in self.videos)
            if([self.favorites containsObject:DLText(v[@"url"])])[result addObject:v];
        for(NSDictionary *v in self.demoVideos)
            if([self.favorites containsObject:DLText(v[@"url"])])[result addObject:v];
        return result;
    }
    if(self.historyOnly){
        NSMutableArray *result=[NSMutableArray array];
        for(NSString *key in self.history){
            NSDictionary *found=nil;
            for(NSDictionary *v in self.videos)if([key isEqualToString:DLText(v[@"url"])]){found=v;break;}
            if(!found)for(NSDictionary *v in self.demoVideos)if([key isEqualToString:DLText(v[@"url"])]){found=v;break;}
            if(found)[result addObject:found];
        }
        return result;
    }
    return self.videos;
}
- (void)savePlaybackIndex {
    if(!self.favoritesOnly&&!self.historyOnly)
        [[NSUserDefaults standardUserDefaults] setInteger:self.index forKey:self.demoMode?@"dl_demo_index_v1":@"dl_library_index_v1"];
}
- (void)setLoading:(BOOL)busy {
    self.loading=busy;
    if(busy)[self.loadingIndicator startAnimating];else[self.loadingIndicator stopAnimating];
}
- (void)pulseView:(UIView *)target {
    if(!self.animationsEnabled || UIAccessibilityIsReduceMotionEnabled() || !target)return;
    target.transform=CGAffineTransformMakeScale(1.24,1.24);
    [UIView animateWithDuration:.19 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{
        target.transform=CGAffineTransformIdentity;
    } completion:nil];
}
- (void)showHeartAnimationAt:(CGPoint)point {
    if(!self.animationsEnabled||UIAccessibilityIsReduceMotionEnabled())return;
    UILabel *heart=[[UILabel alloc] initWithFrame:CGRectMake(point.x-44,point.y-48,88,88)];
    heart.text=@"♥";heart.textAlignment=NSTextAlignmentCenter;
    heart.textColor=[UIColor colorWithRed:1 green:.28 blue:.43 alpha:1];
    heart.font=[UIFont boldSystemFontOfSize:79];
    heart.shadowColor=[UIColor colorWithWhite:0 alpha:.45];
    heart.shadowOffset=CGSizeMake(0,2);
    heart.alpha=0;heart.transform=CGAffineTransformMakeScale(.45,.45);
    heart.userInteractionEnabled=NO;
    [self.view addSubview:heart];
    [UIView animateWithDuration:.17 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        heart.alpha=1;heart.transform=CGAffineTransformMakeScale(1.12,1.12);
    } completion:^(BOOL finished){
        [UIView animateWithDuration:.24 delay:.06 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            heart.alpha=0;
            heart.transform=CGAffineTransformConcat(CGAffineTransformMakeScale(.92,.92),CGAffineTransformMakeTranslation(0,-24));
        } completion:^(BOOL done){[heart removeFromSuperview];}];
    }];
}
- (void)transitionToIndex:(NSInteger)index direction:(NSInteger)direction {
    if(self.transitioning)return;
    self.transitioning=YES;
    NSUInteger token=++self.transitionID;
    CGFloat distance=direction>=0?-14.0f:14.0f;
    if(!self.animationsEnabled || UIAccessibilityIsReduceMotionEnabled()){
        self.index=index;
        [self savePlaybackIndex];
        [self reloadCurrent];
        self.transitioning=NO;
        return;
    }
    NSArray *captions=@[self.titleText,self.subtitleText,self.countText,self.rightRail];
    [UIView animateWithDuration:.11 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseIn animations:^{
        for(UIView *v in captions){v.alpha=0;v.transform=CGAffineTransformMakeTranslation(0,distance);}
    } completion:^(BOOL finished){
        if(token!=self.transitionID)return;
        self.index=index;
        [self savePlaybackIndex];
        [self reloadCurrent];
        for(UIView *v in captions){v.transform=CGAffineTransformMakeTranslation(0,-distance);v.alpha=0;}
        [UIView animateWithDuration:.19 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseOut animations:^{
            for(UIView *v in captions){v.transform=CGAffineTransformIdentity;v.alpha=1;}
        } completion:^(BOOL done){if(token==self.transitionID)self.transitioning=NO;}];
    }];
}
- (void)prepareNextAsset {
    self.nextAsset=nil;self.nextURL=nil;self.preloadSourceURL=nil;
    if(!self.preloadEnabled || !self.item || ![self visibleVideos].count)return;
    NSArray *videos=[self visibleVideos];
    NSInteger next=self.index+1;
    if(next>=videos.count){
        if(self.demoMode && videos.count>1)next=0;
        else return;
    }
    NSString *link=DLText(videos[next][@"url"]);
    if(!link.length)return;
    NSURL *url=[NSURL URLWithString:link];
    if(!url)return;
    self.preloadSourceURL=DLText(videos[self.index][@"url"]);
    self.nextURL=link;
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@NO}];
    self.nextAsset=asset;
    [asset loadValuesAsynchronouslyForKeys:@[@"playable"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(),^{
            if(self.nextAsset!=asset)return;
            NSError *error=nil;
            AVKeyValueStatus status=[asset statusOfValueForKey:@"playable" error:&error];
            if(status!=AVKeyValueStatusLoaded || !asset.playable){
                self.nextAsset=nil;self.nextURL=nil;self.preloadSourceURL=nil;
            }
        });
    }];
}
- (void)storeLibrary {
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    [d setObject:self.videos forKey:@"dl_library_v1"];
    [d setObject:self.favorites forKey:@"dl_favorites_v1"];
    [d setObject:self.history forKey:@"dl_history_v1"];
}
- (void)stopCurrent {
    [self.player pause];
    if(self.observing && self.item)[self.item removeObserver:self forKeyPath:@"status" context:NULL];
    self.observing=NO;
    if(self.item){
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.item];
    }
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.item=nil;self.holdingSpeed=NO;
    [self setLoading:NO];
}
- (void)reloadCurrent {
    NSArray *visible=[self visibleVideos];
    // Reuse the one metadata-prefetched asset, never a second decoding player.
    NSString *wanted=self.index<(NSInteger)visible.count?DLText(visible[self.index][@"url"]):@"";
    AVURLAsset *prefetched=([wanted isEqualToString:self.nextURL])?self.nextAsset:nil;
    self.nextAsset=nil;self.nextURL=nil;self.preloadSourceURL=nil;
    if(self.index>=visible.count)self.index=MAX(0,(NSInteger)visible.count-1);
    [self stopCurrent];
    [self setLoading:NO];
    self.progress.progress=0;
    self.playButton.hidden=YES;
    self.message.text=@"";
    self.titleText.text=@"";
    self.subtitleText.text=@"";
    self.countText.text=@"";
    self.likeButton.hidden=!visible.count;
    self.rightRail.hidden=!visible.count;
    self.topText.text=self.favoritesOnly?@"我的收藏":(self.historyOnly?@"观看历史":(self.demoMode?@"公开视频样片 · 测试":@"我的视频"));
    if(!visible.count){
        self.message.text=self.favoritesOnly?@"还没有收藏视频\n轻点左上角 ··· 返回全部视频":
            (self.historyOnly?@"暂无观看历史":@"DouyinLite\n\n点击右上角＋添加视频链接\n或通过菜单扫描本地视频\n\n向上滑动切换下一条");
        return;
    }
    NSDictionary *clip=visible[self.index];
    NSString *address=DLText(clip[@"url"]);
    self.titleText.text=DLText(clip[@"title"]);
    NSString *kind=[clip[@"source"] isEqualToString:@"demo"]?@"公开授权样片 · 非抖音":([clip[@"source"] isEqualToString:@"public-share"]?@"抖音公开分享":([clip[@"source"] isEqualToString:@"local"]?@"本机视频":@"手动添加"));
    self.subtitleText.text=[NSString stringWithFormat:@"%@ · 向上滑动播放下一条",kind];
    self.countText.text=[NSString stringWithFormat:@"%ld / %ld",(long)(self.index+1),(long)visible.count];
    [self.likeButton setTitle:[self.favorites containsObject:address]?@"♥":@"♡" forState:UIControlStateNormal];
    [self.likeButton setTitleColor:[self.favorites containsObject:address]?[UIColor colorWithRed:1 green:.34 blue:.48 alpha:1]:[UIColor whiteColor] forState:UIControlStateNormal];
    NSURL *url=[NSURL URLWithString:address];
    if(!url){
        self.message.text=@"视频链接无效";
        self.playButton.hidden=NO;
        return;
    }
    [self setLoading:YES];
    self.message.text=@"正在加载视频…";
    self.item=prefetched?[AVPlayerItem playerItemWithAsset:prefetched]:[AVPlayerItem playerItemWithURL:url];
    [self.item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:NULL];
    self.observing=YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.item];
    [self.player replaceCurrentItemWithPlayerItem:self.item];
    self.player.muted=self.muted;
}
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if(object!=self.item || ![path isEqualToString:@"status"]){
        [super observeValueForKeyPath:path ofObject:object change:change context:context];return;
    }
    AVPlayerItem *item=(AVPlayerItem *)object;
    dispatch_async(dispatch_get_main_queue(), ^{
        if(item!=self.item)return;
        if(item.status==AVPlayerItemStatusReadyToPlay){
            [self setLoading:NO];self.message.text=@"";
            [self.player play];
            [self prepareNextAsset];
            self.playButton.hidden=YES;
            NSArray *shown=[self visibleVideos];
            if(!shown.count || self.index>=shown.count)return;
            NSString *key=DLText(shown[self.index][@"url"]);
            [self.history removeObject:key];[self.history insertObject:key atIndex:0];
            if(self.history.count>100)[self.history removeLastObject];
            [self storeLibrary];
        }else if(item.status==AVPlayerItemStatusFailed){
            [self setLoading:NO];
            self.message.text=@"无法播放该视频\n可能是链接失效、编码不兼容或需要平台授权\n\n可添加直接的 MP4 / HLS 地址";
            self.playButton.hidden=NO;
        }
    });
}
- (void)videoEnded:(NSNotification *)notification {
    NSArray *clips=[self visibleVideos];
    if(!clips.count)return;
    if(self.autoplayNext && self.index+1<(NSInteger)clips.count){
        [self transitionToIndex:self.index+1 direction:1];return;
    }
    if(self.autoplayNext && self.demoMode && clips.count>1){
        [self transitionToIndex:0 direction:1];return;
    }
    [self.player pause];self.playButton.hidden=NO;
    self.message.text=@"播放结束 · 上滑继续或导入新视频";
}
- (void)videoFailed:(NSNotification *)notification {
    [self.player pause];self.playButton.hidden=NO;
    self.message.text=@"视频播放中断\n请检查网络或尝试其他视频地址";
}
- (void)tick {
    BOOL playing=self.player.rate>.01f;
    self.playButton.hidden=playing||self.loading||![self visibleVideos].count;
    if(playing && self.message.text.length)self.message.text=@"";
    Float64 t=CMTimeGetSeconds(self.player.currentTime);
    Float64 d=CMTimeGetSeconds(self.item.duration);
    if(isfinite(t)&&isfinite(d)&&d>0)self.progress.progress=(float)MIN(1,MAX(0,t/d));
}
- (void)togglePlay {
    if(!self.item)return;
    if(self.item.status==AVPlayerItemStatusFailed){[self reloadCurrent];return;}
    if(self.player.rate>.01f){[self.player pause];}
    else{
        Float64 d=CMTimeGetSeconds(self.item.duration);
        Float64 t=CMTimeGetSeconds(self.player.currentTime);
        if(isfinite(d)&&d>0&&isfinite(t)&&t>d-1)[self.player seekToTime:kCMTimeZero];
        [self.player play];
        self.message.text=@"";
    }
    [self tick];
}
- (void)tapVideo:(UITapGestureRecognizer *)tap {if(tap.state==UIGestureRecognizerStateEnded)[self togglePlay];}
- (void)doubleTapVideo:(UITapGestureRecognizer *)tap {
    if(tap.state!=UIGestureRecognizerStateEnded)return;
    NSArray *clips=[self visibleVideos];if(!clips.count)return;
    NSString *key=DLText(clips[self.index][@"url"]);
    if(![self.favorites containsObject:key])[self toggleFavorite];
    [self showHeartAnimationAt:[tap locationInView:self.view]];
}
- (void)holdVideo:(UILongPressGestureRecognizer *)hold {
    if(hold.state==UIGestureRecognizerStateBegan){
        self.wasPlaying=self.player.rate>.01f;self.holdingSpeed=YES;
        if(self.wasPlaying)self.player.rate=2;
    }else if(hold.state==UIGestureRecognizerStateEnded||hold.state==UIGestureRecognizerStateCancelled){
        self.holdingSpeed=NO;if(self.wasPlaying)self.player.rate=1;
    }
}
- (void)swipe:(UISwipeGestureRecognizer *)gesture {
    NSArray *clips=[self visibleVideos];
    NSInteger next=self.index+(gesture.direction==UISwipeGestureRecognizerDirectionUp?1:-1);
    if(next<0 || next>=clips.count){
        if(self.demoMode && clips.count){
            [self transitionToIndex:next<0?(NSInteger)clips.count-1:0 direction:(gesture.direction==UISwipeGestureRecognizerDirectionUp?1:-1)];return;
        }
        if(clips.count){
            self.message.text=next<0?@"已经是第一条":@"已经是最后一条";
            [self performSelector:@selector(clearTransientMessage) withObject:nil afterDelay:1.2];
        }
        return;
    }
    [self transitionToIndex:next direction:(gesture.direction==UISwipeGestureRecognizerDirectionUp?1:-1)];
}
- (void)clearTransientMessage {if(self.player.rate>.01f)self.message.text=@"";}
- (void)toggleFavorite {
    NSArray *clips=[self visibleVideos];if(!clips.count)return;
    NSString *key=DLText(clips[self.index][@"url"]);
    if([self.favorites containsObject:key])[self.favorites removeObject:key];
    else[self.favorites addObject:key];
    [self storeLibrary];[self reloadMetadata];
    [self pulseView:self.likeButton];
}
- (void)reloadMetadata {
    NSArray *clips=[self visibleVideos];if(!clips.count){[self reloadCurrent];return;}
    NSString *key=DLText(clips[self.index][@"url"]);
    BOOL liked=[self.favorites containsObject:key];
    [self.likeButton setTitle:liked?@"♥":@"♡" forState:UIControlStateNormal];
    [self.likeButton setTitleColor:liked?[UIColor colorWithRed:1 green:.34 blue:.48 alpha:1]:[UIColor whiteColor] forState:UIControlStateNormal];
}
- (void)toggleMute {self.muted=!self.muted;self.player.muted=self.muted;[self.muteButton setTitle:self.muted?@"×":@"♪" forState:UIControlStateNormal];}
- (void)copyLink {
    NSArray *clips=[self visibleVideos];if(!clips.count)return;
    [UIPasteboard generalPasteboard].string=DLText(clips[self.index][@"url"]);
    [self alert:@"已复制" message:@"视频地址已复制到剪贴板。"];
}
- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)addVideo {
    UIAlertController *input=[UIAlertController alertControllerWithTitle:@"添加视频"
      message:@"粘贴可访问的 MP4 / HLS 视频直链，或尝试粘贴抖音分享链接。公开视频页面能否解析取决于平台限制。"
      preferredStyle:UIAlertControllerStyleAlert];
    [input addTextFieldWithConfigurationHandler:^(UITextField *field){
        field.placeholder=@"粘贴视频链接或分享文案";
        field.clearButtonMode=UITextFieldViewModeWhileEditing;
        field.text=[UIPasteboard generalPasteboard].string?:@"";
    }];
    [input addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [input addAction:[UIAlertAction actionWithTitle:@"导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *text=((UITextField *)input.textFields.firstObject).text;
        [self importText:text];
    }]];
    [self presentViewController:input animated:YES completion:nil];
}
- (void)importText:(NSString *)text {
    NSString *value=DLFindURL(text);
    NSURL *url=value.length?[NSURL URLWithString:value]:nil;
    if(!url || !([url.scheme isEqualToString:@"https"]||[url.scheme isEqualToString:@"http"])){
        [self alert:@"链接无效" message:@"请粘贴 http 或 https 的公开链接。"];
        return;
    }
    if(DLDouyinHost(url.host)){
        [self inspectPublicShare:url];
        return;
    }
    [self addPlayableURL:value name:[url lastPathComponent]?:@"我的视频" source:@"link"];
}
- (void)inspectPublicShare:(NSURL *)url {
    self.message.text=@"正在检查公开分享页…";
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:13];
    [req setValue:@"text/html,application/xhtml+xml" forHTTPHeaderField:@"Accept"];
    [req setValue:@"DouyinLite/0.1 iOS8" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSString *html=nil;
        if(data.length && data.length<500000){
            html=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if(!html)html=[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
        }
        NSDictionary *publicClip=DLVideoDetails(html);
        NSString *video=DLText(publicClip[@"url"]);
        dispatch_async(dispatch_get_main_queue(),^{
            self.message.text=@"";
            if(video.length){
                [self addPlayableURL:video name:DLText(publicClip[@"title"]) source:@"public-share"];
            }else{
                [self alert:@"暂无法从分享页播放"
                  message:@"已识别抖音分享链接，但当前公开页面未提供可直接播放的视频地址。DouyinLite 不会绕过登录、风控或视频访问限制；你可以导入已获授权的 MP4/HLS 视频直链或本机文件。"];
            }
        });
    }] resume];
}
- (void)addPlayableURL:(NSString *)address name:(NSString *)name source:(NSString *)source {
    if(!address.length)return;
    for(NSDictionary *item in self.videos){
        if([DLText(item[@"url"]) isEqualToString:address]){
            self.favoritesOnly=NO;self.historyOnly=NO;
            self.index=[self.videos indexOfObject:item];
            self.demoMode=NO;
            [self reloadCurrent];
            return;
        }
    }
    NSDictionary *entry=@{@"url":address,@"title":name.length?name:@"视频",
        @"source":source.length?source:@"link"};
    [self.videos insertObject:entry atIndex:0];
    if(self.videos.count>200)[self.videos removeLastObject];
    self.favoritesOnly=NO;self.historyOnly=NO;self.demoMode=NO;self.index=0;
    [self storeLibrary];[self reloadCurrent];
}
- (void)scanLocalVideos {
    NSMutableArray *found=[NSMutableArray array];
    NSArray *dirs=@[@"/var/mobile/Documents/DouyinLite",@"/var/mobile/Documents/PocketDrop"];
    for(NSString *folder in dirs){
        NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL];
        for(NSString *file in files){
            if(!DLPlayableFile(file))continue;
            NSString *path=[folder stringByAppendingPathComponent:file];
            BOOL isDir=NO;
            if([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && !isDir){
                NSDictionary *entry=@{@"url":[NSURL fileURLWithPath:path].absoluteString,
                    @"title":file,@"source":@"local"};
                [found addObject:entry];
            }
        }
    }
    NSInteger count=0;
    for(NSDictionary *entry in found){
        BOOL exists=NO;
        for(NSDictionary *old in self.videos)if([old[@"url"] isEqualToString:entry[@"url"]]){exists=YES;break;}
        if(!exists){[self.videos addObject:entry];count++;}
    }
    if(found.count){self.demoMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;self.index=0;}
    [self storeLibrary];
    [self alert:@"本地视频扫描完成" message:[NSString stringWithFormat:@"新增 %ld 个视频。\n扫描路径：\n/var/mobile/Documents/DouyinLite\n/var/mobile/Documents/PocketDrop",(long)count]];
    [self reloadCurrent];
}
- (void)openMenu {
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"DouyinLite"
        message:@"支持公开抖音分享页解析；官方推荐流仍需授权。演示样片使用公开许可视频。" preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"公开样片（上下滑动测试）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.demoMode=YES;self.favoritesOnly=NO;self.historyOnly=NO;self.index=0;[self reloadCurrent];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"所有视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.demoMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;self.index=0;[self reloadCurrent];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"我的收藏" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.favoritesOnly=YES;self.historyOnly=NO;self.index=0;[self reloadCurrent];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"观看历史" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.favoritesOnly=NO;self.historyOnly=YES;self.index=0;[self reloadCurrent];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"扫描本地视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self scanLocalVideos];}]];
    if([self visibleVideos].count){
        [menu addAction:[UIAlertAction actionWithTitle:@"移除当前视频" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
            NSArray *clips=[self visibleVideos];
            if(!clips.count)return;
            NSString *url=DLText(clips[self.index][@"url"]);
            NSIndexSet *indices=[self.videos indexesOfObjectsPassingTest:^BOOL(NSDictionary *item,NSUInteger idx,BOOL *stop){
                return [url isEqualToString:DLText(item[@"url"])];
            }];
            [self.videos removeObjectsAtIndexes:indices];
            [self.favorites removeObject:url];[self.history removeObject:url];
            self.index=0;[self storeLibrary];[self reloadCurrent];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)viewWillDisappear:(BOOL)animated {[self.player pause];[super viewWillDisappear:animated];}
- (void)dealloc {[self.uiTimer invalidate];[self stopCurrent];[[NSNotificationCenter defaultCenter] removeObserver:self];}
@end

@interface DLApp : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation DLApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController=[DLFeedController new];
    self.window.backgroundColor=DLBG();
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass([DLApp class]));}}
