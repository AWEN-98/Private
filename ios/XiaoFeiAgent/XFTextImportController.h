#import <UIKit/UIKit.h>
@interface XFTextImportController : UIViewController
@property(nonatomic,copy) void (^onUseText)(NSString *text);
@end
