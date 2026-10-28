#import <Foundation/Foundation.h>
@interface XFChatStore : NSObject
+ (NSArray *)conversations;
+ (NSDictionary *)conversationForID:(NSString *)cid;
+ (NSString *)createConversation;
+ (void)saveConversationID:(NSString *)cid messages:(NSArray *)messages;
+ (void)renameConversationID:(NSString *)cid title:(NSString *)title;
+ (void)deleteConversationID:(NSString *)cid;
@end
