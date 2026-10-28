#import <UIKit/UIKit.h>
@interface XFChatView : UIView
- (void)showWelcome;
- (void)showConversation:(NSArray *)messages;
- (void)addMessage:(NSString *)text fromUser:(BOOL)user;
- (void)updateStreaming:(NSString *)text;
- (void)finishStreaming:(NSString *)text;
- (void)showNotice:(NSString *)text;
@end
