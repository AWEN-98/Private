#import "XFModelProbe.h"

static NSString *const XFProbeCacheKey=@"xf_model_probe_results_v1";
static NSTimeInterval const XFProbeFreshness=24*60*60;

@implementation XFModelProbe

+ (BOOL)canProbeCategory:(NSString *)category {
    return [@[@"文字对话",@"深度推理",@"图片理解"] containsObject:category];
}
+ (NSString *)keyForAccount:(NSDictionary *)account model:(NSDictionary *)model {
    return [NSString stringWithFormat:@"%@|%@",account[@"id"]?:@"",model[@"id"]?:@""];
}
+ (NSDictionary *)cachedForAccount:(NSDictionary *)account model:(NSDictionary *)model {
    NSDictionary *cache=[[NSUserDefaults standardUserDefaults] dictionaryForKey:XFProbeCacheKey];
    NSDictionary *entry=cache[[self keyForAccount:account model:model]];
    if(![entry isKindOfClass:[NSDictionary class]])return nil;
    NSTimeInterval age=[[NSDate date] timeIntervalSince1970]-[entry[@"time"] doubleValue];
    if(age<0 || age>XFProbeFreshness)return nil;
    return entry;
}
+ (void)store:(NSDictionary *)result account:(NSDictionary *)account model:(NSDictionary *)model {
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all=[[defaults dictionaryForKey:XFProbeCacheKey] mutableCopy]?:[NSMutableDictionary dictionary];
    all[[self keyForAccount:account model:model]]=result;
    if(all.count>450) {
        NSArray *ordered=[all keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
            return [a[@"time"] compare:b[@"time"]];
        }];
        for(NSUInteger i=0;i<ordered.count-400;i++)[all removeObjectForKey:ordered[i]];
    }
    [defaults setObject:all forKey:XFProbeCacheKey];
    [defaults synchronize];
}
+ (void)clearAccount:(NSString *)accountID {
    if(!accountID.length)return;
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all=[[defaults dictionaryForKey:XFProbeCacheKey] mutableCopy]?:[NSMutableDictionary dictionary];
    NSString *prefix=[accountID stringByAppendingString:@"|"];
    for(NSString *key in [[all allKeys] copy])if([key hasPrefix:prefix])[all removeObjectForKey:key];
    [defaults setObject:all forKey:XFProbeCacheKey];[defaults synchronize];
}
+ (NSString *)safeReason:(NSData *)data {
    id json=(data.length && data.length<1024*1024)?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    NSString *reason=nil;
    if([json isKindOfClass:[NSDictionary class]]) {
        id error=json[@"error"];
        if([error isKindOfClass:[NSDictionary class]]) {
            id message=error[@"message"]?:error[@"detail"]?:error[@"code"];
            if([message isKindOfClass:[NSString class]])reason=message;
        }else if([error isKindOfClass:[NSString class]])reason=error;
        if(!reason.length){
            id candidate=json[@"message"]?:json[@"detail"]?:json[@"msg"];
            if([candidate isKindOfClass:[NSString class]])reason=candidate;
        }
    }
    if(!reason.length)reason=@"API 返回错误，但没有提供明确的故障原因";
    if(reason.length>220)reason=[reason substringToIndex:220];
    return reason;
}
+ (BOOL)containsOneOf:(NSString *)text patterns:(NSArray *)patterns {
    for(NSString *word in patterns)if([text rangeOfString:word].location!=NSNotFound)return YES;
    return NO;
}
+ (NSString *)statusForHTTP:(NSInteger)http message:(NSString *)reason {
    NSString *msg=[reason.lowercaseString copy]?:@"";
    // Account-level errors are checked first: do not mislabel product-activation
    // or billing failures as a permanently invalid model.
    if([self containsOneOf:msg patterns:@[@"product is not activated",@"not activated",@"product not activated",
       @"service is not activated",@"service not activated",@"model not activated",
       @"服务未开通",@"尚未开通",@"未开通",@"需要开通"]])return @"unactivated";
    if([self containsOneOf:msg patterns:@[@"insufficient balance",@"balance insufficient",
       @"insufficient credit",@"no remaining credit",@"payment required",
       @"out of credit",@"account balance",@"arrears",@"billing limit",
       @"余额不足",@"账户欠费",@"欠费",@"支付额度不足"]])return @"balance";
    if(http==429 || [self containsOneOf:msg patterns:@[@"rate limit",@"rate_limit",
       @"too many requests",@"throttl",@"request limit reached",@"限流",@"请求过于频繁"]])return @"rate";
    if(http==401 || http==403 ||
       [self containsOneOf:msg patterns:@[@"invalid api key",@"invalid_api_key",
           @"unauthorized",@"authentication failed",@"permission denied",
           @"access denied",@"api key expired",@"鉴权失败",@"无权限",@"权限不足"]])return @"auth";
    if([self containsOneOf:msg patterns:@[@"unsupported endpoint",@"unknown endpoint",
        @"does not support chat completions",@"not support chat completions",
        @"not support the chat",@"unsupported request",@"unsupported parameter",
        @"unsupported operation",@"unsupported api",@"unrecognized request argument",
        @"invalid request format",@"not support stream",@"接口不兼容",@"请求格式不支持"]])
        return @"incompatible";
    BOOL missing=[self containsOneOf:msg patterns:@[@"model_not_found",@"model not found",
        @"model does not exist",@"unknown model",@"invalid model",
        @"模型不存在",@"无此模型",@"未找到模型",@"模型未找到"]];
    if((http==400 || http==404) && missing)return @"bad";
    // HTTP 5xx, network, ambiguous 400/404, daily quotas etc remain inconclusive.
    return @"unknown";
}
+ (void)finish:(NSString *)status detail:(NSString *)detail code:(NSInteger)code
    millis:(NSInteger)millis account:(NSDictionary *)account model:(NSDictionary *)model completion:(XFProbeCompletion)completion {
    NSDictionary *result=@{@"status":status?:@"unknown",@"reason":detail?:@"",@"code":@(code),
       @"latency_ms":@(MAX(0,millis)),@"time":@([[NSDate date] timeIntervalSince1970])};
    [self store:result account:account model:model];
    if(completion)completion(result);
}
+ (void)probeAccount:(NSDictionary *)account model:(NSDictionary *)model apiKey:(NSString *)key completion:(XFProbeCompletion)completion {
    CFAbsoluteTime started=CFAbsoluteTimeGetCurrent();
    if(!key.length) {
        [self finish:@"auth" detail:@"未配置 API Key" code:0 millis:0
          account:account model:model completion:completion];return;
    }
    NSString *base=account[@"base"]?:@"";
    NSString *url=[base hasSuffix:@"/"]?[base stringByAppendingString:@"chat/completions"]:[base stringByAppendingString:@"/chat/completions"];
    NSString *legacy=account[@"legacy_endpoint"];
    if([legacy isKindOfClass:[NSString class]] && legacy.length && [account[@"models"] count]==1)url=legacy;
    NSURL *endpoint=[NSURL URLWithString:url];
    if(![[endpoint scheme] isEqualToString:@"https"] || ![endpoint.host length]) {
        [self finish:@"incompatible" detail:@"API 地址不是有效的 HTTPS 聊天接口" code:0 millis:0
          account:account model:model completion:completion];return;
    }
    NSString *mid=model[@"id"];
    if(![mid isKindOfClass:[NSString class]] || !mid.length) {
        [self finish:@"unknown" detail:@"模型 ID 为空" code:0 millis:0
           account:account model:model completion:completion];return;
    }
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:endpoint
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    req.HTTPMethod=@"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    // Intentionally tiny, but a live request may incur provider charges.
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{
        @"model":mid,
        @"messages":@[@{@"role":@"user",@"content":@"请回答：好"}],
        @"stream":[NSNumber numberWithBool:NO]
    } options:0 error:NULL];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
      completionHandler:^(NSURLResponse *response,NSData *data,NSError *error) {
        NSInteger elapsed=MAX(1,(NSInteger)round((CFAbsoluteTimeGetCurrent()-started)*1000));
        if(error){
            [self finish:@"unknown"
                detail:[NSString stringWithFormat:@"连接失败 %ld，可能是 iOS 8 TLS 或网络问题",(long)error.code]
                code:0 millis:elapsed account:account model:model completion:completion];return;
        }
        NSInteger http=[response isKindOfClass:[NSHTTPURLResponse class]]?[(NSHTTPURLResponse *)response statusCode]:0;
        if(http>=200 && http<300) {
            id json=(data.length && data.length<1024*1024)?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
            NSArray *choices=[json isKindOfClass:[NSDictionary class]]?json[@"choices"]:nil;
            if([choices isKindOfClass:[NSArray class]] && choices.count) {
                NSDictionary *first=[choices[0] isKindOfClass:[NSDictionary class]]?choices[0]:nil;
                if([first[@"message"] isKindOfClass:[NSDictionary class]] || [first[@"text"] isKindOfClass:[NSString class]]) {
                    [self finish:@"ok" detail:@"文字推理请求成功（视觉输入未单独验证）" code:http millis:elapsed
                      account:account model:model completion:completion];return;
                }
            }
            [self finish:@"unknown" detail:@"HTTP 成功，但未识别返回格式" code:http millis:elapsed
                account:account model:model completion:completion];return;
        }
        NSString *reason=[self safeReason:data];
        if(key.length)reason=[reason stringByReplacingOccurrencesOfString:key withString:@"[密钥已隐藏]"];
        NSString *status=[self statusForHTTP:http message:reason];
        [self finish:status
           detail:[NSString stringWithFormat:@"HTTP %ld：%@",(long)http,reason]
           code:http millis:elapsed account:account model:model completion:completion];
    }];
}
@end
