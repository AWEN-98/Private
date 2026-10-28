#import <Foundation/Foundation.h>
@interface XFDiagnostics : NSObject
+ (void)record:(NSString *)event code:(NSInteger)code detail:(NSString *)detail;
+ (NSString *)report;
+ (void)clear;
@end
