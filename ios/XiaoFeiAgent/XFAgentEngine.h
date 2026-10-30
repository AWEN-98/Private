#import <UIKit/UIKit.h>
@interface XFAgentEngine : NSObject
@property(nonatomic,copy) void (^onProgress)(NSString *);
@property(nonatomic,copy) void (^onFinished)(NSString *);
@property(nonatomic,copy) void (^onApproval)(NSString *,NSString *,void (^)(BOOL));
@property(nonatomic,assign,readonly) BOOL running;
- (void)start:(NSString *)task context:(NSString *)context profile:(NSDictionary *)profile;
- (void)cancel;
+ (NSString *)taskBoard;
@end
