#import <UIKit/UIKit.h>
@interface XFHistoryController : UITableViewController
@property(nonatomic,copy) void (^onChoose)(NSString *cid);
@end
