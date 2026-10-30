#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString *const DLAccountDidChangeNotification;
FOUNDATION_EXPORT NSString *DLWebUserAgent(void);
FOUNDATION_EXPORT NSString *DLFormEncode(NSString *value);
FOUNDATION_EXPORT BOOL DLIsOfficialLoginURL(NSURL *url);

@interface DLAccountSession : NSObject <NSURLSessionTaskDelegate>
+ (instancetype)shared;
- (BOOL)hasSession;
- (NSString *)cookieValue:(NSString *)name;
- (BOOL)saveSession;
- (void)logout;
- (NSMutableURLRequest *)webRequest:(NSString *)url;
- (void)prepareLogin:(void (^)(void))completion;
- (NSMutableURLRequest *)feedRequestAtPage:(NSInteger)page reset:(BOOL)reset error:(NSString **)error;
- (NSMutableURLRequest *)searchRequestForKeyword:(NSString *)keyword offset:(NSInteger)offset error:(NSString **)error;
- (void)requestJSON:(NSURLRequest *)request completion:(void (^)(NSDictionary *, NSString *))completion;
- (void)finishLoginAtURL:(NSURL *)url completion:(void (^)(BOOL,NSString *))completion;
- (void)verifyAccount:(void (^)(BOOL,NSString *))completion;
@end

@interface DLLoginController : UIViewController
@end
