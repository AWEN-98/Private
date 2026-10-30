#import <UIKit/UIKit.h>
@interface XFJarvisController : UIViewController
@property(nonatomic,copy) void (^onPrimary)(void);
@property(nonatomic,copy) void (^onStop)(void);
@property(nonatomic,copy) void (^onClose)(void);
@property(nonatomic,copy) void (^onAutoSpeak)(BOOL enabled);
@property(nonatomic,copy) void (^onTease)(void);
@property(nonatomic,copy) void (^onContinuousTalk)(BOOL enabled);
@property(nonatomic,copy) void (^onMechanicalVoice)(BOOL enabled);
@property(nonatomic,assign) BOOL autoSpeak;
@property(nonatomic,assign) BOOL continuousTalk;
@property(nonatomic,assign) BOOL mechanicalVoice;
- (void)updateMode:(NSString *)mode description:(NSString *)detail;
- (void)updateMeter:(float)level seconds:(NSInteger)seconds;
- (void)updateSpeechPulse;
- (void)updateSpeechText:(NSString *)spokenText;
@end
