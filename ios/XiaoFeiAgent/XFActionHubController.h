#import <UIKit/UIKit.h>
@interface XFActionHubController : UITableViewController
@property(nonatomic,copy) void (^onAction)(NSString *key);
@end
