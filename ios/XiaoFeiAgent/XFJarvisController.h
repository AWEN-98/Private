#import <UIKit/UIKit.h>
@interface XFJarvisController : UIViewController
@property(nonatomic,copy) void (^onPrimary)(void);
@property(nonatomic,copy) void (^onStop)(void);
@property(nonatomic,copy) void (^onClose)(void);
@property(nonatomic,copy) void (^onAutoSpeak)(BOOL enabled);
@property(nonatomic,assign) BOOL autoSpeak;
- (void)updateMode:(NSString *)mode description:(NSString *)detail;
- (void)updateMeter:(float)level seconds:(NSInteger)seconds;
@end
