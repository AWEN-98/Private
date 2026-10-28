#import "XFAppDelegate.h"
#import "XFViewController.h"
@implementation XFAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
 self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
 self.window.rootViewController=[[XFViewController alloc] init];
 [self.window makeKeyAndVisible]; return YES;
}
@end
