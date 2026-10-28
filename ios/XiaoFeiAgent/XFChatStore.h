#import <UIKit/UIKit.h>
@interface XFChatStore : NSObject
+ (NSString *)saveImage:(UIImage *)image;
+ (UIImage *)imageForName:(NSString *)filename;
+ (UIImage *)thumbnailForName:(NSString *)filename;
+ (NSArray *)conversations;
+ (NSDictionary *)conversationForID:(NSString *)cid;
+ (NSString *)createConversation;
+ (void)saveConversationID:(NSString *)cid messages:(NSArray *)messages;
+ (void)renameConversationID:(NSString *)cid title:(NSString *)title;
+ (void)deleteConversationID:(NSString *)cid;
@end
