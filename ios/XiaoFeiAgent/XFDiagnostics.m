#import "XFDiagnostics.h"

static NSString *const XFDiagnosticKey=@"xf_diagnostics_v1";

@implementation XFDiagnostics
+ (void)record:(NSString *)event code:(NSInteger)code detail:(NSString *)detail {
    NSString *label=[event isKindOfClass:[NSString class]]?event:@"事件";
    NSString *note=[detail isKindOfClass:[NSString class]]?detail:@"";
    if(note.length>190)note=[note substringToIndex:190];
    // Callers must pass metadata only, never request/response bodies or API keys.
    NSString *timestamp=[NSDateFormatter localizedStringFromDate:[NSDate date]
      dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle];
    NSString *entry=[NSString stringWithFormat:@"%@ | %@ | %ld | %@",
       timestamp,label,(long)code,note];
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    NSMutableArray *entries=[[defaults arrayForKey:XFDiagnosticKey] mutableCopy]?:[NSMutableArray array];
    [entries addObject:entry];
    if(entries.count>40)[entries removeObjectsInRange:NSMakeRange(0,entries.count-40)];
    [defaults setObject:entries forKey:XFDiagnosticKey];
}
+ (NSString *)report {
    NSArray *entries=[[NSUserDefaults standardUserDefaults] arrayForKey:XFDiagnosticKey]?:@[];
    if(!entries.count)return @"暂时没有诊断事件。";
    return [[entries reverseObjectEnumerator].allObjects componentsJoinedByString:@"\n"];
}
+ (void)clear {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:XFDiagnosticKey];
}
@end
