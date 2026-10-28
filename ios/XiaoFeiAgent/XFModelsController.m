#import "XFModelsController.h"
#import <Security/Security.h>

static NSString * const kXFProfiles = @"xf_saved_profiles";
static NSString * const kXFActive = @"xf_active_profile";
static NSString * const kXFService = @"com.finn.xiaofeiagent.profiles";

@interface XFModelsController ()
@property(nonatomic,strong) NSMutableArray *profiles;
@end

@implementation XFModelsController

+ (NSDictionary *)activeProfile {
    NSString *active = [[NSUserDefaults standardUserDefaults] stringForKey:kXFActive];
    NSArray *profiles = [[NSUserDefaults standardUserDefaults] arrayForKey:kXFProfiles];
    for (NSDictionary *p in profiles) {
        if ([p[@"id"] isEqualToString:active]) return p;
    }
    return nil;
}
+ (NSMutableDictionary *)queryForID:(NSString *)pid {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService:kXFService,
              (__bridge id)kSecAttrAccount:pid} mutableCopy];
}
+ (NSString *)secretsFile {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/XiaoFeiAgent"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions:@0700,
                     NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication}
        error:NULL];
    return [dir stringByAppendingPathComponent:@"profile-secrets.plist"];
}
+ (NSString *)secretForProfile:(NSDictionary *)profile {
    NSString *pid=profile[@"id"];
    if (![pid isKindOfClass:[NSString class]] || !pid.length) return nil;
    NSMutableDictionary *q=[self queryForID:pid];
    q[(__bridge id)kSecReturnData]=@YES;
    q[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
    CFTypeRef result=NULL;
    OSStatus err=SecItemCopyMatching((__bridge CFDictionaryRef)q,&result);
    if(err==errSecSuccess && result) {
        NSData *bytes=(__bridge_transfer NSData *)result;
        return [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
    }
    NSDictionary *fallback=[NSDictionary dictionaryWithContentsOfFile:[self secretsFile]];
    id secret=fallback[pid];
    return [secret isKindOfClass:[NSString class]]?secret:nil;
}
+ (OSStatus)writeKeychain:(NSString *)key forID:(NSString *)pid {
    NSMutableDictionary *query=[self queryForID:pid];
    NSData *data=[key dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *changes=@{(__bridge id)kSecValueData:data};
    OSStatus err=SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)changes);
    if(err==errSecItemNotFound) {
        query[(__bridge id)kSecValueData]=data;
        query[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        err=SecItemAdd((__bridge CFDictionaryRef)query,NULL);
    }
    return err;
}
+ (BOOL)writeFallback:(NSString *)key forID:(NSString *)pid {
    NSString *path=[self secretsFile];
    NSMutableDictionary *values=[NSMutableDictionary dictionaryWithContentsOfFile:path];
    if(!values) values=[NSMutableDictionary dictionary];
    if(key.length) values[pid]=key; else [values removeObjectForKey:pid];
    if(![values writeToFile:path atomically:YES]) return NO;
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600,
        NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:path error:NULL];
    return YES;
}
+ (void)removeSecretForID:(NSString *)pid {
    SecItemDelete((__bridge CFDictionaryRef)[self queryForID:pid]);
    [self writeFallback:@"" forID:pid];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"模型管理";
    NSArray *saved=[[NSUserDefaults standardUserDefaults] arrayForKey:kXFProfiles];
    self.profiles=saved?[saved mutableCopy]:[NSMutableArray array];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
        target:self action:@selector(addTapped)];
    self.tableView.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero];
}
- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)saveProfiles {
    [[NSUserDefaults standardUserDefaults] setObject:self.profiles forKey:kXFProfiles];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s==0?self.profiles.count:1; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return s==0?@"点击一行选择模型，点击右侧编辑":@"使用说明";
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[t dequeueReusableCellWithIdentifier:@"profile"];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"profile"];
    cell.textLabel.font=[UIFont systemFontOfSize:16];
    cell.accessoryType=UITableViewCellAccessoryNone;
    if(index.section!=0) {
        cell.textLabel.text=@"右上角 ＋ 添加模型";
        cell.detailTextLabel.text=@"可以添加多个厂商，保留多个 API Key";
        cell.selectionStyle=UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *p=self.profiles[index.row];
    NSString *active=[[NSUserDefaults standardUserDefaults] stringForKey:kXFActive];
    BOOL chosen=[p[@"id"] isEqualToString:active];
    cell.textLabel.text=[NSString stringWithFormat:@"%@%@",chosen?@"✓  ":@"",p[@"name"]];
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",p[@"provider"],p[@"model"]];
    cell.accessoryType=UITableViewCellAccessoryDetailButton;
    cell.selectionStyle=UITableViewCellSelectionStyleDefault;
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)index {
    [t deselectRowAtIndexPath:index animated:YES];
    if(index.section!=0) return;
    NSDictionary *p=self.profiles[index.row];
    if (![[XFModelsController secretForProfile:p] length]) {
        [self editProfile:p index:index.row];
        return;
    }
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    [d setObject:p[@"id"] forKey:kXFActive];
    [d setObject:@"direct" forKey:@"connect_mode"];
    [d synchronize];
    [self.tableView reloadData];
}
- (void)tableView:(UITableView *)t accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)index {
    if(index.section==0) [self editProfile:self.profiles[index.row] index:index.row];
}
- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)index {return index.section==0;}
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)index {
    if(index.section!=0 || style!=UITableViewCellEditingStyleDelete) return;
    NSDictionary *p=self.profiles[index.row];
    [XFModelsController removeSecretForID:p[@"id"]];
    [self.profiles removeObjectAtIndex:index.row];
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    if([[d stringForKey:kXFActive] isEqualToString:p[@"id"]]) [d removeObjectForKey:kXFActive];
    [self saveProfiles];
}
- (NSArray *)presets {
    return @[
      @{@"provider":@"DeepSeek",@"endpoint":@"https://api.deepseek.com/chat/completions",@"model":@"deepseek-flash"},
      @{@"provider":@"通义千问",@"endpoint":@"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",@"model":@"qwen-plus"},
      @{@"provider":@"Kimi",@"endpoint":@"https://api.moonshot.cn/v1/chat/completions",@"model":@"kimi-k2.6"},
      @{@"provider":@"智谱 GLM",@"endpoint":@"https://open.bigmodel.cn/api/paas/v4/chat/completions",@"model":@"glm-4-flash"},
      @{@"provider":@"MiniMax",@"endpoint":@"https://api.minimax.io/v1/chat/completions",@"model":@"MiniMax-M2"},
      @{@"provider":@"自定义兼容接口",@"endpoint":@"https://",@"model":@""}
    ];
}
- (void)addTapped {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"添加模型" message:@"选择厂商，之后可修改模型 ID 和完整接口地址"
        preferredStyle:UIAlertControllerStyleAlert];
    for(NSDictionary *preset in [self presets]) {
        [a addAction:[UIAlertAction actionWithTitle:preset[@"provider"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *act){
            [self editProfile:preset index:-1];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)showMessage:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"提示" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)editProfile:(NSDictionary *)profile index:(NSInteger)index {
    BOOL existing=index>=0;
    NSString *pid=existing?profile[@"id"]:[[NSUUID UUID] UUIDString];
    UIAlertController *form=[UIAlertController alertControllerWithTitle:existing?@"编辑模型":@"添加模型"
        message:@"可以随时修改名称、模型 ID、URL 和密钥。已有密钥留空则保留。"
        preferredStyle:UIAlertControllerStyleAlert];
    NSArray *labels=@[@"显示名称",@"模型 ID",@"完整 HTTPS 接口地址",@"API Key（已有密钥可留空）"];
    NSArray *values=@[profile[@"name"]?:profile[@"provider"]?:@"",profile[@"model"]?:@"",profile[@"endpoint"]?:@"",@""];
    for(NSInteger i=0;i<4;i++) {
        NSString *label=labels[i],*value=values[i];
        [form addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder=label;
            field.text=value;
            field.autocorrectionType=UITextAutocorrectionTypeNo;
            field.autocapitalizationType=UITextAutocapitalizationTypeNone;
            if(i==3) field.secureTextEntry=YES;
        }];
    }
    [form addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [form addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSArray *fields=form.textFields;
        NSString *name=[[fields[0] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *model=[[fields[1] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *endpoint=[[fields[2] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *key=[fields[3] text];
        NSURL *url=[NSURL URLWithString:endpoint];
        if(!name.length || !model.length || ![url.scheme isEqualToString:@"https"] || !url.host.length) {
            [self showMessage:@"名称、模型 ID 不能为空，接口必须是完整 HTTPS URL"];
            return;
        }
        NSDictionary *saved=@{@"id":pid,@"name":name,@"model":model,@"endpoint":endpoint,
                               @"provider":profile[@"provider"]?:@"自定义"};
        if(key.length) {
            OSStatus code=[XFModelsController writeKeychain:key forID:pid];
            if(code!=errSecSuccess) {
                [self offerFallback:key code:code saved:saved index:index];
                return;
            }
        } else if(![[XFModelsController secretForProfile:saved] length]) {
            // One provider may have multiple model profiles sharing one API key.
            NSString *reuse=nil;
            for(NSDictionary *other in self.profiles) {
                if([other[@"provider"] isEqualToString:saved[@"provider"]]) {
                    reuse=[XFModelsController secretForProfile:other];
                    if(reuse.length) break;
                }
            }
            if(reuse.length) {
                OSStatus code=[XFModelsController writeKeychain:reuse forID:pid];
                if(code!=errSecSuccess) {
                    [self offerFallback:reuse code:code saved:saved index:index];
                    return;
                }
            } else {
                [self showMessage:@"首次添加该厂商时，请填写 API Key"];
                return;
            }
        }
        [self finishSave:saved index:index];
    }]];
    [self presentViewController:form animated:YES completion:nil];
}
- (void)offerFallback:(NSString *)key code:(OSStatus)code saved:(NSDictionary *)saved index:(NSInteger)index {
    NSString *message=[NSString stringWithFormat:@"iOS 钥匙串写入错误 %ld。可自愿改用 App 私有文件，保护弱于钥匙串，越狱设备有泄露风险。",(long)code];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"密钥存储失败"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"使用本机兼容存储" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act){
        if(![XFModelsController writeFallback:key forID:saved[@"id"]]) {
            [self showMessage:@"本机保存失败，请检查应用权限"]; return;
        }
        [self finishSave:saved index:index];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)finishSave:(NSDictionary *)profile index:(NSInteger)index {
    if(index>=0 && index<self.profiles.count) self.profiles[index]=profile;
    else [self.profiles addObject:profile];
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    if(![d stringForKey:kXFActive]){
        [d setObject:profile[@"id"] forKey:kXFActive];
        [d setObject:@"direct" forKey:@"connect_mode"];
    }
    [self saveProfiles];
}
@end
