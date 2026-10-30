#import <UIKit/UIKit.h>
#import "DLAccountSession.h"
#import "DLRemoteBrowserController.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>
@interface DLBrowserController : UIViewController
- (instancetype)initWithURL:(NSURL *)url;
@end

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

static NSString *DLShareVideoID(NSURL *url){
    if(!url||!DLDouyinHost(url.host))return nil;
    NSString *path=url.path?:@"";
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"/(?:share/)?video/([0-9]{6,25})(?:/|$)"
        options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *match=[re firstMatchInString:path options:0 range:NSMakeRange(0,path.length)];
    if(match && [match rangeAtIndex:1].location!=NSNotFound)
        return [path substringWithRange:[match rangeAtIndex:1]];
    NSURLComponents *components=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for(NSURLQueryItem *q in components.queryItems){
        if(![@[@"modal_id",@"aweme_id",@"item_ids"] containsObject:q.name])continue;
        NSString *candidate=q.value?:@"";
        NSRegularExpression *digits=[NSRegularExpression regularExpressionWithPattern:@"^[0-9]{6,25}$" options:0 error:NULL];
        if([digits numberOfMatchesInString:candidate options:0 range:NSMakeRange(0,candidate.length)]==1)
            return candidate;
    }
    return nil;
}
static NSString *DLModernMobileAgent(void){
    // A mobile web view identity is needed for the publicly rendered official share page.
    return @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1";
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


// Parse up to twelve actual official share links from a block of pasted text.
static NSArray *DLShareURLsInText(NSString *input) {
    if(!input.length)return @[];
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"https?://[^\\s<>，。]+" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSArray *matches=[re matchesInString:input options:0 range:NSMakeRange(0,MIN(input.length,(NSUInteger)16000))];
    NSMutableArray *urls=[NSMutableArray array];
    NSMutableSet *known=[NSMutableSet set];
    for(NSTextCheckingResult *match in matches){
        NSString *clean=DLFindURL([input substringWithRange:match.range]);
        NSURL *url=[NSURL URLWithString:clean];
        if(!DLDouyinHost(url.host) || ![url.scheme.lowercaseString isEqualToString:@"https"])continue;
        NSString *videoID=DLShareVideoID(url);
        NSString *unique=videoID.length?videoID:url.absoluteString;
        if([known containsObject:unique])continue;
        [known addObject:unique];
        [urls addObject:url];
        if(urls.count>=12)break;
    }
    return urls;
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
// Returns a playable URL from public video-address variants. Some web
// responses omit bit_rate but retain play_addr_h264 or play_addr_lowbr.
static NSString *DLFirstPlayableAddress(id node){
    if(![node isKindOfClass:[NSDictionary class]])return nil;
    NSDictionary *d=node;
    NSArray *links=[d[@"url_list"] isKindOfClass:[NSArray class]]?d[@"url_list"]:([d[@"urlList"] isKindOfClass:[NSArray class]]?d[@"urlList"]:@[]);
    for(id value in links){
        NSString *link=[value isKindOfClass:NSString.class]?value:
          ([value isKindOfClass:NSDictionary.class]?DLText(value[@"src"]):@"");
        NSURL *url=[NSURL URLWithString:link];
        if(([url.scheme.lowercaseString isEqualToString:@"https"]||[url.scheme.lowercaseString isEqualToString:@"http"])&&url.host.length)return link;
    }
    return nil;
}
static NSString *DLPublicPlaybackURL(NSDictionary *item) {
    NSDictionary *video=[item[@"video"] isKindOfClass:NSDictionary.class]?item[@"video"]:@{};
    NSMutableArray *rates=[NSMutableArray array];
    for(NSString *key in @[@"bit_rate",@"dynamic_video_list"]){
        id value=video[key];
        if([value isKindOfClass:NSArray.class])[rates addObjectsFromArray:value];
    }
    [rates sortUsingComparator:^NSComparisonResult(id a,id b){
        double x=[a isKindOfClass:NSDictionary.class]&&[a[@"bit_rate"] respondsToSelector:@selector(doubleValue)]?[a[@"bit_rate"] doubleValue]:1e12;
        double y=[b isKindOfClass:NSDictionary.class]&&[b[@"bit_rate"] respondsToSelector:@selector(doubleValue)]?[b[@"bit_rate"] doubleValue]:1e12;
        return x<y?NSOrderedAscending:(x>y?NSOrderedDescending:NSOrderedSame);
    }];
    // Low-bitrate AVC is gentler on the 512 MB iPhone 4S.
    for(id entry in rates){
        if(![entry isKindOfClass:NSDictionary.class])continue;
        NSDictionary *rate=entry;
        NSString *codec=[DLText(rate[@"codec_type"]) lowercaseString];
        if(codec.length && ![codec containsString:@"264"] && ![codec containsString:@"avc"])continue;
        if([rate[@"is_h265"] respondsToSelector:@selector(boolValue)]&&[rate[@"is_h265"] boolValue])continue;
        NSString *link=DLFirstPlayableAddress(rate[@"play_addr"]);
        if(!link.length)link=DLFirstPlayableAddress(rate[@"playAddr"]);
        if(link.length)return link;
    }
    for(NSString *key in @[@"play_addr_h264",@"playAddrH264",@"play_addr_lowbr"]){
        NSString *link=DLFirstPlayableAddress(video[key]);
        if(link.length)return link;
    }
    BOOL hevc=[video[@"is_h265"] respondsToSelector:@selector(boolValue)]&&[video[@"is_h265"] boolValue];
    if(!hevc){
        NSString *link=DLFirstPlayableAddress(video[@"play_addr"]);
        if(!link.length)link=DLFirstPlayableAddress(video[@"playAddr"]);
        if(link.length)return link;
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


static UIImage *DLLineIcon(NSString *kind,CGFloat size,UIColor *color){
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size,size),NO,0);
    CGContextRef c=UIGraphicsGetCurrentContext();
    if(!c)return nil;
    CGContextScaleCTM(c,size/24.0,size/24.0);
    CGContextSetLineWidth(c,1.85);
    CGContextSetLineCap(c,kCGLineCapRound);
    CGContextSetLineJoin(c,kCGLineJoinRound);
    CGContextSetStrokeColorWithColor(c,color.CGColor);
    CGContextSetFillColorWithColor(c,color.CGColor);
    if([kind isEqualToString:@"heart"]||[kind isEqualToString:@"heart-on"]){
        CGContextMoveToPoint(c,12,20.5);
        CGContextAddCurveToPoint(c,3.2,12.7,2.0,8.5,4,5.7);
        CGContextAddCurveToPoint(c,6.0,2.6,10.0,3.3,12,6.1);
        CGContextAddCurveToPoint(c,14.0,3.3,18.0,2.6,20,5.7);
        CGContextAddCurveToPoint(c,22,8.5,20.8,12.7,12,20.5);
        CGContextClosePath(c);
        if([kind isEqualToString:@"heart-on"])CGContextDrawPath(c,kCGPathFillStroke);
        else CGContextStrokePath(c);
    }else if([kind isEqualToString:@"plus"]){
        CGContextMoveToPoint(c,12,4);CGContextAddLineToPoint(c,12,20);
        CGContextMoveToPoint(c,4,12);CGContextAddLineToPoint(c,20,12);CGContextStrokePath(c);
    }else if([kind isEqualToString:@"menu"]){
        for(int y=6;y<=18;y+=6){CGContextMoveToPoint(c,4,y);CGContextAddLineToPoint(c,20,y);}
        CGContextStrokePath(c);
    }else if([kind isEqualToString:@"share"]){
        CGContextMoveToPoint(c,12,3);CGContextAddLineToPoint(c,12,15);
        CGContextMoveToPoint(c,7,8);CGContextAddLineToPoint(c,12,3);CGContextAddLineToPoint(c,17,8);
        CGContextMoveToPoint(c,4.5,13);CGContextAddLineToPoint(c,4.5,19);
        CGContextAddQuadCurveToPoint(c,4.5,21,7,21);
        CGContextAddLineToPoint(c,17,21);CGContextAddQuadCurveToPoint(c,19.5,21,19.5,18.5);
        CGContextAddLineToPoint(c,19.5,13);CGContextStrokePath(c);
    }else if([kind isEqualToString:@"sound"]||[kind isEqualToString:@"muted"]){
        CGContextMoveToPoint(c,3,9);CGContextAddLineToPoint(c,7,9);
        CGContextAddLineToPoint(c,12,5);CGContextAddLineToPoint(c,12,19);
        CGContextAddLineToPoint(c,7,15);CGContextAddLineToPoint(c,3,15);CGContextClosePath(c);
        CGContextStrokePath(c);
        if([kind isEqualToString:@"sound"]){
            CGContextMoveToPoint(c,16,9);CGContextAddQuadCurveToPoint(c,19,12,16,15);
            CGContextMoveToPoint(c,18,6);CGContextAddQuadCurveToPoint(c,24,12,18,18);
        }else{
            CGContextMoveToPoint(c,16,9);CGContextAddLineToPoint(c,21,15);
            CGContextMoveToPoint(c,21,9);CGContextAddLineToPoint(c,16,15);
        }
        CGContextStrokePath(c);
    }else if([kind isEqualToString:@"play"]){
        CGContextMoveToPoint(c,8,4.5);CGContextAddLineToPoint(c,19,12);
        CGContextAddLineToPoint(c,8,19.5);CGContextClosePath(c);CGContextStrokePath(c);
    }else if([kind isEqualToString:@"pause"]){
        CGContextMoveToPoint(c,8,5);CGContextAddLineToPoint(c,8,19);
        CGContextMoveToPoint(c,16,5);CGContextAddLineToPoint(c,16,19);CGContextStrokePath(c);
    }else if([kind isEqualToString:@"home"]){
        CGContextMoveToPoint(c,3,11);CGContextAddLineToPoint(c,12,3.5);
        CGContextAddLineToPoint(c,21,11);
        CGContextMoveToPoint(c,5.5,10);CGContextAddLineToPoint(c,5.5,20);
        CGContextAddLineToPoint(c,18.5,20);CGContextAddLineToPoint(c,18.5,10);
        CGContextMoveToPoint(c,10,20);CGContextAddLineToPoint(c,10,14);
        CGContextAddLineToPoint(c,14,14);CGContextAddLineToPoint(c,14,20);CGContextStrokePath(c);
    }else if([kind isEqualToString:@"search"]){
        CGContextAddArc(c,10.5,10.5,6.5,0,2*M_PI,0);
        CGContextMoveToPoint(c,15.1,15.1);CGContextAddLineToPoint(c,21,21);CGContextStrokePath(c);
    }else if([kind isEqualToString:@"user"]){
        CGContextAddArc(c,12,8,4.1,0,2*M_PI,0);
        CGContextMoveToPoint(c,4.5,21);CGContextAddQuadCurveToPoint(c,3.9,14,12,14);
        CGContextAddQuadCurveToPoint(c,20.1,14,19.5,21);CGContextStrokePath(c);
    }else if([kind isEqualToString:@"clock"]){
        CGContextAddArc(c,12,12,9,0,2*M_PI,0);
        CGContextMoveToPoint(c,12,6.5);CGContextAddLineToPoint(c,12,12);
        CGContextAddLineToPoint(c,16,14);CGContextStrokePath(c);
    }else if([kind isEqualToString:@"grid"]){
        for(int y=4;y<=14;y+=10)for(int x=4;x<=14;x+=10){
            CGContextStrokeRect(c,CGRectMake(x,y,6,6));
        }
    }else if([kind isEqualToString:@"back"]){
        CGContextMoveToPoint(c,15.5,4.5);CGContextAddLineToPoint(c,8,12);
        CGContextAddLineToPoint(c,15.5,19.5);CGContextStrokePath(c);
    }
    UIImage *result=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}
static void DLStyleIcon(UIButton *button,NSString *kind,CGFloat size,UIColor *color){
    [button setTitle:nil forState:UIControlStateNormal];
    [button setImage:DLLineIcon(kind,size,color) forState:UIControlStateNormal];
    button.adjustsImageWhenHighlighted=NO;
    button.imageView.contentMode=UIViewContentModeScaleAspectFit;
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
@property(nonatomic,strong) NSMutableArray *onlineVideos;
@property(nonatomic,strong) NSMutableArray *pendingShareURLs;
@property(nonatomic,assign) NSUInteger batchImported;
@property(nonatomic,assign) NSUInteger batchFailed;
@property(nonatomic,assign) NSUInteger batchTotal;
@property(nonatomic,assign) BOOL batchInProgress;
@property(nonatomic,strong) NSMutableSet *refreshedShareOrigins;

@property(nonatomic,assign) BOOL onlineMode;
@property(nonatomic,assign) BOOL onlineLoading;
@property(nonatomic,assign) NSInteger onlineOffset;
@property(nonatomic,assign) NSInteger onlineInstance;
@property(nonatomic,assign) NSUInteger onlineRequestID;
@property(nonatomic,assign) BOOL onlinePaging;
@property(nonatomic,assign) BOOL accountReloadPending;
@property(nonatomic,assign) BOOL douyinEnd;
@property(nonatomic,strong) NSDate *douyinRetryAfter;
@property(nonatomic,copy) NSString *onlineError;
@property(nonatomic,strong) AVURLAsset *nextAsset;
@property(nonatomic,copy) NSString *nextURL;
@property(nonatomic,copy) NSString *feedNextPageURL;
@property(nonatomic,copy) NSString *preloadSourceURL;
@property(nonatomic,strong) UIActivityIndicatorView *loadingIndicator;
@property(nonatomic,assign) BOOL animationsEnabled;
@property(nonatomic,assign) BOOL preloadEnabled;
@property(nonatomic,assign) BOOL autoplayNext;
@property(nonatomic,assign) BOOL transitioning;
@property(nonatomic,assign) NSUInteger transitionID;
@property(nonatomic,strong) NSMutableDictionary *positions;
@property(nonatomic,copy) NSString *playingURL;
@property(nonatomic,assign) NSTimeInterval lastPositionSave;
@property(nonatomic,assign) BOOL demoMode;
@property(nonatomic,assign) BOOL scanning;
@property(nonatomic,assign) NSInteger failedDemoCount;
@property(nonatomic,strong) UIView *rightRail;
@property(nonatomic,strong) UIView *tabBar;
@property(nonatomic,strong) NSArray *tabButtons;
@property(nonatomic,strong) NSArray *tabLabels;
@property(nonatomic,strong) NSArray *searchResults;
@property(nonatomic,copy) NSString *searchQuery;
@property(nonatomic,assign) BOOL searchMode;
@property(nonatomic,assign) BOOL panning;
@property(nonatomic,assign) NSInteger activeTab;
@property(nonatomic,assign) NSInteger paintedTab;
@property(nonatomic,assign) BOOL lastPlayingIcon;
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
    [DLAccountSession shared];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountChanged) name:DLAccountDidChangeNotification object:nil];
    self.view.backgroundColor=DLBG();
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    self.videos=[[[defaults arrayForKey:@"dl_library_v1"]?:@[] mutableCopy] mutableCopy];
    self.favorites=[[[defaults arrayForKey:@"dl_favorites_v1"]?:@[] mutableCopy] mutableCopy];
    self.history=[[[defaults arrayForKey:@"dl_history_v1"]?:@[] mutableCopy] mutableCopy];
    self.positions=[[[defaults dictionaryForKey:@"dl_positions_v1"]?:@{} mutableCopy] mutableCopy];
    self.refreshedShareOrigins=[NSMutableSet set];
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
    self.onlineVideos=[NSMutableArray array];
    self.onlineMode=YES;self.demoMode=NO;self.index=0;
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
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(verticalPan:)];
    pan.delegate=self;
    pan.maximumNumberOfTouches=1;
    pan.cancelsTouchesInView=NO;
    [self.view addGestureRecognizer:pan];
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
    UIButton *add=[self button:@"" action:@selector(addVideo) font:18];
    DLStyleIcon(add,@"plus",24,[UIColor whiteColor]);
    add.tag=101;[top addSubview:add];
    UIButton *menu=[self button:@"" action:@selector(openMenu) font:18];
    DLStyleIcon(menu,@"menu",22,[UIColor whiteColor]);
    menu.tag=102;[top addSubview:menu];

    self.rightRail=[[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.rightRail];
    self.likeButton=[self button:@"" action:@selector(toggleFavorite) font:20];
    DLStyleIcon(self.likeButton,@"heart",29,[UIColor whiteColor]);
    [self.rightRail addSubview:self.likeButton];
    UILabel *likeLabel=[self label:10];likeLabel.text=@"收藏";
    likeLabel.textAlignment=NSTextAlignmentCenter;likeLabel.tag=111;[self.rightRail addSubview:likeLabel];
    UIButton *share=[self button:@"" action:@selector(shareCurrent) font:20];
    DLStyleIcon(share,@"share",27,[UIColor whiteColor]);
    [self.rightRail addSubview:share];share.tag=112;
    UILabel *shareLabel=[self label:10];shareLabel.text=@"分享";
    shareLabel.textAlignment=NSTextAlignmentCenter;shareLabel.tag=113;[self.rightRail addSubview:shareLabel];
    self.muteButton=[self button:@"" action:@selector(toggleMute) font:20];
    DLStyleIcon(self.muteButton,@"sound",26,[UIColor whiteColor]);
    [self.rightRail addSubview:self.muteButton];
    UILabel *muteLabel=[self label:10];muteLabel.text=@"声音";
    muteLabel.textAlignment=NSTextAlignmentCenter;muteLabel.tag=114;[self.rightRail addSubview:muteLabel];

    self.playButton=[self button:@"" action:@selector(togglePlay) font:28];
    DLStyleIcon(self.playButton,@"play",42,[UIColor whiteColor]);
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

    self.tabBar=[[UIView alloc] initWithFrame:CGRectZero];
    self.tabBar.backgroundColor=[UIColor colorWithRed:.045 green:.052 blue:.064 alpha:.98];
    [self.view addSubview:self.tabBar];
    NSArray *kinds=@[@"home",@"search",@"heart",@"user"];
    NSArray *names=@[@"首页",@"搜索",@"收藏",@"我的"];
    NSMutableArray *buttons=[NSMutableArray array];
    NSMutableArray *labels=[NSMutableArray array];
    for(NSInteger i=0;i<4;i++){
        UIButton *button=[self button:@"" action:@selector(tabPressed:) font:12];
        button.tag=200+i;
        button.contentVerticalAlignment=UIControlContentVerticalAlignmentTop;
        DLStyleIcon(button,kinds[i],23,[UIColor whiteColor]);
        UILabel *label=[self label:10];
        label.text=names[i];
        label.textAlignment=NSTextAlignmentCenter;
        label.userInteractionEnabled=NO;
        [button addSubview:label];
        [buttons addObject:button];[labels addObject:label];
        [self.tabBar addSubview:button];
    }
    self.tabButtons=buttons;self.tabLabels=labels;
    self.activeTab=0;
    self.paintedTab=-1;


    self.uiTimer=[NSTimer scheduledTimerWithTimeInterval:.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self layoutScreen];
    [self reloadCurrent];
    [self loadOnlineFeed:YES];
}
- (void)viewDidLayoutSubviews {[super viewDidLayoutSubviews];[self layoutScreen];}
- (void)layoutScreen {
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    UIView *top=[self.view viewWithTag:100];top.frame=CGRectMake(0,0,w,60);
    self.topText.frame=CGRectMake(54,13,MAX(100,w-108),38);
    [top viewWithTag:101].frame=CGRectMake(w-49,10,43,43);
    [top viewWithTag:102].frame=CGRectMake(6,10,43,43);
    self.rightRail.frame=CGRectMake(w-64,MAX(92,h-352),59,205);
    self.likeButton.frame=CGRectMake(2,0,55,45);
    [self.rightRail viewWithTag:111].frame=CGRectMake(2,42,55,22);
    [self.rightRail viewWithTag:112].frame=CGRectMake(2,68,55,45);
    [self.rightRail viewWithTag:113].frame=CGRectMake(2,111,55,22);
    self.muteButton.frame=CGRectMake(2,142,55,39);
    [self.rightRail viewWithTag:114].frame=CGRectMake(2,181,55,20);
    self.playButton.frame=CGRectMake((w-82)/2,(h-82)/2,82,82);
    self.titleText.frame=CGRectMake(14,h-179,MAX(100,w-93),42);
    self.subtitleText.frame=CGRectMake(14,h-137,MAX(100,w-93),43);
    self.countText.frame=CGRectMake(MAX(140,w-94),h-91,78,22);
    self.message.frame=CGRectMake(20,MAX(85,(h-100)/2),w-40,110);
    self.loadingIndicator.center=CGPointMake(w/2,MAX(78,h/2-49));
    self.tabBar.frame=CGRectMake(0,h-52,w,52);
    CGFloat tabWidth=w/4.0;
    for(NSInteger i=0;i<self.tabButtons.count;i++){
        UIButton *btn=self.tabButtons[i];
        btn.frame=CGRectMake(i*tabWidth,0,tabWidth,52);
        UILabel *label=self.tabLabels[i];
        label.frame=CGRectMake(0,32,tabWidth,16);
    }
    self.progress.frame=CGRectMake(0,h-55,w,3);
}

// Independent PeerTube public feed. It is deliberately NOT a Douyin recommender.
- (NSArray *)networkHosts {
    return @[@"https://diode.zone",@"https://tilvids.com",@"https://peertube.tv"];
}
- (NSString *)networkHost {
    NSArray *hosts=[self networkHosts];
    return hosts[(NSUInteger)MIN(MAX(0,self.onlineInstance),(NSInteger)hosts.count-1)];
}
- (void)onlineRequest:(NSString *)url finished:(void (^)(NSDictionary *,NSString *))done {
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];
    [req setValue:@"DouyinLite/0.5 (iOS 8; public Peertube client)" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSDictionary *json=nil;
        NSString *problem=nil;
        if(error)problem=error.localizedDescription?:@"网络连接失败";
        else if([response isKindOfClass:[NSHTTPURLResponse class]]&&[(NSHTTPURLResponse *)response statusCode]>=400)
            problem=[NSString stringWithFormat:@"服务器 HTTP %ld",(long)[(NSHTTPURLResponse *)response statusCode]];
        else if(data.length && data.length<900000){
            id object=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if([object isKindOfClass:[NSDictionary class]])json=object;
            else problem=@"服务器返回的数据无法识别";
        }else problem=@"服务器无有效响应";
        dispatch_async(dispatch_get_main_queue(),^{done(json,problem);});
    }] resume];
}
- (NSString *)peerStreamFromVideo:(NSDictionary *)detail {
    NSArray *files=[detail[@"files"] isKindOfClass:[NSArray class]]?detail[@"files"]:@[];
    NSString *best=nil;
    NSInteger bestScore=100000;
    for(id candidate in files){
        if(![candidate isKindOfClass:[NSDictionary class]])continue;
        NSDictionary *file=candidate;
        NSString *link=DLText(file[@"fileUrl"]);
        if(!link.length)link=DLText(file[@"fileDownloadUrl"]);
        NSString *lower=[[NSURL URLWithString:link].path lowercaseString];
        if(![lower hasSuffix:@".mp4"] && ![lower hasSuffix:@".m4v"])continue;
        NSDictionary *resolution=[file[@"resolution"] isKindOfClass:[NSDictionary class]]?file[@"resolution"]:@{};
        NSInteger h=[resolution[@"id"] integerValue];
        if(h<=0)h=480;
        NSInteger score=ABS(h-360)+(h>720?1800:0);
        if(score<bestScore){bestScore=score;best=link;}
    }
    if(best.length)return best;
    NSArray *playlists=[detail[@"streamingPlaylists"] isKindOfClass:[NSArray class]]?detail[@"streamingPlaylists"]:@[];
    for(id candidate in playlists){
        if(![candidate isKindOfClass:[NSDictionary class]])continue;
        NSString *url=DLText(candidate[@"playlistUrl"]);
        if([url hasPrefix:@"https://"] || [url hasPrefix:@"http://"])return url;
    }
    return nil;
}
- (void)fetchOnlineCandidates:(NSArray *)items index:(NSUInteger)i token:(NSUInteger)token before:(NSUInteger)before {
    if(token!=self.onlineRequestID)return;
    if(i>=items.count){
        self.onlineLoading=NO;self.onlinePaging=NO;
        self.onlineOffset+=35;
        if(self.onlineVideos.count==before && before==0 && self.onlineInstance+1<[self networkHosts].count){
            self.onlineInstance++;
            [self loadOnlineFeed:YES preserveHost:YES];
            return;
        }
        if(self.onlineVideos.count==0){
            self.onlineError=@"公开视频源没有提供兼容 MP4/HLS，或网络连接失败。\n可以在左上角菜单重试、切换公开样片，或导入自己的视频。";
            if(self.onlineMode)[self reloadCurrent];
        }
        return;
    }
    NSDictionary *entry=items[i];
    NSString *idString=DLText(entry[@"uuid"]);
    if(!idString.length)idString=DLText(entry[@"id"]);
    if(!idString.length){[self fetchOnlineCandidates:items index:i+1 token:token before:before];return;}
    NSString *url=[NSString stringWithFormat:@"%@/api/v1/videos/%@",[self networkHost],idString];
    [self onlineRequest:url finished:^(NSDictionary *detail,NSString *problem){
        if(token!=self.onlineRequestID)return;
        NSString *stream=[self peerStreamFromVideo:detail?:@{}];
        if(stream.length){
            NSString *title=DLText(detail[@"name"]);
            if(!title.length)title=DLText(entry[@"name"]);
            NSString *original=DLText(detail[@"url"]);
            if(!original.length)original=DLText(entry[@"url"]);
            NSDictionary *clip=@{@"url":stream,@"title":title.length?title:@"网络公开视频",
                @"source":@"peertube",@"originURL":original.length?original:url};
            BOOL duplicate=NO;
            for(NSDictionary *existing in self.onlineVideos){
                if([DLText(existing[@"url"]) isEqualToString:stream]){duplicate=YES;break;}
            }
            if(!duplicate){
                [self.onlineVideos addObject:clip];
                if(self.onlineMode&&!self.favoritesOnly&&!self.historyOnly&&self.onlineVideos.count==1){
                    self.index=0;[self reloadCurrent];
                }
            }
        }
        [self fetchOnlineCandidates:items index:i+1 token:token before:before];
    }];
}
- (void)openCloudChrome {
    NSString *address=[[NSUserDefaults standardUserDefaults] stringForKey:@"dl_feed_endpoint_v1"]?:@"";
    NSString *key=[[NSUserDefaults standardUserDefaults] stringForKey:@"dl_bridge_key_v1"]?:@"";
    NSURL *url=[NSURL URLWithString:address];
    if(![url.scheme isEqualToString:@"https"]||![url.path hasSuffix:@"/api/feed"]||!url.host.length||!key.length){
        [self alert:@"请先连接云端" message:@"在视频来源中选择「连接 DouyinBridge」，填写已部署服务器的 HTTPS /api/feed 地址和密钥，再打开云端 Chrome。"];
        return;
    }
    [self.player pause];
    DLRemoteBrowserController *viewer=[[DLRemoteBrowserController alloc]initWithFeedURL:url apiKey:key];
    [self presentViewController:viewer animated:YES completion:nil];
}
- (void)checkBridgeLoginStatus {
 NSString *base=[[NSUserDefaults standardUserDefaults] stringForKey:@"dl_feed_endpoint_v1"];
 NSURL *feed=[NSURL URLWithString:base];
 if(![feed.scheme isEqualToString:@"https"] || !feed.host.length){
    [self alert:@"尚未连接云端" message:@"请先在视频来源菜单连接 DouyinBridge，并填写服务器地址和 API 密钥。"];
    return;
 }
 NSURLComponents *parts=[NSURLComponents componentsWithURL:feed resolvingAgainstBaseURL:NO];
 NSString *path=parts.path?:@"";
 if(![path hasSuffix:@"/api/feed"]){
    [self alert:@"地址不兼容" message:@"请填写 DouyinBridge 的 /api/feed 地址后再检查登录。"];
    return;
 }
 parts.path=[[path substringToIndex:path.length-4] stringByAppendingString:@"status"];
 parts.query=nil;parts.fragment=nil;
 NSURL *endpoint=parts.URL;
 NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:endpoint cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
 NSString *key=[[NSUserDefaults standardUserDefaults] stringForKey:@"dl_bridge_key_v1"];
 if(key.length)[request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
 [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
    NSDictionary *json=nil;
    if(data.length && data.length<200000){
        id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if([obj isKindOfClass:[NSDictionary class]])json=obj;
    }
    NSHTTPURLResponse *http=[response isKindOfClass:[NSHTTPURLResponse class]]?(NSHTTPURLResponse *)response:nil;
    BOOL cookie=[json[@"session_cookie_present"] respondsToSelector:@selector(boolValue)]?[json[@"session_cookie_present"] boolValue]:NO;
    NSString *status=DLText(json[@"status"]);
    NSString *account=cookie?@"已检测到账号会话，仍需确认登录是否有效":@"未检测到账号登录会话";
    NSString *detail=@"";
    if(http.statusCode==401)detail=@"云端 API 密钥错误，请重新配置。";
    else if(error)detail=error.localizedDescription;
    else if([status isEqualToString:@"verification_required"])detail=@"云端浏览器正在等待人工验证。";
    else if([status isEqualToString:@"ready"])detail=@"云端已获取到可访问的视频。";
    else if([status isEqualToString:@"waiting_for_videos"])detail=@"当前暂无视频，请在云端浏览器确认登录和页面播放状态。";
    else if([status isEqualToString:@"browser_error"])detail=DLText(json[@"error"]);
    else detail=@"请检查云端服务状态。";
    NSString *message=[NSString stringWithFormat:@"%@\n%@\n缓存视频：%@\n\n首次登录：在电脑上通过 SSH 隧道打开云端浏览器，扫码登录后会保存会话。",account,detail,DLText(json[@"items"])];
    dispatch_async(dispatch_get_main_queue(),^{[self alert:@"DouyinBridge 登录状态" message:message];});
 }] resume];
}

- (void)configureJSONFeed {
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"连接 DouyinBridge"
 message:@"填写自己部署的 HTTPS 视频列表接口。浏览器会话可能需要人工验证；当前应用不会绕过平台限制。"
 preferredStyle:UIAlertControllerStyleAlert];
 [a addTextFieldWithConfigurationHandler:^(UITextField *t){
   t.placeholder=@"https://bridge.example.com/api/feed";
   t.text=[[NSUserDefaults standardUserDefaults] stringForKey:@"dl_feed_endpoint_v1"]?:@"";
   t.keyboardType=UIKeyboardTypeURL;t.autocapitalizationType=UITextAutocapitalizationTypeNone;
 }];
 [a addTextFieldWithConfigurationHandler:^(UITextField *t){
   t.placeholder=@"云端 API 密钥";
   t.text=[[NSUserDefaults standardUserDefaults] stringForKey:@"dl_bridge_key_v1"]?:@"";
   t.secureTextEntry=YES;t.autocapitalizationType=UITextAutocapitalizationTypeNone;
 }];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"连接并加载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
    NSString *s=[((UITextField *)a.textFields[0]).text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *key=[((UITextField *)a.textFields[1]).text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *url=[NSURL URLWithString:s];
    if(![url.scheme isEqualToString:@"https"]||!url.host.length){[self alert:@"无效地址" message:@"请填写有效的 HTTPS 云端列表地址。"];return;}
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    [defaults setObject:s forKey:@"dl_feed_endpoint_v1"];
    [defaults setObject:key?:@"" forKey:@"dl_bridge_key_v1"];
    [defaults setBool:NO forKey:@"dl_use_peertube_v1"];
    self.feedNextPageURL=nil;self.onlineMode=YES;self.demoMode=NO;self.searchMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;
    [self loadOnlineFeed:YES];
 }]];
 [self presentViewController:a animated:YES completion:nil];
}
- (void)loadJSONFeed:(BOOL)reset {
 NSString *base=[[NSUserDefaults standardUserDefaults] stringForKey:@"dl_feed_endpoint_v1"];
 if(!base.length)return;
 if(self.onlineLoading&&!reset)return;
 if(!reset && !self.feedNextPageURL.length)return;
 if(reset){[self.onlineVideos removeAllObjects];self.onlineError=nil;self.onlineOffset=0;self.index=0;}
 self.onlineLoading=YES;self.onlinePaging=YES;
 NSUInteger token=++self.onlineRequestID;
 NSString *endpoint=base;
 if(!reset && self.feedNextPageURL.length)endpoint=self.feedNextPageURL;
 if(reset)self.feedNextPageURL=nil;
 NSURL *url=[NSURL URLWithString:endpoint];
 if(![url.scheme isEqualToString:@"https"]){self.onlineLoading=NO;self.onlinePaging=NO;self.onlineError=@"内容接口需要 HTTPS";[self reloadCurrent];return;}
 NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:18];
 NSString *bridgeKey=[[NSUserDefaults standardUserDefaults] stringForKey:@"dl_bridge_key_v1"];
 if(bridgeKey.length)[req setValue:[@"Bearer " stringByAppendingString:bridgeKey] forHTTPHeaderField:@"Authorization"];
 [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
  id parsed=(data.length && data.length<2000000)?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
  NSDictionary *json=[parsed isKindOfClass:[NSDictionary class]]?parsed:@{};
  NSArray *rows=[json[@"data"] isKindOfClass:[NSArray class]]?json[@"data"]:@[];
  NSMutableArray *incoming=[NSMutableArray array];
  for(id value in rows){
    if(![value isKindOfClass:[NSDictionary class]])continue;
    NSDictionary *item=value;NSString *link=DLText(item[@"url"]);
    NSURL *candidate=[NSURL URLWithString:link];
    if(![candidate.scheme isEqualToString:@"https"])continue;
    BOOL duplicate=NO;
    for(NSDictionary *old in self.onlineVideos)if([DLText(old[@"url"]) isEqualToString:link]){duplicate=YES;break;}
    if(!duplicate)[incoming addObject:@{@"url":link,@"title":DLText(item[@"title"]).length?DLText(item[@"title"]):@"公开视频",@"source":DLText(item[@"source"]).length?DLText(item[@"source"]):@"custom"}];
    if(incoming.count>=30)break;
  }
  dispatch_async(dispatch_get_main_queue(),^{
    if(token!=self.onlineRequestID)return;
    [self.onlineVideos addObjectsFromArray:incoming];
    NSString *next=DLText(json[@"next"]);NSURL *nextURL=[NSURL URLWithString:next];
    NSURL *baseURL=[NSURL URLWithString:base];
    BOOL sameHost=[nextURL.host isEqualToString:baseURL.host] &&
                  ((!nextURL.port && !baseURL.port) || [nextURL.port isEqual:baseURL.port]);
    self.feedNextPageURL=([nextURL.scheme isEqualToString:@"https"] && sameHost)?next:nil;
    self.onlineOffset+=rows.count;
    self.onlineLoading=NO;self.onlinePaging=NO;
    if(!self.onlineVideos.count){
      NSHTTPURLResponse *http=[response isKindOfClass:[NSHTTPURLResponse class]]?(NSHTTPURLResponse *)response:nil;
      self.onlineError=[NSString stringWithFormat:@"云端暂无可播放视频（HTTP %ld）：%@",(long)http.statusCode,error.localizedDescription?: (DLText(json[@"message"]).length?DLText(json[@"message"]):@"请检查云端浏览器是否需要验证")];
    }
    if(self.onlineMode && (reset || self.onlineVideos.count==incoming.count))[self reloadCurrent];
    else if(self.onlineMode)[self reloadMetadata];
  });
 }] resume];
}

- (void)loadDouyinAccountFeed:(BOOL)reset {
 if(self.onlineLoading&&!reset)return;
 if(!reset&&(self.douyinEnd||self.douyinRetryAfter.timeIntervalSinceNow>0))return;
 if(reset){self.onlineOffset=0;self.index=0;[self.onlineVideos removeAllObjects];self.onlineError=nil;self.douyinEnd=NO;self.douyinRetryAfter=nil;}
 self.onlineLoading=YES;self.onlinePaging=YES;
 NSUInteger token=++self.onlineRequestID;
 NSString *signError=nil;
 NSMutableURLRequest *request=[DLAccountSession.shared feedRequestAtPage:self.onlineOffset reset:reset error:&signError];
 if(!request){self.onlineLoading=NO;self.onlinePaging=NO;self.onlineError=signError;[self reloadCurrent];return;}
 if(reset){self.message.text=DLAccountSession.shared.hasSession?@"正在用本机账号加载抖音内容…":@"正在连接抖音，可在「我」中登录账号";[self.loadingIndicator startAnimating];}
 [DLAccountSession.shared requestJSON:request completion:^(NSDictionary *root,NSString *problem){
  if(token!=self.onlineRequestID)return;
  id nested=root[@"data"];
  NSDictionary *body=[nested isKindOfClass:NSDictionary.class]?nested:root;
  NSArray *rows=nil;
  for(NSString *key in @[@"aweme_list",@"item_list",@"list",@"feed_list"]){if([body[key] isKindOfClass:NSArray.class]){rows=body[key];break;}}
  if(!rows&&[nested isKindOfClass:NSArray.class])rows=nested;
  NSMutableArray *items=[NSMutableArray array];NSMutableSet *known=[NSMutableSet set];
  for(NSDictionary *old in self.onlineVideos)[known addObject:DLText(old[@"id"]).length?old[@"id"]:DLText(old[@"url"])];
  for(id obj in rows){
   if(![obj isKindOfClass:NSDictionary.class])continue;
   NSDictionary *entry=obj;if([entry[@"aweme_info"] isKindOfClass:NSDictionary.class])entry=entry[@"aweme_info"];
   NSString *address=DLPublicPlaybackURL(entry);if(!address.length)continue;
   NSString *vid=DLText(entry[@"aweme_id"]);NSString *identity=vid.length?vid:address;if([known containsObject:identity])continue;[known addObject:identity];
   NSDictionary *author=[entry[@"author"] isKindOfClass:NSDictionary.class]?entry[@"author"]:@{};
   NSString *title=DLText(entry[@"desc"]);if(!title.length)title=DLText(author[@"nickname"]);if(!title.length)title=@"抖音视频";
   [items addObject:@{@"id":vid,@"url":address,@"title":title,@"source":@"douyin-account"}];if(items.count>=20)break;
  }
  self.onlineLoading=NO;self.onlinePaging=NO;
  if(rows.count)self.onlineOffset++;
  [self.onlineVideos addObjectsFromArray:items];
  // Keep at most 120 feed entries without discarding the current or upcoming video.
  NSInteger remove=MIN(MAX(0,(NSInteger)self.onlineVideos.count-120),MAX(0,self.index-10));
  if(remove>0){[self.onlineVideos removeObjectsInRange:NSMakeRange(0,remove)];self.index-=remove;}
  if(!items.count){
   self.douyinRetryAfter=[NSDate dateWithTimeIntervalSinceNow:15];
   if(!problem&&[body[@"has_more"] respondsToSelector:@selector(boolValue)]&&![body[@"has_more"] boolValue])self.douyinEnd=YES;
   NSString *reason=problem;
   if(!reason.length){NSString *code=DLText(root[@"status_code"]);if(!code.length)code=DLText(body[@"status_code"]);reason=code.length&&![code isEqualToString:@"0"]?[NSString stringWithFormat:@"内容接口返回状态 %@。",code]:@"未返回新的兼容视频，可能需要账号登录或网页验证。";}
   self.onlineError=[reason stringByAppendingString:@"\n也可以点右上角＋，粘贴公开视频分享链接直接播放。"];
   if(self.onlineVideos.count){self.message.text=@"本次未取得新视频，稍后可重试";[self performSelector:@selector(clearTransientMessage) withObject:nil afterDelay:2];}
  }else{self.onlineError=nil;self.douyinRetryAfter=nil;[DLAccountSession.shared saveSession];}
  if(self.onlineMode && !self.presentedViewController){if(reset||self.onlineVideos.count==items.count)[self reloadCurrent];else [self reloadMetadata];}
 }];
}
- (void)loadOnlineFeed:(BOOL)reset {
    // Only direct on-device requests: ignore settings left by previous releases.
    [self loadDouyinAccountFeed:reset];
}
- (void)loadOnlineFeed:(BOOL)reset preserveHost:(BOOL)preserveHost {
    if(self.onlineLoading&&!reset)return;
    if(reset){
        if(!preserveHost)self.onlineInstance=0;
        self.onlineOffset=0;self.index=0;
        [self.onlineVideos removeAllObjects];
        self.onlineError=nil;
    }
    self.onlineLoading=YES;self.onlinePaging=YES;
    NSUInteger token=++self.onlineRequestID;
    if(self.onlineMode && self.onlineVideos.count==0){
        self.message.text=@"正在获取真实公开视频…\n（来源 PeerTube，不是抖音推荐）";
        [self.loadingIndicator startAnimating];
    }
    NSString *endpoint=[NSString stringWithFormat:@"%@/api/v1/videos?start=%ld&count=35&sort=-publishedAt&nsfw=false&isLocal=true",
         [self networkHost],(long)self.onlineOffset];
    [self onlineRequest:endpoint finished:^(NSDictionary *json,NSString *problem){
        if(token!=self.onlineRequestID)return;
        NSArray *rows=[json[@"data"] isKindOfClass:[NSArray class]]?json[@"data"]:@[];
        NSMutableArray *candidates=[NSMutableArray array];
        for(id object in rows){
            if(![object isKindOfClass:[NSDictionary class]])continue;
            NSDictionary *video=object;
            if([video[@"isLive"] boolValue])continue;
            NSInteger duration=[video[@"duration"] integerValue];
            if(duration<3 || duration>900)continue;
            NSNumber *privacy=[video[@"privacy"] isKindOfClass:[NSDictionary class]]?video[@"privacy"][@"id"]:nil;
            if(privacy && [privacy integerValue]!=1)continue;
            [candidates addObject:video];
            if(candidates.count>=16)break;
        }
        if(candidates.count){
            [self fetchOnlineCandidates:candidates index:0 token:token before:self.onlineVideos.count];
        }else{
            self.onlineLoading=NO;self.onlinePaging=NO;
            if(self.onlineVideos.count==0 && self.onlineInstance+1<[self networkHosts].count){
                self.onlineInstance++;[self loadOnlineFeed:YES preserveHost:YES];
            }else if(self.onlineVideos.count==0){
                self.onlineError=[NSString stringWithFormat:@"网络公开视频加载失败：%@\n可切换公开样片，或导入已有播放地址。",problem?:@"没有符合条件的兼容视频"];
                if(self.onlineMode)[self reloadCurrent];
            }
        }
    }];
}
- (NSArray *)visibleVideos {
    if(self.searchMode)return self.searchResults?:@[];
    if(self.onlineMode&&!self.favoritesOnly&&!self.historyOnly)return self.onlineVideos;
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
    if(!self.favoritesOnly&&!self.historyOnly&&!self.onlineMode)
        [[NSUserDefaults standardUserDefaults] setInteger:self.index forKey:self.demoMode?@"dl_demo_index_v1":@"dl_library_index_v1"];
}
- (void)setLoading:(BOOL)busy {
    _loading=busy;
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
    UIImageView *heart=[[UIImageView alloc] initWithImage:DLLineIcon(@"heart",82,[UIColor colorWithRed:1 green:.28 blue:.43 alpha:1])];
    heart.frame=CGRectMake(point.x-41,point.y-41,82,82);
    heart.alpha=0;heart.transform=CGAffineTransformMakeScale(.48,.48);
    heart.userInteractionEnabled=NO;
    [self.view addSubview:heart];
    [UIView animateWithDuration:.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        heart.alpha=1;heart.transform=CGAffineTransformMakeScale(1.12,1.12);
    } completion:^(BOOL done){
        [UIView animateWithDuration:.24 delay:.06 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            heart.alpha=0;heart.transform=CGAffineTransformMakeTranslation(0,-23);
        } completion:^(BOOL finished){[heart removeFromSuperview];}];
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
    AVURLAsset *asset=[self playbackAsset:url];
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

- (void)refreshTabBar {
    NSInteger selected=self.searchMode?1:(self.favoritesOnly?2:((self.onlineMode||self.demoMode)&&!self.historyOnly?0:3));
    if(selected==self.paintedTab)return;
    self.paintedTab=selected;
    NSArray *symbols=@[@"home",@"search",@"heart",@"user"];
    for(NSInteger i=0;i<self.tabButtons.count;i++){
        UIButton *button=self.tabButtons[i];
        BOOL active=i==selected;
        UIColor *color=active?[UIColor whiteColor]:[UIColor colorWithWhite:.61 alpha:1];
        DLStyleIcon(button,symbols[i],23,color);
        UILabel *label=self.tabLabels[i];
        label.textColor=color;
        label.font=active?[UIFont boldSystemFontOfSize:10]:[UIFont systemFontOfSize:10];
    }
}
- (void)openSearch {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"搜索我的视频"
        message:@"仅搜索已经导入的视频和公开样片；不提供抖音平台全站搜索。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){
        field.placeholder=@"搜索标题或文件名";
        field.text=self.searchQuery?:@"";
        field.clearButtonMode=UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"搜索" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *query=[DLText(((UITextField *)alert.textFields.firstObject).text) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if(!query.length){[self openSearch];return;}
        self.searchQuery=query;
        NSMutableArray *result=[NSMutableArray array];
        NSMutableSet *known=[NSMutableSet set];
        NSMutableArray *all=[NSMutableArray arrayWithArray:self.videos];
        [all addObjectsFromArray:self.onlineVideos];
        [all addObjectsFromArray:self.demoVideos];
        for(NSDictionary *clip in all){
            NSString *title=DLText(clip[@"title"]);
            NSString *address=DLText(clip[@"url"]);
            if([title rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound &&
               [address rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound)continue;
            if([known containsObject:address])continue;
            [known addObject:address];[result addObject:clip];
        }
        self.searchResults=result;
        self.searchMode=YES;self.onlineMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;self.index=0;
        [self reloadCurrent];[self refreshTabBar];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tabPressed:(UIButton *)button {
    NSInteger tab=button.tag-200;
    if(tab==0){
        self.demoMode=NO;self.onlineMode=YES;self.searchMode=NO;
        self.favoritesOnly=NO;self.historyOnly=NO;self.index=0;
        [self reloadCurrent];
        if(!self.onlineVideos.count)[self loadOnlineFeed:YES];
    }else if(tab==1){
        [self openSearch];
    }else if(tab==2){
        self.searchMode=NO;self.onlineMode=NO;self.favoritesOnly=YES;self.historyOnly=NO;self.index=0;
        [self reloadCurrent];
    }else if(tab==3){
        [self openMenu];
    }
    [self refreshTabBar];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    if(![recognizer isKindOfClass:[UIPanGestureRecognizer class]])return YES;
    CGPoint point=[touch locationInView:self.view];
    CGFloat h=self.view.bounds.size.height;
    if(point.y<58 || point.y>h-57)return NO;
    UIView *v=touch.view;
    while(v && v!=self.view){
        if([v isKindOfClass:[UIControl class]])return NO;
        v=v.superview;
    }
    return YES;
}
- (void)resetPanVisuals:(BOOL)animated {
    NSArray *targets=@[self.titleText,self.subtitleText,self.countText,self.rightRail];
    void (^reset)(void)=^{
        for(UIView *v in targets){v.transform=CGAffineTransformIdentity;v.alpha=1;}
    };
    if(animated && self.animationsEnabled && !UIAccessibilityIsReduceMotionEnabled())
        [UIView animateWithDuration:.16 animations:reset];
    else reset();
}
- (void)moveFeedBy:(NSInteger)delta {
    NSArray *clips=[self visibleVideos];
    if(!clips.count)return;
    NSInteger next=self.index+delta;
    if(next<0 || next>=clips.count){
        if(self.demoMode&&!self.searchMode&&!self.favoritesOnly&&!self.historyOnly){
            next=next<0?(NSInteger)clips.count-1:0;
        }else{
            if(next>=clips.count && self.onlineMode && !self.searchMode && !self.favoritesOnly && !self.historyOnly){
                if(!self.onlineLoading && !self.onlinePaging)[self loadOnlineFeed:NO];
                self.message.text=@"正在加载更多公开视频…";
            }else{
                self.message.text=next<0?@"已经是第一条":@"已经是最后一条";
            }
            [self performSelector:@selector(clearTransientMessage) withObject:nil afterDelay:1.2];
            return;
        }
    }
    [self transitionToIndex:next direction:delta];
}
- (void)verticalPan:(UIPanGestureRecognizer *)gesture {
    if(self.transitioning)return;
    CGPoint translation=[gesture translationInView:self.view];
    CGPoint velocity=[gesture velocityInView:self.view];
    if(gesture.state==UIGestureRecognizerStateBegan){self.panning=YES;return;}
    if(gesture.state==UIGestureRecognizerStateChanged){
        if(fabs(translation.y)<fabs(translation.x))return;
        if(self.animationsEnabled&&!UIAccessibilityIsReduceMotionEnabled()){
            CGFloat offset=MAX(-18,MIN(18,translation.y*.16));
            CGFloat opacity=MAX(.62,1-fabs(translation.y)/420);
            for(UIView *v in @[self.titleText,self.subtitleText,self.countText,self.rightRail]){
                v.transform=CGAffineTransformMakeTranslation(0,offset);
                v.alpha=opacity;
            }
        }
    }else if(gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled||gesture.state==UIGestureRecognizerStateFailed){
        self.panning=NO;
        BOOL change=fabs(translation.y)>46 || (fabs(velocity.y)>470 && fabs(translation.y)>16);
        NSInteger delta=(translation.y<0||velocity.y<-470)?1:-1;
        [self resetPanVisuals:!change];
        if(change)[self moveFeedBy:delta];
    }
}
- (void)storeLibrary {
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    [d setObject:self.videos forKey:@"dl_library_v1"];
    [d setObject:self.favorites forKey:@"dl_favorites_v1"];
    [d setObject:self.history forKey:@"dl_history_v1"];
}
- (void)saveCurrentPosition {
    NSString *key=self.playingURL;
    if(!self.item||!key.length)return;
    NSTimeInterval time=CMTimeGetSeconds(self.player.currentTime);
    NSTimeInterval duration=CMTimeGetSeconds(self.item.duration);
    if(!isfinite(time)||time<1)return;
    if(isfinite(duration)&&duration>0&&time>=duration-3)[self.positions removeObjectForKey:key];
    else self.positions[key]=@(time);
    if(self.positions.count>100){
        NSString *oldKey=self.positions.allKeys.firstObject;
        if(oldKey)[self.positions removeObjectForKey:oldKey];
    }
    [[NSUserDefaults standardUserDefaults] setObject:self.positions forKey:@"dl_positions_v1"];
}
- (void)stopCurrent {
    [self saveCurrentPosition];
    [self.player pause];
    if(self.observing && self.item)[self.item removeObserver:self forKeyPath:@"status" context:NULL];
    self.observing=NO;
    if(self.item){
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.item];
    }
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.item=nil;self.playingURL=nil;self.holdingSpeed=NO;
    [self setLoading:NO];
}
- (AVURLAsset *)playbackAsset:(NSURL *)url {
 NSMutableDictionary *options=[@{AVURLAssetPreferPreciseDurationAndTimingKey:@NO} mutableCopy];
 NSArray *cookies=[NSHTTPCookieStorage.sharedHTTPCookieStorage cookiesForURL:url];
 if(cookies.count)options[AVURLAssetHTTPCookiesKey]=cookies;
 return [AVURLAsset URLAssetWithURL:url options:options];
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
    self.lastPlayingIcon=YES;
    DLStyleIcon(self.playButton,@"play",42,[UIColor whiteColor]);
    self.progress.progress=0;
    self.playButton.hidden=YES;
    self.message.text=@"";
    self.titleText.text=@"";
    self.subtitleText.text=@"";
    self.countText.text=@"";
    self.likeButton.hidden=!visible.count;
    self.rightRail.hidden=!visible.count;
    self.topText.text=self.searchMode?@"本地搜索":(self.favoritesOnly?@"我的收藏":(self.historyOnly?@"观看历史":(self.onlineMode?@"抖音 · 纯手机":(self.demoMode?@"视频样片 · 测试":@"我的视频"))));
    [self refreshTabBar];
    if(!visible.count){
        if(self.onlineMode){
            self.message.text=self.onlineLoading?@"正在连接视频来源…":
                (self.onlineError.length?self.onlineError:@"暂无联网视频，可打开左上角菜单刷新");
            if(self.onlineLoading)[self.loadingIndicator startAnimating];else[self.loadingIndicator stopAnimating];
        }else{
            self.message.text=self.searchMode?@"没有符合条件的视频\n点底部搜索可以修改关键词":
                (self.favoritesOnly?@"还没有收藏视频\n双击视频即可添加收藏":
                (self.historyOnly?@"暂无观看历史":@"暂无视频\n右上角＋导入视频"));
        }
        return;
    }
    NSDictionary *clip=visible[self.index];
    NSString *address=DLText(clip[@"url"]);
    self.playingURL=address;
    self.titleText.text=DLText(clip[@"title"]);
    NSString *kind=[clip[@"source"] isEqualToString:@"douyin-account"]?@"抖音内容 · 本机连接":([clip[@"source"] isEqualToString:@"douyin-bridge"]?@"DouyinBridge · 云端公开视频":([clip[@"source"] isEqualToString:@"peertube"]?@"PeerTube 公开网络视频 · 非抖音":([clip[@"source"] isEqualToString:@"demo"]?@"公开视频样片 · 非抖音":([clip[@"source"] isEqualToString:@"public-share"]?@"抖音公开分享":([clip[@"source"] isEqualToString:@"local"]?@"本机视频":@"手动添加")))));
    self.subtitleText.text=[NSString stringWithFormat:@"%@ · 向上滑动播放下一条",kind];
    self.countText.text=[NSString stringWithFormat:@"%ld / %ld",(long)(self.index+1),(long)visible.count];
    BOOL liked=[self.favorites containsObject:address];
    DLStyleIcon(self.likeButton,@"heart",30,liked?[UIColor colorWithRed:1 green:.34 blue:.48 alpha:1]:[UIColor whiteColor]);
    NSURL *url=[NSURL URLWithString:address];
    if(!url){
        self.message.text=@"视频链接无效";
        self.playButton.hidden=NO;
        return;
    }
    [self setLoading:YES];
    self.message.text=@"正在加载视频…";
    self.item=[AVPlayerItem playerItemWithAsset:prefetched?:[self playbackAsset:url]];
    [self.item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:NULL];
    self.observing=YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.item];
    [self.player replaceCurrentItemWithPlayerItem:self.item];
    self.player.muted=self.muted;
    if(self.onlineMode && self.index+5>=self.onlineVideos.count && !self.onlineLoading && !self.onlinePaging)
        [self loadOnlineFeed:NO];
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
            NSTimeInterval previous=[self.positions[self.playingURL] doubleValue];
            NSTimeInterval duration=CMTimeGetSeconds(item.duration);
            if(isfinite(duration)&&duration>0 && previous>4 && previous<duration-6)
                [self.player seekToTime:CMTimeMakeWithSeconds(previous,600)];
            if(!self.presentedViewController && UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[self.player play];
            [self prepareNextAsset];
            self.playButton.hidden=YES;
            NSArray *shown=[self visibleVideos];
            if(!shown.count || self.index>=shown.count)return;
            NSDictionary *clip=shown[self.index];
            NSString *key=DLText(clip[@"url"]);
            if([DLText(clip[@"source"]) isEqualToString:@"peertube"]){
                BOOL stored=NO;
                for(NSDictionary *existing in self.videos)
                    if([DLText(existing[@"url"]) isEqualToString:key]){stored=YES;break;}
                if(!stored)[self.videos insertObject:clip atIndex:0];
                if(self.videos.count>140)[self.videos removeLastObject];
            }
            [self.history removeObject:key];[self.history insertObject:key atIndex:0];
            if(self.history.count>100)[self.history removeLastObject];
            [self storeLibrary];
        }else if(item.status==AVPlayerItemStatusFailed){
            [self setLoading:NO];
            NSArray *shown=[self visibleVideos];
            NSDictionary *clip=(self.index>=0&&self.index<(NSInteger)shown.count)?shown[self.index]:nil;
            NSString *origin=DLText(clip[@"originURL"]);
            if(!self.batchInProgress && [clip[@"source"] isEqualToString:@"public-share"] &&
               origin.length && ![self.refreshedShareOrigins containsObject:origin]){
                [self.refreshedShareOrigins addObject:origin];
                self.message.text=@"视频地址可能已过期，正在从手机重新获取…";
                [self inspectPublicShare:[NSURL URLWithString:origin]];
                return;
            }
            self.message.text=self.onlineMode?@"这个公开视频源暂时无法在 iPhone 4S 播放。\n上滑切换下一条，或从菜单切换来源":@"无法播放该视频\n可能是链接失效、编码不兼容或需要平台授权";
            self.playButton.hidden=NO;
        }
    });
}
- (void)videoEnded:(NSNotification *)notification {
    NSArray *clips=[self visibleVideos];
    if(self.playingURL.length){
        [self.positions removeObjectForKey:self.playingURL];
        [[NSUserDefaults standardUserDefaults] setObject:self.positions forKey:@"dl_positions_v1"];
    }
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
    if(playing!=self.lastPlayingIcon){
        DLStyleIcon(self.playButton,playing?@"pause":@"play",42,[UIColor whiteColor]);
        self.lastPlayingIcon=playing;
    }
    if(playing && self.message.text.length)self.message.text=@"";
    Float64 t=CMTimeGetSeconds(self.player.currentTime);
    Float64 d=CMTimeGetSeconds(self.item.duration);
    if(isfinite(t)&&isfinite(d)&&d>0)self.progress.progress=(float)MIN(1,MAX(0,t/d));
    NSTimeInterval now=[[NSDate date] timeIntervalSince1970];
    if(playing && now-self.lastPositionSave>8){
        self.lastPositionSave=now;
        [self saveCurrentPosition];
    }
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
    NSArray *clips=[self visibleVideos];if(!clips.count || self.index>=clips.count)return;
    NSDictionary *clip=clips[self.index];
    NSString *key=DLText(clip[@"url"]);
    if([DLText(clip[@"source"]) isEqualToString:@"peertube"]){
        BOOL exists=NO;
        for(NSDictionary *item in self.videos)
            if([DLText(item[@"url"]) isEqualToString:key]){exists=YES;break;}
        if(!exists)[self.videos insertObject:clip atIndex:0];
    }
    if([self.favorites containsObject:key])[self.favorites removeObject:key];
    else[self.favorites addObject:key];
    [self storeLibrary];
    if(self.favoritesOnly && ![self.favorites containsObject:key]){
        self.index=MIN(self.index,MAX(0,(NSInteger)[self visibleVideos].count-1));
        [self reloadCurrent];
    }else [self reloadMetadata];
    [self pulseView:self.likeButton];
}
- (void)reloadMetadata {
    NSArray *clips=[self visibleVideos];if(!clips.count){[self reloadCurrent];return;}
    NSString *key=DLText(clips[self.index][@"url"]);
    BOOL liked=[self.favorites containsObject:key];
    DLStyleIcon(self.likeButton,@"heart",30,liked?[UIColor colorWithRed:1 green:.34 blue:.48 alpha:1]:[UIColor whiteColor]);
}
- (void)toggleMute {
    self.muted=!self.muted;self.player.muted=self.muted;
    DLStyleIcon(self.muteButton,self.muted?@"muted":@"sound",26,[UIColor whiteColor]);
    [self pulseView:self.muteButton];
}
- (void)shareCurrent {
    NSArray *clips=[self visibleVideos];if(!clips.count||self.index>=clips.count)return;
    NSDictionary *clip=clips[self.index];
    NSString *link=DLText(clip[@"originURL"]);
    if(!link.length)link=DLText(clip[@"url"]);
    NSURL *url=[NSURL URLWithString:link];
    if(!url){[self alert:@"无法分享" message:@"当前视频链接无效。"];return;}
    UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)copyLink {
    NSArray *clips=[self visibleVideos];if(!clips.count)return;
    NSString *link=DLText(clips[self.index][@"originURL"]);
    if(!link.length)link=DLText(clips[self.index][@"url"]);
    [UIPasteboard generalPasteboard].string=link;
    [self alert:@"已复制" message:@"视频地址已复制到剪贴板。"];
}
- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)addVideo {
    UIAlertController *input=[UIAlertController alertControllerWithTitle:@"添加视频"
      message:@"粘贴一条或多条抖音分享链接，最多连续导入12条。支持包含文案的分享内容，也可粘贴视频直链。"
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
    if(self.batchInProgress){[self alert:@"正在导入" message:@"请等这一批链接处理完成后再添加。"];return;}
    NSArray *links=DLShareURLsInText(text);
    if(links.count>1){
        UIAlertController *prompt=[UIAlertController alertControllerWithTitle:@"连续导入抖音视频"
            message:[NSString stringWithFormat:@"识别到 %lu 条分享链接，将在手机上逐条获取，成功后可上下滑动连续观看。",(unsigned long)links.count]
            preferredStyle:UIAlertControllerStyleAlert];
        [prompt addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [prompt addAction:[UIAlertAction actionWithTitle:@"开始导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            [self startShareBatch:links];
        }]];
        [self presentViewController:prompt animated:YES completion:nil];
        return;
    }
    if(links.count==1){[self inspectPublicShare:links[0]];return;}
    NSString *value=DLFindURL(text);
    NSURL *url=value.length?[NSURL URLWithString:value]:nil;
    if(!url||!([url.scheme isEqualToString:@"https"]||[url.scheme isEqualToString:@"http"])){
        [self alert:@"链接无效" message:@"请粘贴抖音公开分享链接或可播放的视频直链。"];
        return;
    }
    if(DLDouyinHost(url.host)){[self inspectPublicShare:url];return;}
    [self addPlayableURL:value name:url.lastPathComponent?:@"我的视频" source:@"link"];
}
- (void)startShareBatch:(NSArray *)links {
    if(self.batchInProgress||!links.count)return;
    self.batchInProgress=YES;
    self.batchImported=0;self.batchFailed=0;self.batchTotal=links.count;
    self.pendingShareURLs=[links mutableCopy];
    [self processNextShareBatch];
}
- (void)processNextShareBatch {
    if(!self.batchInProgress)return;
    if(!self.pendingShareURLs.count){
        NSUInteger imported=self.batchImported,failed=self.batchFailed;
        self.batchInProgress=NO;
        self.pendingShareURLs=nil;
        self.message.text=@"";
        if(imported>0){
            self.subtitleText.text=[NSString stringWithFormat:@"已导入 %lu 条%@ · 上滑继续观看",
                (unsigned long)imported,failed?[NSString stringWithFormat:@"，%lu 条失败",(unsigned long)failed]:@""];
            [self prepareNextAsset];
        }else [self alert:@"这一批链接暂时无法播放"
                message:@"已尝试全部官方公开链接，但当前网络没有取得有效视频。请换其他公开链接重试。"];
        return;
    }
    NSURL *next=self.pendingShareURLs[0];
    [self.pendingShareURLs removeObjectAtIndex:0];
    self.message.text=[NSString stringWithFormat:@"正在导入第 %lu / %lu 条…",
        (unsigned long)(self.batchImported+self.batchFailed+1),(unsigned long)self.batchTotal];
    [self inspectPublicShare:next];
}
- (void)acceptImportedVideo:(NSString *)address title:(NSString *)title original:(NSURL *)original {
    NSString *origin=original.absoluteString?:@"";
    NSString *videoID=DLShareVideoID(original)?:@"";
    NSDictionary *entry=@{@"url":address,@"title":title.length?title:@"抖音公开视频",
        @"source":@"public-share",@"originURL":origin,@"id":videoID};
    NSInteger existing=-1;
    for(NSUInteger i=0;i<self.videos.count;i++){
        NSDictionary *old=self.videos[i];
        BOOL sameURL=[DLText(old[@"url"]) isEqualToString:address];
        BOOL sameOrigin=origin.length && [DLText(old[@"originURL"]) isEqualToString:origin];
        BOOL sameID=videoID.length && [DLText(old[@"id"]) isEqualToString:videoID];
        if(sameURL||sameOrigin||sameID){existing=(NSInteger)i;break;}
    }
    if(self.batchInProgress){
        if(existing>=0){
            NSMutableDictionary *updated=[self.videos[existing] mutableCopy];
            [updated addEntriesFromDictionary:entry];
            self.videos[existing]=updated;
        }else{
            [self.videos addObject:entry];
            existing=(NSInteger)self.videos.count-1;
        }
        while(self.videos.count>240){
            [self.videos removeObjectAtIndex:0];
            if(existing>0)existing--;
            if(self.index>0)self.index--;
        }
        [self storeLibrary];
        if(self.batchImported==0){
            self.onlineMode=NO;self.demoMode=NO;self.searchMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;
            self.index=existing;
            [self reloadCurrent];
        }else if(!self.onlineMode && !self.demoMode && !self.searchMode && !self.favoritesOnly && !self.historyOnly)
            [self reloadMetadata];
        self.batchImported++;
        [self processNextShareBatch];
        return;
    }
    self.onlineMode=NO;self.demoMode=NO;self.searchMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;
    if(existing>=0){
        NSMutableDictionary *updated=[self.videos[existing] mutableCopy];
        [updated addEntriesFromDictionary:entry];
        self.videos[existing]=updated;
        self.index=existing;
    }else{
        [self.videos insertObject:entry atIndex:0];
        self.index=0;
        if(self.videos.count>240)[self.videos removeLastObject];
    }
    [self storeLibrary];
    [self reloadCurrent];
}
- (void)failImportedVideo:(NSString *)detail {
    if(self.batchInProgress){
        self.batchFailed++;
        [self processNextShareBatch];
        return;
    }
    [self alert:@"手机直接获取失败"
        message:[NSString stringWithFormat:@"%@\n可能是视频需要验证、网络受限或视频已经失效。可以换其他公开视频重试。",detail?:@"公开页面没有返回视频数据。"]];
}
- (void)inspectPublicShare:(NSURL *)url {
    if(!DLDouyinHost(url.host)){
        [self alert:@"仅支持抖音链接" message:@"请粘贴抖音官方分享的公开视频链接。"];
        return;
    }
    if(!self.batchInProgress)self.message.text=@"手机正在读取公开视频…";
    NSString *known=DLShareVideoID(url);
    if(known.length){
        [self requestMobileVideoID:known original:url endpointIndex:0];
    }else{
        // Resolve official v.douyin.com short URLs first. Never guess a video ID.
        [self requestPublicShare:url original:url stage:0 videoID:nil];
    }
}
- (void)requestMobileVideoID:(NSString *)videoID original:(NSURL *)original endpointIndex:(NSInteger)index {
    NSArray *servers=@[@"https://api5-normal-c-hl.amemv.com/aweme/v1/feed/",
                       @"https://aweme.snssdk.com/aweme/v1/feed/"];
    if(index>=servers.count){
        [self requestPublicShare:original original:original stage:0 videoID:videoID];
        return;
    }
    NSString *link=[NSString stringWithFormat:@"%@?aweme_id=%@&aid=1128",servers[index],videoID];
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:link]
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:9];
    // This is an official mobile API read of the supplied public video ID.
    [req setValue:@"com.ss.android.ugc.aweme/290101 (Linux; U; Android 10; zh_CN; Pixel 4; Build/QQ3A.200805.001)" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        id decoded=(!error && data.length>0 && data.length<3000000)?
            [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
        NSDictionary *json=[decoded isKindOfClass:NSDictionary.class]?decoded:@{};
        NSArray *items=[json[@"aweme_list"] isKindOfClass:NSArray.class]?json[@"aweme_list"]:@[];
        NSDictionary *matched=nil;
        for(id value in items){
            if(![value isKindOfClass:NSDictionary.class])continue;
            NSString *identifier=DLText(value[@"aweme_id"]);
            if(!identifier.length)identifier=DLText(value[@"id"]);
            if([identifier isEqualToString:videoID]){matched=value;break;}
        }
        NSString *video=DLPublicPlaybackURL(matched);
        NSString *caption=DLText(matched[@"desc"]);
        if(caption.length>70)caption=[[caption substringToIndex:70] stringByAppendingString:@"…"];
        dispatch_async(dispatch_get_main_queue(),^{
            if(video.length){
                self.message.text=@"";
                [self acceptImportedVideo:video title:caption.length?caption:@"抖音公开视频" original:original];
                return;
            }
            if(index+1<servers.count)self.message.text=@"手机正在切换备用视频接口…";
            else self.message.text=@"手机正在读取官方分享页…";
            [self requestMobileVideoID:videoID original:original endpointIndex:index+1];
        });
    }] resume];
}
- (void)requestPublicShare:(NSURL *)url original:(NSURL *)original
                     stage:(NSInteger)stage videoID:(NSString *)knownID {
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:16];
    [req setValue:@"text/html,application/xhtml+xml" forHTTPHeaderField:@"Accept"];
    [req setValue:DLModernMobileAgent() forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"https://www.douyin.com/" forHTTPHeaderField:@"Referer"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSString *html=nil;
        if(!error && data.length>0 && data.length<2500000)
            html=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
        NSDictionary *clip=DLVideoDetails(html);
        NSString *video=DLText(clip[@"url"]);
        NSString *discovered=DLShareVideoID(response.URL);
        NSString *identifier=knownID.length?knownID:(discovered.length?discovered:DLShareVideoID(original));
        NSHTTPURLResponse *http=[response isKindOfClass:NSHTTPURLResponse.class]?(NSHTTPURLResponse *)response:nil;
        dispatch_async(dispatch_get_main_queue(),^{
            if(video.length){
                self.message.text=@"";
                [self acceptImportedVideo:video title:DLText(clip[@"title"]) original:original];
                return;
            }
            if(stage==0 && !knownID.length && identifier.length){
                [self requestMobileVideoID:identifier original:original endpointIndex:0];
                return;
            }
            if(identifier.length && stage<2){
                NSString *shareURL=stage==0?
                    [NSString stringWithFormat:@"https://www.douyin.com/share/video/%@/",identifier]:
                    [NSString stringWithFormat:@"https://www.iesdouyin.com/share/video/%@/",identifier];
                self.message.text=stage==0?@"正在读取备用分享页…":@"正在尝试另一条分享页路径…";
                [self requestPublicShare:[NSURL URLWithString:shareURL]
                    original:original stage:stage+1 videoID:identifier];
                return;
            }
            self.message.text=@"";
            NSString *reason=error.localizedDescription?:@"";
            if(!reason.length)reason=[NSString stringWithFormat:@"官方页面未提供可播放视频（网页状态 %ld）。",(long)http.statusCode];
            [self failImportedVideo:reason];
        });
    }] resume];
}
- (void)resolveShareWithBridge:(NSURL *)original reason:(NSString *)reason {
    NSString *base=[[NSUserDefaults standardUserDefaults] stringForKey:@"dl_feed_endpoint_v1"]?:@"";
    NSString *key=[[NSUserDefaults standardUserDefaults] stringForKey:@"dl_bridge_key_v1"]?:@"";
    NSURLComponents *parts=[NSURLComponents componentsWithString:base];
    if(![parts.scheme.lowercaseString isEqualToString:@"https"] || ![parts.path hasSuffix:@"/api/feed"] || !key.length){
        self.message.text=@"";
        [self alert:@"分享页暂时无法解析"
            message:[NSString stringWithFormat:@"%@\n可连接 DouyinBridge 云端 Chrome 继续尝试。",reason?:@"没有可用视频地址。"]];
        return;
    }
    parts.path=[[parts.path substringToIndex:parts.path.length-4] stringByAppendingString:@"resolve"];
    parts.query=nil;parts.fragment=nil;
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:parts.URL
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:24];
    req.HTTPMethod=@"POST";
    [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"url":original.absoluteString?:@""}
        options:0 error:NULL];
    self.message.text=@"正在通过 DouyinBridge 读取公开视频…";
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        id result=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
        NSDictionary *json=[result isKindOfClass:NSDictionary.class]?result:@{};
        NSString *media=DLText(json[@"url"]);
        NSURL *candidate=[NSURL URLWithString:media];
        dispatch_async(dispatch_get_main_queue(),^{
            self.message.text=@"";
            if([candidate.scheme.lowercaseString isEqualToString:@"https"]&&candidate.host.length){
                [self addPlayableURL:media name:DLText(json[@"title"]) source:@"public-share"];
            }else{
                NSString *detail=DLText(json[@"detail"]);
                [self alert:@"抖音视频暂不可用" message:detail.length?detail:(error.localizedDescription?:reason?:@"云端未取得公开视频地址")];
            }
        });
    }] resume];
}
- (void)addPlayableURL:(NSString *)address name:(NSString *)name source:(NSString *)source {
    if(!address.length)return;
    for(NSDictionary *item in self.videos){
        if([DLText(item[@"url"]) isEqualToString:address]){
            self.searchMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;
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
    self.searchMode=NO;self.onlineMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;self.demoMode=NO;self.index=0;
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
    if(found.count){self.demoMode=NO;self.onlineMode=NO;self.searchMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;self.index=0;}
    [self storeLibrary];
    [self alert:@"本地视频扫描完成" message:[NSString stringWithFormat:@"新增 %ld 个视频。\n扫描路径：\n/var/mobile/Documents/DouyinLite\n/var/mobile/Documents/PocketDrop",(long)count]];
    [self reloadCurrent];
}
- (void)openAccount {
 [self.player pause];
 [self presentViewController:[DLLoginController new] animated:YES completion:nil];
}
- (void)accountChanged {
 self.accountReloadPending=YES;self.onlineRequestID++;self.onlineLoading=NO;self.onlinePaging=NO;
 [self.onlineVideos removeAllObjects];self.onlineError=nil;[self stopCurrent];
}
- (void)viewDidAppear:(BOOL)animated {
 [super viewDidAppear:animated];
 if(self.accountReloadPending){
  self.accountReloadPending=NO;
  [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"dl_use_peertube_v1"];
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"dl_feed_endpoint_v1"];
  self.onlineMode=YES;self.demoMode=NO;self.searchMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;[self loadOnlineFeed:YES];
 }
}
- (void)openSurfDouyin {
    // Surf 0.17.0 registers surf-https and opens the URL with modern
    // Chromium on the paired Windows/desktop host, even on iOS 8.
    NSURL *surf=[NSURL URLWithString:@"surf-https://www.douyin.com/"];
    if([[UIApplication sharedApplication] canOpenURL:surf]){
        [self.player pause];
        [[UIApplication sharedApplication] openURL:surf];
        return;
    }
    [self alert:@"需要安装 Surf"
        message:@"请先安装整合包中的 Surf iPhone 4S 版，在 Windows 电脑运行 Surf 并完成一次配对。配对后返回 DouyinLite，点击「Surf 模式 · 刷抖音」。"];
}
- (void)openDouyinBrowser {
    [self.player pause];
    DLBrowserController *browser=[[DLBrowserController alloc] initWithURL:[NSURL URLWithString:@"https://www.douyin.com/"]];
    [self presentViewController:browser animated:YES completion:nil];
}
- (void)openMenu {
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"DouyinLite · 视频来源"
        message:@"本机直接连接抖音。可以粘贴公开视频分享链接；账号推荐是否可用取决于登录与平台接口。" preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"纯手机 · 粘贴抖音视频链接" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self addVideo];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"从剪贴板连续导入（最多12条）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        [self importText:[UIPasteboard generalPasteboard].string?:@""];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"重新获取当前视频地址" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSArray *shown=[self visibleVideos];
        NSDictionary *clip=(self.index>=0&&self.index<(NSInteger)shown.count)?shown[self.index]:nil;
        NSString *origin=DLText(clip[@"originURL"]);
        if(!origin.length){[self alert:@"没有原分享链接" message:@"此视频没有保存抖音分享来源。可以重新粘贴分享链接。"];return;}
        [self.refreshedShareOrigins removeObject:origin];
        [self inspectPublicShare:[NSURL URLWithString:origin]];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:(DLAccountSession.shared.hasSession?@"抖音账号 · 检查 / 重新登录":@"抖音账号 · 扫码登录") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self openAccount];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"抖音内容 · 刷新" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
      [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"dl_use_peertube_v1"];
      [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"dl_feed_endpoint_v1"];
      self.onlineMode=YES;self.demoMode=NO;self.searchMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;
      [self loadOnlineFeed:YES];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"公开样片（上下滑动测试）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.demoMode=YES;self.onlineMode=NO;self.searchMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;self.index=0;[self reloadCurrent];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"所有视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.demoMode=NO;self.onlineMode=NO;self.searchMode=NO;self.favoritesOnly=NO;self.historyOnly=NO;self.index=0;[self reloadCurrent];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"我的收藏" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.searchMode=NO;self.onlineMode=NO;self.favoritesOnly=YES;self.historyOnly=NO;self.index=0;[self reloadCurrent];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"观看历史" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.searchMode=NO;self.onlineMode=NO;self.favoritesOnly=NO;self.historyOnly=YES;self.index=0;[self reloadCurrent];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"轻量动画：%@",self.animationsEnabled?@"开":@"关"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.animationsEnabled=!self.animationsEnabled;
        [[NSUserDefaults standardUserDefaults] setBool:self.animationsEnabled forKey:@"dl_animations_enabled_v1"];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"下一条预加载：%@",self.preloadEnabled?@"开":@"关"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.preloadEnabled=!self.preloadEnabled;
        [[NSUserDefaults standardUserDefaults] setBool:self.preloadEnabled forKey:@"dl_preload_enabled_v1"];
        if(self.preloadEnabled)[self prepareNextAsset];
        else {self.nextAsset=nil;self.nextURL=nil;self.preloadSourceURL=nil;}
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"自动下一条：%@",self.autoplayNext?@"开":@"关"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.autoplayNext=!self.autoplayNext;
        [[NSUserDefaults standardUserDefaults] setBool:self.autoplayNext forKey:@"dl_autonext_enabled_v1"];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"导入视频链接" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self addVideo];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"复制当前视频链接" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self copyLink];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"扫描本地视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self scanLocalVideos];}]];
    NSArray *currentClips=[self visibleVideos];
    NSString *source=(currentClips.count && self.index<currentClips.count)?DLText(currentClips[self.index][@"source"]):@"";
    BOOL canRemove=currentClips.count && self.index<currentClips.count && ![source isEqualToString:@"demo"] && ![source isEqualToString:@"peertube"];
    if(canRemove){
        [menu addAction:[UIAlertAction actionWithTitle:@"移除当前视频" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
            NSArray *clips=[self visibleVideos];
            if(!clips.count)return;
            NSString *url=DLText(clips[self.index][@"url"]);
            NSIndexSet *indices=[self.videos indexesOfObjectsPassingTest:^BOOL(NSDictionary *item,NSUInteger idx,BOOL *stop){
                return [url isEqualToString:DLText(item[@"url"])];
            }];
            [self.videos removeObjectsAtIndexes:indices];
            [self.favorites removeObject:url];[self.history removeObject:url];
            [self.positions removeObjectForKey:url];
            [[NSUserDefaults standardUserDefaults] setObject:self.positions forKey:@"dl_positions_v1"];
            self.index=0;[self storeLibrary];[self reloadCurrent];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)viewWillDisappear:(BOOL)animated {
    [self saveCurrentPosition];
    [self.player pause];
    [super viewWillDisappear:animated];
}
- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self.uiTimer invalidate];
    [self stopCurrent];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
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
