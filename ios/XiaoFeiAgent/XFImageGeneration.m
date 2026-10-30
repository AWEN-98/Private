#import "XFImageGeneration.h"

static NSInteger const XFMaxImageBody=16*1024*1024;
static NSInteger const XFMaxEncodedImage=13*1024*1024;
static NSString *XFImageString(id value) {
    return [value isKindOfClass:[NSString class]]?value:nil;
}
static NSDictionary *XFImageDict(id value) {
    return [value isKindOfClass:[NSDictionary class]]?value:nil;
}
static void XFImageComplete(XFImageGenerationCompletion callback,UIImage *image,NSString *message,NSInteger code) {
    if(callback)callback(image,message?:@"",code);
}
@implementation XFImageGeneration
+ (NSString *)errorFromJSON:(id)object {
    NSDictionary *json=XFImageDict(object);
    id raw=json[@"error"];
    NSString *reason=nil;
    if([raw isKindOfClass:[NSDictionary class]]) {
        NSDictionary *error=(NSDictionary *)raw;
        reason=XFImageString(error[@"message"])?:XFImageString(error[@"detail"])?:XFImageString(error[@"code"]);
    } else reason=XFImageString(raw);
    if(!reason)reason=XFImageString(json[@"message"])?:XFImageString(json[@"detail"]);
    if(!reason.length)reason=@"接口未返回可识别的错误信息";
    if(reason.length>240)reason=[[reason substringToIndex:240] stringByAppendingString:@"…"];
    return reason;
}
+ (void)decodeData:(NSData *)bytes context:(NSString *)context
    completion:(XFImageGenerationCompletion)completion {
    if(!bytes.length || bytes.length>XFMaxImageBody) {
        XFImageComplete(completion,nil,@"图片数据为空或超过16MB，已停止以保护旧设备",0);return;
    }
    UIImage *image=[UIImage imageWithData:bytes];
    if(!image) {
        XFImageComplete(completion,nil,[NSString stringWithFormat:@"%@：返回的不是可解码的图片",context?:@"服务端"],0);return;
    }
    XFImageComplete(completion,image,@"图片生成成功",200);
}
+ (void)decodeBase64:(NSString *)text completion:(XFImageGenerationCompletion)completion {
    NSString *encoded=text;
    NSRange marker=[text rangeOfString:@";base64,"];
    if([text hasPrefix:@"data:image/"] && marker.location!=NSNotFound)
        encoded=[text substringFromIndex:NSMaxRange(marker)];
    if(encoded.length>XFMaxEncodedImage) {
        XFImageComplete(completion,nil,@"Base64 图片过大（超过13MB），旧设备内存不足",0);return;
    }
    NSData *bytes=[[NSData alloc] initWithBase64EncodedString:encoded options:NSDataBase64DecodingIgnoreUnknownCharacters];
    [self decodeData:bytes context:@"Base64" completion:completion];
}
+ (void)fetchImageURL:(NSString *)urlString completion:(XFImageGenerationCompletion)completion {
    NSURL *url=[NSURL URLWithString:urlString];
    if(![[url.scheme lowercaseString] isEqualToString:@"https"] || !url.host.length ||
       urlString.length>8192 || url.user.length || url.password.length){
        XFImageComplete(completion,nil,@"图像 URL 无效或不是 HTTPS",0);return;
    }
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url
      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:65];
    // Result URLs are public/signed. Never forward the API Bearer token to a different host.
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
      completionHandler:^(NSURLResponse *response,NSData *data,NSError *error) {
        if(error){
            XFImageComplete(completion,nil,
              [NSString stringWithFormat:@"图片地址下载失败 (%ld)，可能是链接过期或旧 iOS TLS 不兼容",(long)error.code],0);
            return;
        }
        NSInteger status=[response isKindOfClass:[NSHTTPURLResponse class]]?
          [(NSHTTPURLResponse *)response statusCode]:0;
        if(status<200 || status>=300){
            XFImageComplete(completion,nil,
              [NSString stringWithFormat:@"下载生成图片失败 HTTP %ld，请重新生成",(long)status],status);
            return;
        }
        NSString *mime=[response.MIMEType lowercaseString];
        if(mime.length && ![mime hasPrefix:@"image/"] &&
           ![mime isEqualToString:@"application/octet-stream"]){
            XFImageComplete(completion,nil,@"图像下载返回了网页或其他内容，不是图片",status);return;
        }
        [self decodeData:data context:@"图片链接" completion:completion];
      }];
}
+ (void)parseResponse:(NSData *)data status:(NSInteger)status chatMode:(BOOL)chat
    completion:(XFImageGenerationCompletion)completion {
    if(!data.length){
        XFImageComplete(completion,nil,@"服务端没有返回数据",status);return;
    }
    if(data.length>XFMaxImageBody){
        XFImageComplete(completion,nil,@"生图响应超过16MB，旧设备已拒绝解析",status);return;
    }
    id object=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if(status<200 || status>=300){
        NSString *reason=[self errorFromJSON:object];
        XFImageComplete(completion,nil,[NSString stringWithFormat:@"HTTP %ld：%@",(long)status,reason],status);
        return;
    }
    NSDictionary *json=XFImageDict(object);
    if(!json){
        XFImageComplete(completion,nil,@"服务器没有返回 JSON，可能是接口地址错误或需要验证",status);return;
    }
    NSString *base64=nil,*imageURL=nil;
    if(chat){
        NSArray *choices=[json[@"choices"] isKindOfClass:[NSArray class]]?json[@"choices"]:@[];
        NSDictionary *first=choices.count?XFImageDict(choices[0]):nil;
        NSDictionary *message=XFImageDict(first[@"message"]);
        NSArray *images=[message[@"images"] isKindOfClass:[NSArray class]]?message[@"images"]:@[];
        if(images.count) {
            NSDictionary *item=XFImageDict(images[0]);
            NSDictionary *info=XFImageDict(item[@"image_url"]);
            NSString *value=XFImageString(info[@"url"]);
            if([value hasPrefix:@"data:image/"])base64=value;
            else if(value.length)imageURL=value;
        }
        if(!base64.length && !imageURL.length){
            // Some compatible providers expose output parts instead of message.images.
            id content=message[@"content"];
            if([content isKindOfClass:[NSArray class]]) {
                for(id block in (NSArray *)content){
                    NSDictionary *part=XFImageDict(block);
                    NSDictionary *info=XFImageDict(part[@"image_url"]);
                    NSString *candidate=XFImageString(info[@"url"])?:XFImageString(part[@"image_url"]);
                    if([candidate hasPrefix:@"data:image/"]){base64=candidate;break;}
                    if([candidate hasPrefix:@"https://"]){imageURL=candidate;break;}
                    base64=XFImageString(part[@"b64_json"]);
                    if(base64.length)break;
                }
            }
        }
    }else{
        NSArray *items=[json[@"data"] isKindOfClass:[NSArray class]]?json[@"data"]:@[];
        NSDictionary *first=items.count?XFImageDict(items[0]):nil;
        base64=XFImageString(first[@"b64_json"]);
        imageURL=XFImageString(first[@"url"]);
        if(!base64.length && !imageURL.length){
            base64=XFImageString(json[@"b64_json"]);
            imageURL=XFImageString(json[@"url"]);
        }
    }
    if(base64.length){[self decodeBase64:base64 completion:completion];return;}
    if(imageURL.length){[self fetchImageURL:imageURL completion:completion];return;}
    NSString *detail=chat?@"当前模型未返回图像（choices[0].message.images 为空）。请确认该模型支持图像输出。":
      @"当前接口返回成功，但 data[0] 中没有 b64_json 或 url。请核对模型的生图 API 协议。";
    XFImageComplete(completion,nil,detail,status);
}
+ (void)generateWithEndpoint:(NSString *)endpoint model:(NSString *)model apiKey:(NSString *)key
    prompt:(NSString *)prompt chatMode:(BOOL)chat completion:(XFImageGenerationCompletion)completion {
    NSURL *url=[NSURL URLWithString:endpoint];
    if(![[url.scheme lowercaseString] isEqualToString:@"https"] || !url.host.length){
        XFImageComplete(completion,nil,@"生图 API 地址无效，请配置 HTTPS 接口",0);return;
    }
    if(!model.length || !key.length){
        XFImageComplete(completion,nil,@"未配置生图模型或 API Key",0);return;
    }
    if(!prompt.length){
        XFImageComplete(completion,nil,@"请输入生图描述",0);return;
    }
    if(prompt.length>5000){
        XFImageComplete(completion,nil,@"提示词超过5000字，请缩短",0);return;
    }
    NSMutableDictionary *body=nil;
    if(chat) {
        body=[@{@"model":model,
            @"messages":@[@{@"role":@"user",@"content":prompt}],
            @"modalities":@[@"text",@"image"],
            @"stream":[NSNumber numberWithBool:NO]} mutableCopy];
    } else {
        body=[@{@"model":model,@"prompt":prompt,@"n":@1,@"size":@"1024x1024"} mutableCopy];
    }
    NSData *encoded=[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    if(!encoded.length){
        XFImageComplete(completion,nil,@"创建生图请求失败",0);return;
    }
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url
      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:125];
    req.HTTPMethod=@"POST";req.HTTPBody=encoded;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
      completionHandler:^(NSURLResponse *response,NSData *data,NSError *error){
        if(error){
            XFImageComplete(completion,nil,
              [NSString stringWithFormat:@"生图请求失败 (%ld)，请检查网络或旧设备 TLS 兼容性",(long)error.code],0);return;
        }
        NSInteger code=[response isKindOfClass:[NSHTTPURLResponse class]]?
          [(NSHTTPURLResponse *)response statusCode]:0;
        [self parseResponse:data status:code chatMode:chat completion:completion];
      }];
}
@end
