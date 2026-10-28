#import <UIKit/UIKit.h>
@interface XFModelsController : UITableViewController
+ (NSDictionary *)activeProfile;
+ (NSString *)secretForProfile:(NSDictionary *)profile;
@end
