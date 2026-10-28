#import <UIKit/UIKit.h>
@interface XFPromptToolsController : UITableViewController
@property(nonatomic,copy) void (^onUsePrompt)(NSString *prompt);
@end
