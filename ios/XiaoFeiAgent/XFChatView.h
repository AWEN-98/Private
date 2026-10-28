#import <UIKit/UIKit.h>
@interface XFChatView : UIView
@property(nonatomic,copy) void (^onImageTap)(UIImage *image);
- (void)showWelcome;
- (void)showConversation:(NSArray *)messages;
- (void)addMessage:(NSString *)text fromUser:(BOOL)user;
- (void)addImageMessage:(NSString *)text imageName:(NSString *)filename;
- (void)updateStreaming:(NSString *)text;
- (void)finishStreaming:(NSString *)text;
- (void)showNotice:(NSString *)text;
@end
