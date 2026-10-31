#import "DLAccountSession.h"
#import <Security/Security.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <CommonCrypto/CommonDigest.h>
#import <math.h>

NSString *const DLAccountDidChangeNotification=@"DLAccountDidChange";
NSString *DLWebUserAgent(void){return @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";}
NSString *DLFormEncode(NSString *value){return [value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._"]]?:@"";}
static BOOL DLDomain(NSString *host,NSString *domain){NSString *s=host.lowercaseString;return [s isEqualToString:domain]||[s hasSuffix:[@"." stringByAppendingString:domain]];}
BOOL DLIsOfficialLoginURL(NSURL *url){return [url.scheme.lowercaseString isEqualToString:@"https"]&&!url.user.length&&!url.password.length&&(!url.port||url.port.integerValue==443)&&(DLDomain(url.host,@"douyin.com")||DLDomain(url.host,@"snssdk.com"));}
static NSString *DLString(id x){return [x isKindOfClass:NSString.class]?x:([x respondsToSelector:@selector(stringValue)]?[x stringValue]:@"");}
static NSString *DLMD5(NSString *s){NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[CC_MD5_DIGEST_LENGTH];CC_MD5(d.bytes,(CC_LONG)d.length,hash);NSMutableString *o=[NSMutableString string];for(int i=0;i<CC_MD5_DIGEST_LENGTH;i++)[o appendFormat:@"%02x",hash[i]];return o;}

@interface DLAccountSession ()
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) JSContext *signer;
@property(nonatomic,assign) NSUInteger sessionGeneration;
@property(nonatomic,copy) NSString *fallbackWebID;
@end
@implementation DLAccountSession
+ (instancetype)shared{static DLAccountSession *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
- (NSMutableDictionary *)keyQuery{return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"com.finn.douyinlite.session",(__bridge id)kSecAttrAccount:@"douyin-web"} mutableCopy];}
- (NSString *)fallbackPath{
 NSString *folder=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"DouyinLite"];
 [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:NULL];
 return [folder stringByAppendingPathComponent:@"session.plist"];
}
- (instancetype)init{
 if((self=[super init])){
  NSURLSessionConfiguration *c=[NSURLSessionConfiguration defaultSessionConfiguration];c.HTTPCookieStorage=NSHTTPCookieStorage.sharedHTTPCookieStorage;c.HTTPShouldSetCookies=YES;c.timeoutIntervalForRequest=18;c.timeoutIntervalForResource=25;
  self.session=[NSURLSession sessionWithConfiguration:c delegate:self delegateQueue:NSOperationQueue.mainQueue];
  NSMutableDictionary *q=[self keyQuery];q[(__bridge id)kSecReturnData]=@YES;q[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;CFTypeRef found=NULL;
  OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)q,&found);NSData *saved=status==errSecSuccess?CFBridgingRelease(found):nil;
  if(!saved)saved=[NSData dataWithContentsOfFile:[self fallbackPath]];
  id rows=saved?[NSPropertyListSerialization propertyListWithData:saved options:NSPropertyListImmutable format:NULL error:NULL]:nil;
  if([rows isKindOfClass:NSArray.class])for(id value in rows){if(![value isKindOfClass:NSDictionary.class])continue;NSHTTPCookie *cookie=[NSHTTPCookie cookieWithProperties:value];NSString *domain=[cookie.domain hasPrefix:@"."]?[cookie.domain substringFromIndex:1]:cookie.domain;if(cookie&&DLDomain(domain,@"douyin.com")&&(!cookie.expiresDate||cookie.expiresDate.timeIntervalSinceNow>0))[c.HTTPCookieStorage setCookie:cookie];}
 }
 return self;
}
- (NSString *)cookieValue:(NSString *)name{
 for(NSHTTPCookie *c in [NSHTTPCookieStorage.sharedHTTPCookieStorage cookiesForURL:[NSURL URLWithString:@"https://www.douyin.com/"]])if([c.name isEqualToString:name])return c.value;
 return @"";
}
- (NSString *)webID {
 NSString *value=[self cookieValue:@"webid"];if(!value.length)value=[self cookieValue:@"webid_v2"];
 if(value.length)return value;
 if(!self.fallbackWebID.length){
  unsigned long long bits=(((unsigned long long)arc4random())<<32)|(unsigned long long)arc4random();
  self.fallbackWebID=[NSString stringWithFormat:@"%llu",1000000000000000000ULL+(bits%9000000000000000000ULL)];
 }
 return self.fallbackWebID;
}
- (BOOL)hasSession{return [self cookieValue:@"sessionid"].length||[self cookieValue:@"sessionid_ss"].length||[self cookieValue:@"sid_tt"].length;}
- (BOOL)saveSession{
 NSMutableArray *rows=[NSMutableArray array];for(NSHTTPCookie *c in NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies){
  NSString *domain=[c.domain hasPrefix:@"."]?[c.domain substringFromIndex:1]:c.domain;
  if(!DLDomain(domain,@"douyin.com"))continue;
  NSMutableDictionary *properties=[NSMutableDictionary dictionary];
  for(NSString *key in c.properties){id value=c.properties[key];if([value isKindOfClass:NSString.class]||[value isKindOfClass:NSDate.class]||[value isKindOfClass:NSNumber.class])properties[key]=value;}
  if(properties.count)[rows addObject:properties];
 }
 NSData *data=[NSPropertyListSerialization dataWithPropertyList:rows format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];if(!data)return NO;
 NSMutableDictionary *q=[self keyQuery];NSDictionary *attrs=@{(__bridge id)kSecValueData:data,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
 OSStatus s=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)attrs);
 if(s==errSecItemNotFound){[q addEntriesFromDictionary:attrs];s=SecItemAdd((__bridge CFDictionaryRef)q,NULL);}
 if(s==errSecSuccess){[[NSFileManager defaultManager] removeItemAtPath:[self fallbackPath] error:NULL];return YES;}
 // Older jailbreak keychains can reject writes. Use an owner-only, protected file.
 NSString *path=[self fallbackPath];if(![data writeToFile:path options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:NULL])return NO;
 return [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:path error:NULL];
}
- (void)logout{
 self.sessionGeneration++;[self.session invalidateAndCancel];
 NSURLSessionConfiguration *c=[NSURLSessionConfiguration defaultSessionConfiguration];c.HTTPCookieStorage=NSHTTPCookieStorage.sharedHTTPCookieStorage;c.HTTPShouldSetCookies=YES;c.timeoutIntervalForRequest=18;c.timeoutIntervalForResource=25;
 self.session=[NSURLSession sessionWithConfiguration:c delegate:self delegateQueue:NSOperationQueue.mainQueue];
 SecItemDelete((__bridge CFDictionaryRef)[self keyQuery]);[[NSFileManager defaultManager] removeItemAtPath:[self fallbackPath] error:NULL];
 for(NSHTTPCookie *c in NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies){NSString *domain=[c.domain hasPrefix:@"."]?[c.domain substringFromIndex:1]:c.domain;if(DLDomain(domain,@"douyin.com"))[NSHTTPCookieStorage.sharedHTTPCookieStorage deleteCookie:c];}
 [[NSNotificationCenter defaultCenter] postNotificationName:DLAccountDidChangeNotification object:self];
}
- (NSMutableURLRequest *)webRequest:(NSString *)url{
 NSURL *target=[NSURL URLWithString:url];if(!DLIsOfficialLoginURL(target))return nil;
 NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:target cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:18];
 [r setValue:DLWebUserAgent() forHTTPHeaderField:@"User-Agent"];[r setValue:@"https://www.douyin.com/" forHTTPHeaderField:@"Referer"];
 [r setValue:@"https://www.douyin.com" forHTTPHeaderField:@"Origin"];[r setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
 [r setValue:@"zh-CN,zh;q=0.9,en;q=0.8" forHTTPHeaderField:@"Accept-Language"];
 // Current Douyin web gateway requires the Argus marker and, when present,
 // the same UIFID cookie used by the browser session.
 [r setValue:@"1" forHTTPHeaderField:@"x-tt-argus"];
 NSString *uifid=[self cookieValue:@"UIFID"];if(!uifid.length)uifid=[self cookieValue:@"UIFID_TEMP"];
 if(uifid.length)[r setValue:uifid forHTTPHeaderField:@"uifid"];
 for(NSHTTPCookie *cookie in [NSHTTPCookieStorage.sharedHTTPCookieStorage cookiesForURL:target])if([cookie.name isEqualToString:@"passport_csrf_token"])[r setValue:cookie.value forHTTPHeaderField:@"X-Tt-Passport-Csrf-Token"];
 return r;
}
- (void)prepareLogin:(void (^)(void))completion{
 [[self.session dataTaskWithRequest:[self webRequest:@"https://www.douyin.com/"] completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){dispatch_async(dispatch_get_main_queue(),completion);}] resume];
}
- (NSMutableURLRequest *)feedRequestAtPage:(NSInteger)page reset:(BOOL)reset error:(NSString **)error{
 return [self feedRequestAtPage:page reset:reset seenIDs:@[] error:error];
}
- (NSMutableURLRequest *)feedRequestAtPage:(NSInteger)page reset:(BOOL)reset seenIDs:(NSArray *)seenIDs error:(NSString **)error{
 if(!self.signer){NSString *path=[NSBundle.mainBundle pathForResource:@"DLSigner" ofType:@"js"];NSString *source=path?[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]:nil;if(source.length){self.signer=[JSContext new];[self.signer evaluateScript:source];}}
 if(!self.signer||self.signer.exception){if(error)*error=@"本机签名组件加载失败，请重新安装。";return nil;}
 NSString *query=[NSString stringWithFormat:@"device_platform=webapp&aid=6383&channel=channel_pc_web&module_id=3003101&count=20&refresh_index=%ld&refer_type=10&pull_type=%ld&use_lite_type=2&version_code=190600&version_name=19.6.0&update_version_code=170400&pc_client_type=1&cookie_enabled=true&screen_width=1920&screen_height=1080&browser_language=zh-CN&browser_platform=Win32&browser_name=Chrome&browser_version=131.0.0.0&browser_online=true&engine_name=Blink&engine_version=131.0.0.0&os_name=Windows&os_version=10&cpu_core_num=8&device_memory=8&platform=PC&downlink=10&effective_type=4g&round_trip_time=50",(long)(page+1),(long)(reset?0:2)];
 for(NSArray *entry in @[@[@"webid",[self webID]],@[@"msToken",[self cookieValue:@"msToken"]],@[@"verifyFp",[self cookieValue:@"s_v_web_id"]],@[@"fp",[self cookieValue:@"s_v_web_id"]]])if([entry[1] length])query=[query stringByAppendingFormat:@"&%@=%@",entry[0],DLFormEncode(entry[1])];
 NSMutableArray *ids=[NSMutableArray array];
 for(id entry in seenIDs){
  NSString *value=DLString(entry);
  if(!value.length || [value rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location!=NSNotFound)continue;
  [ids addObject:value];
  if(ids.count>=30)break;
 }
 NSString *joined=[ids componentsJoinedByString:@","];
 NSString *body=[@"encoded_pre_item_ids=" stringByAppendingString:DLFormEncode([[joined dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0])];
 if(joined.length)query=[query stringByAppendingFormat:@"&pre_item_ids=%@",DLFormEncode(joined)];
 NSNumber *now=@(floor(NSDate.date.timeIntervalSince1970*1000));
 self.signer.exception=nil;JSValue *function=self.signer[@"DLSigner"][@"sign"];JSValue *result=[function callWithArguments:@[query,body,DLWebUserAgent(),now]];
 NSString *signature=result.isString?result.toString:nil;if(self.signer.exception||!signature.length){if(error)*error=@"请求签名失败，请检查手机日期时间。";return nil;}
 query=[query stringByAppendingFormat:@"&a_bogus=%@",DLFormEncode(signature)];
 NSString *uifid=@"";for(NSString *name in @[@"UIFID",@"UIFID_TEMP",@"uifid",@"uifid_temp",@"UIFIDTEMP",@"uifidtemp"]){uifid=[self cookieValue:name];if(uifid.length)break;}
 NSString *stamp=[NSString stringWithFormat:@"%.0f",floor(NSDate.date.timeIntervalSince1970)],*websign=nil;
 if(uifid.length){query=[query stringByAppendingFormat:@"&uifid=%@&timestamp=%@",DLFormEncode(uifid),stamp];websign=DLMD5([NSString stringWithFormat:@"%@_%@_A96D855A08C0A9707F8BEF0D9A527E4E_%@",uifid,stamp,query]);query=[query stringByAppendingFormat:@"&x-secsdk-web-signature=%@",websign];}
 NSMutableURLRequest *r=[self webRequest:[@"https://www.douyin.com/aweme/v2/web/module/feed/?" stringByAppendingString:query]];r.HTTPMethod=@"POST";r.HTTPBody=[body dataUsingEncoding:NSUTF8StringEncoding];[r setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
 if(websign){[r setValue:uifid forHTTPHeaderField:@"uifid"];[r setValue:websign forHTTPHeaderField:@"x-secsdk-web-signature"];[r setValue:stamp forHTTPHeaderField:@"x-secsdk-web-expire"];}return r;
}
- (NSMutableURLRequest *)searchRequestForKeyword:(NSString *)keyword offset:(NSInteger)offset error:(NSString **)error {
 return [self searchRequestForKeyword:keyword offset:offset searchID:@"" error:error];
}
- (NSMutableURLRequest *)searchRequestForKeyword:(NSString *)keyword offset:(NSInteger)offset searchID:(NSString *)searchID error:(NSString **)error {
 NSString *word=[keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
 if(!word.length||word.length>48){if(error)*error=@"请输入不超过48个字的关键词";return nil;}
 // The current general-search endpoint does not use a_bogus. It expects the
 // browser's common query fields, search_id continuation token, x-tt-argus
 // header and (when available) the UIFID cookie header.
 NSString *query=[NSString stringWithFormat:
  @"search_channel=aweme_general&enable_history=1&keyword=%@&search_source=tab_search&query_correct_type=1&is_filter_search=0&from_group_id=7378810571505847586&offset=%ld&count=15&need_filter_settings=1&list_type=multi&search_id=%@&device_platform=webapp&aid=6383&channel=channel_pc_web&version_code=190600&version_name=19.6.0&update_version_code=170400&pc_client_type=1&cookie_enabled=true&browser_language=zh-CN&browser_platform=Win32&browser_name=Chrome&browser_version=131.0.0.0&browser_online=true&engine_name=Blink&engine_version=131.0.0.0&os_name=Windows&os_version=10&cpu_core_num=8&device_memory=8&platform=PC&screen_width=2560&screen_height=1440&effective_type=4g&round_trip_time=50",
  DLFormEncode(word),(long)MAX(0,offset),DLFormEncode(searchID?:@"")];
 NSString *webid=[self webID];if(webid.length)query=[query stringByAppendingFormat:@"&webid=%@",DLFormEncode(webid)];
 NSString *token=[self cookieValue:@"msToken"];if(token.length)query=[query stringByAppendingFormat:@"&msToken=%@",DLFormEncode(token)];
 NSString *full=[NSString stringWithFormat:@"https://www.douyin.com/aweme/v1/web/general/search/single/?%@",query];
 NSMutableURLRequest *request=[self webRequest:full];
 NSString *referer=[NSString stringWithFormat:@"https://www.douyin.com/search/%@?aid=f594bbd9-a0e2-4651-9319-ebe3cb6298c1&type=general",DLFormEncode(word)];
 [request setValue:referer forHTTPHeaderField:@"Referer"];
 return request;
}
- (void)requestJSON:(NSURLRequest *)request completion:(void (^)(NSDictionary *,NSString *))completion{
 if(!request){completion(nil,@"请求地址无效");return;}
 NSUInteger generation=self.sessionGeneration;
 [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
  NSHTTPURLResponse *http=[response isKindOfClass:NSHTTPURLResponse.class]?(id)response:nil;
  id raw=data.length&&data.length<4000000?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
  NSDictionary *json=[raw isKindOfClass:NSDictionary.class]?raw:nil;NSString *problem=nil;
  if(error)problem=[NSString stringWithFormat:@"网络连接失败（%ld），请检查网络、系统日期和证书。",(long)error.code];
  else if(http.statusCode<200||http.statusCode>=300)problem=[NSString stringWithFormat:@"服务器返回 HTTP %ld%@",(long)http.statusCode,http.statusCode==403?@"，会话或请求被拒绝。":@""];
  else if(!data.length)problem=@"服务器返回空内容，当前会话未获准访问。";
  else if(!json){
   NSString *mime=response.MIMEType.lowercaseString?:@"unknown";
   NSString *host=request.URL.host.lowercaseString?:@"unknown";
   NSString *route=request.URL.path?:@"/";
   if(route.length>80)route=[route substringToIndex:80];
   NSString *html=data.length?[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0,MIN((NSUInteger)2000,data.length))] encoding:NSUTF8StringEncoding]:@"";
   if(!html)html=@"";
   BOOL challenge=[html rangeOfString:@"captcha" options:NSCaseInsensitiveSearch].location!=NSNotFound ||
      [html rangeOfString:@"验证码"].location!=NSNotFound ||
      [html rangeOfString:@"verify" options:NSCaseInsensitiveSearch].location!=NSNotFound;
   problem=[NSString stringWithFormat:@"接口被返回网页%@（HTTP %ld，%@，%@%@）。请尝试刷新二维码；若多次发生，当前旧设备可能需要现代浏览器登录。",challenge?@" / 验证页":@"",(long)http.statusCode,mime,host,route];
  }
  dispatch_async(dispatch_get_main_queue(),^{if(generation!=self.sessionGeneration){completion(nil,@"账号会话已切换，请重新操作。");return;}completion(problem?nil:json,problem);});
 }] resume];
}
- (void)confirmVerifiedAccount:(void (^)(BOOL,NSString *))completion{
 BOOL saved=[self saveSession];
 [[NSNotificationCenter defaultCenter] postNotificationName:DLAccountDidChangeNotification object:self];
 completion(YES,saved?@"账号已验证，登录会话已保存。":@"账号已验证，但会话保存失败，重开应用后可能需要重新登录。");
}
- (void)verifyAccount:(void (^)(BOOL,NSString *))completion{
 [self requestJSON:[self webRequest:@"https://www.douyin.com/passport/web/account/info/?aid=6383&account_sdk_source=web"] completion:^(NSDictionary *json,NSString *problem){
  NSDictionary *data=[json[@"data"] isKindOfClass:NSDictionary.class]?json[@"data"]:@{};
  NSString *uid=DLString(data[@"user_id"]);if(!uid.length)uid=DLString(data[@"uid"]);if(!uid.length)uid=DLString(data[@"user_id_str"]);
  NSString *code=DLString(json[@"status_code"]);NSString *message=[DLString(json[@"message"]) lowercaseString];
  BOOL apiSuccess=([code isEqualToString:@"0"]||[message isEqualToString:@"success"]);
  if(!problem&&apiSuccess&&uid.length&&![uid isEqualToString:@"0"]){[self confirmVerifiedAccount:completion];return;}
  // Account info may be unsupported on older sessions. Verify against the
  // separate profile endpoint rather than assuming cookies prove login.
  [self requestJSON:[self webRequest:@"https://www.douyin.com/webcast/user/me/?aid=1128"] completion:^(NSDictionary *other,NSString *otherProblem){
    NSDictionary *profile=[other[@"data"] isKindOfClass:NSDictionary.class]?other[@"data"]:@{};
    NSString *identity=DLString(profile[@"user_id"]);
    if(!identity.length)identity=DLString(profile[@"uid"]);
    if(!identity.length)identity=DLString(profile[@"display_id"]);
    NSString *nickname=DLString(profile[@"nickname"]);
    NSString *otherCode=DLString(other[@"status_code"]);
    NSString *otherMessage=[DLString(other[@"message"]) lowercaseString];
    BOOL verified=!otherProblem&&identity.length&&![identity isEqualToString:@"0"]&&nickname.length&&
      ([otherCode isEqualToString:@"0"]||[otherMessage isEqualToString:@"success"]);
    if(verified){[self confirmVerifiedAccount:completion];return;}
    NSString *reason=otherProblem?:problem;
    completion(NO,reason?:([self hasSession]?@"已获取账号会话，但两个账号接口均未确认有效登录。":@"尚未取得有效登录会话，请重新扫码。"));
  }];
 }];
}
- (void)finishLoginAtURL:(NSURL *)url completion:(void (^)(BOOL,NSString *))completion{
 if(!DLIsOfficialLoginURL(url)){completion(NO,@"登录回调地址无效，请刷新二维码重试。");return;}
 NSUInteger generation=self.sessionGeneration;
 [[self.session dataTaskWithRequest:[self webRequest:url.absoluteString] completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){dispatch_async(dispatch_get_main_queue(),^{if(generation!=self.sessionGeneration||error){completion(NO,@"登录回调未完成，请重试。");return;}[self verifyAccount:completion];});}] resume];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler{completionHandler(DLIsOfficialLoginURL(request.URL)?request:nil);}
@end
