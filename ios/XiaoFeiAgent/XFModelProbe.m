#import "XFModelProbe.h"

static NSString *const XFProbeCacheKey=@"xf_model_probe_results_v1";
static NSTimeInterval const XFProbeFreshness=48*60*60;

@implementation XFModelProbe

+ (BOOL)canProbeCategory:(NSString *)category {
    return [@[@"文字对话",@"深度推理",@"图片理解"] containsObject:category];
}
+ (NSString *)keyForAccount:(NSDictionary *)account model:(NSDictionary *)model {
    return [NSString stringWithFormat:@"%@|%@",account[@"id"]?:@"",model[@"id"]?:@""];
}
+ (NSDictionary *)cachedForAccount:(NSDictionary *)account model:(NSDictionary *)model {
    NSString *key=[self keyForAccount:account model:model];
    NSDictionary *cache=[[NSUserDefaults standardUserDefaults] dictionaryForKey:XFProbeCacheKey];
    NSDictionary *item=cache[key];
    if(![item isKindOfClass:[NSDictionary class]])return nil;
    NSTimeInterval age=[[NSDate date] timeIntervalSince1970]-[item[@"time"] doubleValue];
    // A status is evidence only for a limited interval, not a permanent ban.
    if(age<0 || age>XFProbeFreshness)return nil;
    return item;
}
+ (void)store:(NSDictionary *)result account:(NSDictionary *)account model:(NSDictionary *)model {
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all=[[d dictionaryForKey:XFProbeCacheKey] mutableCopy]?:[NSMutableDictionary dictionary];
    all[[self keyForAccount:account model:model]]=result;
    if(all.count>450) {
        NSArray *sorted=[all keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
            return [a[@"time"] compare:b[@"time"]];
        }];
        for(NSUInteger i=0;i<sorted.count-400;i++) [all removeObjectForKey:sorted[i]];
    }
    [d setObject:all forKey:XFProbeCacheKey];[d synchronize];
}
+ (void)clearAccount:(NSString *)accountID {
    if(!accountID.length)return;
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    NSMutableDictionary *cache=[[d dictionaryForKey:XFProbeCacheKey] mutableCopy];
    NSString *prefix=[accountID stringByAppendingString:@"|"];
    for(NSString *key in [[cache allKeys] copy])if([key hasPrefix:prefix])[cache removeObjectForKey:key];
    [d setObject:cache forKey:XFProbeCacheKey];[d synchronize];
}
+ (NSString *)safeReason:(NSData *)data {
    id json=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    NSString *reason=nil;
    if([json isKindOfClass:[NSDictionary class]]) {
        id err=json[@"error"];
        if([err isKindOfClass:[NSDictionary class]])reason=err[@"message"]?:err[@"code"];
        else if([err isKindOfClass:[NSString class]])reason=err;
        if(!reason.length)reason=json[@"message"]?:json[@"detail"]?:json[@"msg"];
    }
    if(![reason isKindOfClass:[NSString class]])reason=nil;
    if(!reason.length)reason=@"API 返回请求错误，需检查模型权限或请求格式";
    if(reason.length>130)reason=[reason substringToIndex:130];
    return reason;
}
+ (void)finish:(NSString *)status detail:(NSString *)detail code:(NSInteger)code
     account:(NSDictionary *)account model:(NSDictionary *)model completion:(XFProbeCompletion)completion {
    NSDictionary *result=@{@"status":status?:@"unknown",@"reason":detail?:@"",@"code":@(code),
       @"time":@([[NSDate date] timeIntervalSince1970])};
    [self store:result account:account model:model];
    if(completion)completion(result);
}
+ (void)probeAccount:(NSDictionary *)account model:(NSDictionary *)model apiKey:(NSString *)key completion:(XFProbeCompletion)completion {
    if(![key isKindOfClass:[NSString class]] || !key.length) {
        [self finish:@"unknown" detail:@"API Key 缺失，请在 API 管理中配置密钥"
             code:0 account:account model:model completion:completion];return;
    }
    NSString *base=account[@"base"];
    NSString *url=[base hasSuffix:@"/"]?[base stringByAppendingString:@"chat/completions"]:[base stringByAppendingString:@"/chat/completions"];
    NSString *legacy=account[@"legacy_endpoint"];
    if([legacy isKindOfClass:[NSString class]] && legacy.length && [account[@"models"] count]==1)url=legacy;
    NSURL *endpoint=[NSURL URLWithString:url];
    if(![[endpoint scheme] isEqualToString:@"https"] || ![[endpoint host] length]) {
        [self finish:@"unknown" detail:@"不合法的 HTTPS 接口地址" code:0 account:account model:model completion:completion];return;
    }
    NSString *mid=model[@"id"];
    if(![mid isKindOfClass:[NSString class]] || !mid.length) {
        [self finish:@"unknown" detail:@"模型 ID 为空" code:0 account:account model:model completion:completion];return;
    }
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:endpoint
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:18];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    // Keep the request minimal. We check real inference access, not just GET /models.
    // Do not use provider-specific max_tokens or web_search_options: many APIs reject them.
    NSDictionary *payload=@{@"model":mid,
        @"messages":@[@{@"role":@"user",@"content":@"请只回答：好"}],
        @"stream":@NO};
    request.HTTPBody=[NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:
      ^(NSURLResponse *response,NSData *data,NSError *error) {
        if(error) {
            [self finish:@"unknown" detail:[NSString stringWithFormat:@"网络错误 %ld（暂不判定模型失效）",(long)error.code]
                code:0 account:account model:model completion:completion];return;
        }
        NSInteger http=[response isKindOfClass:[NSHTTPURLResponse class]]?[(NSHTTPURLResponse *)response statusCode]:0;
        if(http>=200 && http<300) {
            id json=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
            NSArray *choices=[json isKindOfClass:[NSDictionary class]]?json[@"choices"]:nil;
            if([choices isKindOfClass:[NSArray class]] && choices.count) {
                NSDictionary *first=[choices[0] isKindOfClass:[NSDictionary class]]?choices[0]:nil;
                if([first[@"message"] isKindOfClass:[NSDictionary class]] || first[@"text"]) {
                    [self finish:@"ok" detail:@"已成功调用聊天接口" code:http account:account model:model completion:completion];
                    return;
                }
            }
            [self finish:@"unknown" detail:@"HTTP 成功，但回复不是兼容的聊天格式" code:http account:account model:model completion:completion];
            return;
        }
        NSString *reason=[self safeReason:data];
        if(key.length) reason=[reason stringByReplacingOccurrencesOfString:key withString:@"[密钥已隐藏]"];
        NSString *lower=[reason lowercaseString];
        BOOL badModel=([lower containsString:@"model_not_found"] ||
          [lower containsString:@"model not found"] ||
          [lower containsString:@"model does not exist"] ||
          [lower containsString:@"unknown model"] ||
          [lower containsString:@"invalid model"] ||
          [lower containsString:@"model not supported"] ||
          [lower containsString:@"模型不存在"] ||
          [lower containsString:@"无此模型"]);
        // Never gray out a model solely because of 429/5xx/TLS/account or product activation.
        // 400/404 may also be a wrong API path; explicit model errors are needed.
        NSString *status=badModel?@"bad":@"unknown";
        [self finish:status detail:[NSString stringWithFormat:@"HTTP %ld：%@",(long)http,reason]
             code:http account:account model:model completion:completion];
      }];
}
@end
