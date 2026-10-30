#import <UIKit/UIKit.h>
typedef void (^XFImageGenerationCompletion)(UIImage *image, NSString *message, NSInteger code);
@interface XFImageGeneration : NSObject
+ (void)generateWithEndpoint:(NSString *)endpoint model:(NSString *)model
    apiKey:(NSString *)key prompt:(NSString *)prompt chatMode:(BOOL)chat
    completion:(XFImageGenerationCompletion)completion;
@end
