#import <Foundation/Foundation.h>
typedef void (^XFProbeCompletion)(NSDictionary *result);
@interface XFModelProbe : NSObject
+ (BOOL)canProbeCategory:(NSString *)category;
+ (NSDictionary *)cachedForAccount:(NSDictionary *)account model:(NSDictionary *)model;
+ (void)probeAccount:(NSDictionary *)account model:(NSDictionary *)model apiKey:(NSString *)key completion:(XFProbeCompletion)completion;
+ (void)clearAccount:(NSString *)accountID;
@end
