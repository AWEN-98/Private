#import <UIKit/UIKit.h>
@interface XFModelsController : UITableViewController
+ (NSDictionary *)activeProfile;
+ (NSDictionary *)activeProfileForCapability:(NSString *)capability;
+ (NSString *)secretForProfile:(NSDictionary *)profile;
@end
