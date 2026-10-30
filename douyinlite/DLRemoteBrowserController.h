#import <UIKit/UIKit.h>

@interface DLRemoteBrowserController : UIViewController <UIScrollViewDelegate>
- (instancetype)initWithFeedURL:(NSURL *)feedURL apiKey:(NSString *)apiKey;
@end
