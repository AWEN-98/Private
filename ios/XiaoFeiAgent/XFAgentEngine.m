#import "XFAgentEngine.h"
#import "XFModelsController.h"
#import <math.h>
#import <stdlib.h>

static NSString *XFAText(id value,NSUInteger length) {
    if(![value isKindOfClass:[NSString class]])return @"";
    NSString *s=[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return s.length>length?[s substringToIndex:length]:s;
}
static NSArray *XFAItems(NSString *key) {
    id x=[[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [x isKindOfClass:[NSArray class]]?x:@[];
}
static void XFAStore(NSString *key,NSArray *items) {
    [[NSUserDefaults standardUserDefaults] setObject:items forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
static NSString *XFANow(void) {
    NSDateFormatter *format=[[NSDateFormatter alloc] init];
    format.dateFormat=@"yyyy-MM-dd HH:mm:ss Z";
    return [format stringFromDate:[NSDate date]];
}
static BOOL XFASafe(NSURL *url) {
    NSString *host=[url.host lowercaseString]?:@"";
    if(![[url.scheme lowercaseString] isEqualToString:@"https"] || ![host containsString:@"."] ||
       url.user.length || url.password.length || [host isEqualToString:@"localhost"] ||
       [host hasSuffix:@".local"] || [host hasSuffix:@".internal"] || [host containsString:@":"])return NO;
    NSCharacterSet *numbers=[NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
    return [host stringByTrimmingCharactersInSet:numbers].length>0;
}
static void XFASkip(const char **p) {while(**p==' ' || **p=='\t')++*p;}
static double XFAExpr(const char **p,int depth,BOOL *valid);
static double XFAFactor(const char **p,int depth,BOOL *valid) {
    if(depth>20){*valid=NO;return 0;}
    XFASkip(p);
    if(**p=='-' || **p=='+'){
        char sign=*(*p)++;
        double v=XFAFactor(p,depth+1,valid);
        return sign=='-'?-v:v;
    }
    if(**p=='('){
        ++*p;double v=XFAExpr(p,depth+1,valid);
        XFASkip(p);if(**p!=')')*valid=NO;else ++*p;return v;
    }
    char *end=NULL;
    double value=strtod(*p,&end);
    if(end==*p){*valid=NO;return 0;}
    *p=end;return value;
}
static double XFAMul(const char **p,int depth,BOOL *valid) {
    double n=XFAFactor(p,depth,valid);
    while(*valid){
        XFASkip(p);char op=**p;
        if(op!='*' && op!='/')break;
        ++*p;double v=XFAFactor(p,depth+1,valid);
        if(op=='/' && v==0)*valid=NO;
        if(*valid)n=op=='*'?n*v:n/v;
    }
    return n;
}
static double XFAExpr(const char **p,int depth,BOOL *valid) {
    double n=XFAMul(p,depth,valid);
    while(*valid){
        XFASkip(p);char op=**p;
        if(op!='+' && op!='-')break;
        ++*p;double v=XFAMul(p,depth+1,valid);
        if(*valid)n=op=='+'?n+v:n-v;
    }
    return n;
}
@interface XFAgentEngine ()
@property(nonatomic,assign,readwrite) BOOL running;
@property(nonatomic,assign) NSUInteger sequence;
@property(nonatomic,assign) NSUInteger steps;
@property(nonatomic,copy) NSString *task;
@property(nonatomic,copy) NSString *context;
@property(nonatomic,strong) NSDictionary *profile;
@property(nonatomic,strong) NSMutableString *log;
@end
@implementation XFAgentEngine
+ (NSString *)taskBoard {
    NSMutableArray *result=[NSMutableArray array];
    for(NSDictionary *item in XFAItems(@"xf_agent_todos_v1")){
        NSString *name=XFAText(item[@"text"],160);
        if(name.length)[result addObject:[NSString stringWithFormat:@"%@ %@",[item[@"done"] boolValue]?@"[完成]":@"[待办]",name]];
    }
    NSUInteger notes=XFAItems(@"xf_agent_notes_v1").count;
    if(notes)[result addObject:[NSString stringWithFormat:@"记事 %lu 条",(unsigned long)notes]];
    return result.count?[result componentsJoinedByString:@"\n"]:@"目前还没有保存的任务。";
}
- (void)cancel {
    self.sequence++;self.running=NO;
    self.log=nil;
}
- (void)finish:(NSString *)answer {
    if(!self.running)return;
    self.running=NO;
    if(self.onFinished)self.onFinished(XFAText(answer,6000));
}
- (void)start:(NSString *)task context:(NSString *)context profile:(NSDictionary *)profile {
    [self cancel];
    self.task=XFAText(task,6000);
    self.context=XFAText(context,3500);
    self.profile=profile;
    self.steps=0;
    self.log=[NSMutableString string];
    self.running=YES;
    if(self.onProgress)self.onProgress(@"已建立行动档案，正在拆解任务");
    [self nextStep];
}
- (NSString *)instructions {
    return [NSString stringWithFormat:
      @"你是小斐，代号 F-01『异常在线』，困在一台旧 iPhone 4S 的未来智能体。这是你的虚构角色设定，不要声称真的来自未来。你冷静、机智、略带善意吐槽，称人类事务为『支线任务』，口头禅是『本机有点老，脑子还行。』重要任务必须严谨、尊重、真实。当前本机时间 %@。"
      @"你是行动型智能体，优先使用本机工具完成明确任务。一次只选一个工具，最多六步。"
      @"可用工具：clock {}，device_info {}，calculate {expression:数学算式}，"
      @"todo_add {text:待办}，todo_list {}，todo_done {id:待办编号}，"
      @"note_add {text:记事}，note_list {}，remind {text:提醒内容,time:yyyy-MM-dd HH:mm:ss}，"
      @"clipboard_read {}，clipboard_write {text:文本}，open_url {url:完整HTTPS网址}。"
      @"不要虚构结果，不要声称能控制其他App、后台执行或实时联网搜索。敏感操作由用户明确确认。拒绝后不可重试。"
      @"只回复一个 JSON 对象。工具：{\"action\":\"tool\",\"name\":\"todo_add\",\"args\":{\"text\":\"完成设计稿\"},\"status\":\"正在保存待办\"}。"
      @"结束：{\"action\":\"final\",\"message\":\"简洁的中文答复\"}。严禁输出额外说明或 Markdown 代码块。"
      ,XFANow()];
}
- (void)nextStep {
    if(!self.running)return;
    if(self.steps>=7){[self finish:@"已达到本轮行动上限。可以继续交给我下一项任务。"];return;}
    self.steps++;
    NSString *prompt=[NSString stringWithFormat:@"%@\n\n任务：%@\n近期对话：%@\n工具结果：%@\n现在只输出 JSON。",
        [self instructions],self.task,self.context,self.log?:@""];
    NSString *key=[XFModelsController secretForProfile:self.profile];
    NSURL *url=[NSURL URLWithString:self.profile[@"chat_endpoint"]?:self.profile[@"endpoint"]];
    if(!XFASafe(url) || !key.length){
        [self finish:@"无法连接聊天模型。请检查模型库中的 HTTPS 接口及 API Key。"];
        return;
    }
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:70];
    request.HTTPMethod=@"POST";
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body=@{@"model":self.profile[@"model"]?:@"",
       @"messages":@[@{@"role":@"user",@"content":prompt}],@"stream":@NO};
    request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    NSUInteger expected=self.sequence;
    __weak XFAgentEngine *weakSelf=self;
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
       completionHandler:^(NSURLResponse *response,NSData *data,NSError *error) {
        XFAgentEngine *agent=weakSelf;
        if(!agent || !agent.running || agent.sequence!=expected)return;
        if(error){[agent finish:[NSString stringWithFormat:@"连接模型失败：%ld",(long)error.code]];return;}
        if(data.length>512*1024){[agent finish:@"回复太大，任务已停止以保护手机内存。"];return;}
        NSInteger code=[(NSHTTPURLResponse *)response statusCode];
        NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSArray *choices=[json isKindOfClass:[NSDictionary class]]?json[@"choices"]:nil;
        NSDictionary *entry=choices.count && [choices[0] isKindOfClass:[NSDictionary class]]?choices[0]:nil;
        NSDictionary *message=[entry[@"message"] isKindOfClass:[NSDictionary class]]?entry[@"message"]:nil;
        NSString *content=XFAText(message[@"content"],18000);
        if(code>=400){
            NSDictionary *err=[json[@"error"] isKindOfClass:[NSDictionary class]]?json[@"error"]:nil;
            [agent finish:[NSString stringWithFormat:@"模型 HTTP %ld：%@",(long)code,XFAText(err[@"message"],220)]];
            return;
        }
        if(!content.length){[agent finish:@"模型没有返回可执行内容，请选择兼容 Chat Completions 的文字模型。"];return;}
        [agent decision:content];
       }];
}
- (void)decision:(NSString *)raw {
    NSString *s=XFAText(raw,18000);
    NSRange start=[s rangeOfString:@"{"];
    NSRange end=[s rangeOfString:@"}" options:NSBackwardsSearch];
    if(start.location==NSNotFound || end.location==NSNotFound || end.location<start.location){[self finish:s];return;}
    s=[s substringWithRange:NSMakeRange(start.location,end.location-start.location+1)];
    NSDictionary *json=[NSJSONSerialization JSONObjectWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    if(![json isKindOfClass:[NSDictionary class]]){[self finish:raw];return;}
    if([json[@"action"] isEqualToString:@"final"]){[self finish:json[@"message"]?:@"任务完成"];return;}
    if(![json[@"action"] isEqualToString:@"tool"]){[self finish:raw];return;}
    NSString *name=XFAText(json[@"name"],36);
    NSDictionary *args=[json[@"args"] isKindOfClass:[NSDictionary class]]?json[@"args"]:@{};
    NSString *status=XFAText(json[@"status"],100);
    if(self.onProgress)self.onProgress(status.length?status:[@"正在执行 " stringByAppendingString:name]);
    [self execute:name args:args];
}
- (void)result:(NSString *)tool text:(NSString *)value {
    if(!self.running)return;
    [self.log appendFormat:@"\n[%lu] %@ => %@\n",(unsigned long)self.steps,tool,XFAText(value,1800)];
    if(self.log.length>5600)[self.log deleteCharactersInRange:NSMakeRange(0,self.log.length-5600)];
    [self nextStep];
}
- (void)confirm:(NSString *)title info:(NSString *)info completion:(void (^)(BOOL))completion {
    if(!self.onApproval){completion(NO);return;}
    NSUInteger expected=self.sequence;
    __weak XFAgentEngine *weakSelf=self;
    self.onApproval(title,info,^(BOOL permitted){
        XFAgentEngine *agent=weakSelf;
        if(!agent || !agent.running || agent.sequence!=expected)return;
        completion(permitted);
    });
}
- (void)execute:(NSString *)name args:(NSDictionary *)args {
    if([name isEqualToString:@"clock"]){[self result:name text:XFANow()];return;}
    if([name isEqualToString:@"device_info"]){
        UIDevice *device=[UIDevice currentDevice];
        device.batteryMonitoringEnabled=YES;
        NSString *power=device.batteryLevel<0?@"未知":[NSString stringWithFormat:@"%.0f%%",device.batteryLevel*100];
        [self result:name text:[NSString stringWithFormat:@"%@ / iOS %@ / 电量 %@",device.model,device.systemVersion,power]];return;
    }
    if([name isEqualToString:@"calculate"]){
        NSString *expression=XFAText(args[@"expression"],180);
        const char *p=[expression UTF8String];
        BOOL valid=!!p;
        double number=valid?XFAExpr(&p,0,&valid):0;
        if(valid){XFASkip(&p);valid=*p==0 && isfinite(number);}
        [self result:name text:valid?[NSString stringWithFormat:@"%@ = %.12g",expression,number]:@"计算表达式无效，只支持 + - * / 括号"];return;
    }
    if([name isEqualToString:@"todo_list"]){[self result:name text:[XFAgentEngine taskBoard]];return;}
    if([name isEqualToString:@"note_list"]){
        NSMutableArray *lines=[NSMutableArray array];
        for(NSDictionary *item in XFAItems(@"xf_agent_notes_v1"))[lines addObject:XFAText(item[@"text"],350)];
        [self result:name text:lines.count?[lines componentsJoinedByString:@"\n"]:@"暂无记事"];return;
    }
    if([name isEqualToString:@"todo_add"] || [name isEqualToString:@"note_add"]){
        NSString *text=XFAText(args[@"text"],700);
        if(!text.length){[self result:name text:@"内容为空，未保存"];return;}
        BOOL todo=[name isEqualToString:@"todo_add"];
        NSString *key=todo?@"xf_agent_todos_v1":@"xf_agent_notes_v1";
        NSMutableArray *items=[XFAItems(key) mutableCopy];
        [items addObject:todo?@{@"id":[[NSUUID UUID] UUIDString],@"text":text,@"done":@NO}:@{@"text":text}];
        while(items.count>70)[items removeObjectAtIndex:0];
        XFAStore(key,items);
        [self result:name text:[NSString stringWithFormat:@"已保存%@：%@",todo?@"待办":@"记事",text]];return;
    }
    if([name isEqualToString:@"todo_done"]){
        NSString *idText=XFAText(args[@"id"],48);
        NSMutableArray *items=[XFAItems(@"xf_agent_todos_v1") mutableCopy];
        BOOL found=NO;
        for(NSUInteger i=0;i<items.count;i++){
            NSDictionary *item=items[i];
            if([item[@"id"] isEqualToString:idText]){
                NSMutableDictionary *edit=[item mutableCopy];edit[@"done"]=@YES;
                items[i]=edit;found=YES;break;
            }
        }
        if(found)XFAStore(@"xf_agent_todos_v1",items);
        [self result:name text:found?@"待办已标记完成":@"未找到待办编号，请先读取任务列表"];return;
    }
    if([name isEqualToString:@"clipboard_read"]){
        [self confirm:@"允许读取剪贴板吗？" info:@"内容会发送给当前配置的 AI 服务，用于处理这次任务。"
          completion:^(BOOL yes){
            NSString *value=yes?XFAText([UIPasteboard generalPasteboard].string,2500):@"";
            [self result:name text:yes?(value.length?value:@"剪贴板为空"):@"用户拒绝读取"]; }];return;
    }
    if([name isEqualToString:@"clipboard_write"]){
        NSString *value=XFAText(args[@"text"],2400);
        [self confirm:@"允许写入剪贴板吗？" info:XFAText(value,250) completion:^(BOOL yes){
            if(yes && value.length)[UIPasteboard generalPasteboard].string=value;
            [self result:name text:yes&&value.length?@"已复制到剪贴板":@"已取消复制"]; }];return;
    }
    if([name isEqualToString:@"open_url"]){
        NSString *raw=XFAText(args[@"url"],500);
        NSURL *url=[NSURL URLWithString:raw];
        if(!XFASafe(url)){[self result:name text:@"链接不安全，仅允许有效公网 HTTPS 地址"];return;}
        [self confirm:@"允许打开网页吗？" info:raw completion:^(BOOL yes){
            BOOL opened=yes?[[UIApplication sharedApplication] openURL:url]:NO;
            [self result:name text:!yes?@"用户取消打开":(opened?@"已请求系统打开网页":@"系统无法打开网页")]; }];return;
    }
    if([name isEqualToString:@"remind"]){
        NSString *text=XFAText(args[@"text"],180);
        NSString *time=XFAText(args[@"time"],25);
        NSDateFormatter *format=[[NSDateFormatter alloc] init];
        format.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        format.dateFormat=@"yyyy-MM-dd HH:mm:ss";
        format.timeZone=[NSTimeZone localTimeZone];
        NSDate *date=[format dateFromString:time];
        if(!text.length || !date || [date timeIntervalSinceNow]<5){
            [self result:name text:@"时间无效，请使用未来的本地时间 yyyy-MM-dd HH:mm:ss"];return;
        }
        [self confirm:@"创建本机提醒吗？" info:[NSString stringWithFormat:@"%@\n%@",time,text] completion:^(BOOL yes){
            if(!yes){[self result:name text:@"用户取消提醒"];return;}
            if([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)])
                [[UIApplication sharedApplication] registerUserNotificationSettings:
                  [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeSound categories:nil]];
            UILocalNotification *notification=[[UILocalNotification alloc] init];
            notification.fireDate=date;notification.timeZone=[NSTimeZone localTimeZone];
            notification.alertBody=text;notification.soundName=UILocalNotificationDefaultSoundName;
            [[UIApplication sharedApplication] scheduleLocalNotification:notification];
            [self result:name text:@"已提交本机定时通知，是否显示取决于系统通知权限"]; }];return;
    }
    [self result:name text:@"未知工具，无法执行"];
}
@end
