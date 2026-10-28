#import "XFModelsController.h"
#import <Security/Security.h>

static NSString *const XFAccountsKey=@"xf_api_accounts_v1";
static NSString *const XFSelectionKey=@"xf_active_models_v1";
static NSString *const XFSecretService=@"com.finn.xiaofeiagent.connections";

static NSString *XFTrim(NSString *s) {
    return [[s?:@"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
}
static NSArray *XFCategories(void) {
    return @[@"文字对话",@"深度推理",@"图片理解",@"图片生成",@"语音识别",@"语音朗读",@"联网搜索",@"其他模型"];
}
static NSString *XFCapability(NSString *category) {
    if([category isEqualToString:@"图片理解"])return @"vision";
    if([category isEqualToString:@"图片生成"])return @"image";
    if([category isEqualToString:@"语音识别"])return @"stt";
    if([category isEqualToString:@"语音朗读"])return @"tts";
    if([category isEqualToString:@"联网搜索"])return @"web";
    if([category isEqualToString:@"其他模型"])return @"other";
    return @"chat";
}
static NSString *XFBaseFromEndpoint(NSString *urlString) {
    NSString *value=[urlString?:@"" copy];
    for(NSString *suffix in @[@"/chat/completions",@"/images/generations",@"/audio/transcriptions",@"/audio/speech"]){
        if([value hasSuffix:suffix]) return [value substringToIndex:value.length-suffix.length];
    }
    return value;
}
static NSString *XFEndpoint(NSDictionary *account,NSString *capability) {
    NSString *base=account[@"base"]?:@"";
    NSString *suffix=@"chat/completions";
    if([capability isEqualToString:@"image"])suffix=@"images/generations";
    if([capability isEqualToString:@"stt"])suffix=@"audio/transcriptions";
    if([capability isEqualToString:@"tts"])suffix=@"audio/speech";
    if([base hasSuffix:@"/"])return [base stringByAppendingString:suffix];
    return [base stringByAppendingFormat:@"/%@",suffix];
}
static BOOL XFHas(NSArray *array,NSString *item) {
    if(![array isKindOfClass:[NSArray class]])return NO;
    for(id value in array)if([value isKindOfClass:[NSString class]] && [[(NSString *)value lowercaseString] isEqualToString:item])return YES;
    return NO;
}
static NSString *XFKind(NSDictionary *m) {
    NSString *idText=[m[@"id"] isKindOfClass:[NSString class]]?m[@"id"]:@"";
    NSString *s=[idText lowercaseString];
    NSString *category=m[@"user_category"];
    if([category isKindOfClass:[NSString class]] && [XFCategories() containsObject:category])return category;
    NSDictionary *arch=[m[@"architecture"] isKindOfClass:[NSDictionary class]]?m[@"architecture"]:@{};
    NSArray *input=m[@"input_modalities"]?:arch[@"input_modalities"];
    NSArray *output=m[@"output_modalities"]?:arch[@"output_modalities"];
    if(XFHas(output,@"image") || [s containsString:@"image-gen"] || [s containsString:@"gpt-image"] ||
       [s containsString:@"dall-e"] || [s containsString:@"flux"] || [s containsString:@"qwen-image"])return @"图片生成";
    if([s containsString:@"embedding"] || [s containsString:@"embed"] || [s containsString:@"rerank"] ||
       [s containsString:@"moderation"])return @"其他模型";
    if([s containsString:@"transcri"] || [s containsString:@"whisper"] || [s containsString:@"asr"] ||
       [s containsString:@"speech-to-text"])return @"语音识别";
    if([s containsString:@"tts"] || [s containsString:@"text-to-speech"] ||
       [s containsString:@"speech-gen"])return @"语音朗读";
    if(XFHas(input,@"image") || [m[@"supports_image_in"] boolValue] ||
       [s containsString:@"vision"] || [s containsString:@"-vl"] || [s containsString:@"pixtral"])return @"图片理解";
    if([s containsString:@"search"] && ![s containsString:@"researcher"])return @"联网搜索";
    if([m[@"supports_reasoning"] boolValue] || [s containsString:@"reason"] ||
       [s containsString:@"deepseek-r1"] || [s containsString:@"qwq"] ||
       [s containsString:@"-thinking"])return @"深度推理";
    return @"文字对话";
}
static NSMutableDictionary *XFQuery(NSString *aid,NSString *service) {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrService:service,(__bridge id)kSecAttrAccount:aid} mutableCopy];
}
static NSString *XFSecretFile(void) {
    NSString *folder=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/XiaoFeiAgent"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES
      attributes:@{NSFilePosixPermissions:@0700,
      NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:NULL];
    return [folder stringByAppendingPathComponent:@"api-keys.plist"];
}
static NSString *XFGetSecretFrom(NSString *aid,NSString *service) {
    NSMutableDictionary *q=XFQuery(aid,service);
    q[(__bridge id)kSecReturnData]=@YES;
    q[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
    CFTypeRef r=NULL;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)q,&r);
    if(status==errSecSuccess && r)return [[NSString alloc] initWithData:(__bridge_transfer NSData *)r encoding:NSUTF8StringEncoding];
    return nil;
}
static NSString *XFSecret(NSString *aid) {
    if(!aid.length)return nil;
    NSString *found=XFGetSecretFrom(aid,XFSecretService);
    if(found.length)return found;
    found=XFGetSecretFrom(aid,@"com.finn.xiaofeiagent.profiles");
    if(found.length)return found;
    NSDictionary *keys=[NSDictionary dictionaryWithContentsOfFile:XFSecretFile()];
    found=keys[aid];if([found isKindOfClass:[NSString class]] && found.length)return found;
    NSString *old=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/XiaoFeiAgent/profile-secrets.plist"];
    keys=[NSDictionary dictionaryWithContentsOfFile:old];
    found=keys[aid];
    return [found isKindOfClass:[NSString class]]?found:nil;
}
static OSStatus XFSaveKey(NSString *aid,NSString *key){
    NSMutableDictionary *q=XFQuery(aid,XFSecretService);
    NSDictionary *update=@{(__bridge id)kSecValueData:[key dataUsingEncoding:NSUTF8StringEncoding]};
    OSStatus e=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)update);
    if(e==errSecItemNotFound){
        q[(__bridge id)kSecValueData]=update[(__bridge id)kSecValueData];
        q[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        e=SecItemAdd((__bridge CFDictionaryRef)q,NULL);
    }
    return e;
}
static BOOL XFSaveFileSecret(NSString *aid,NSString *secret) {
    NSString *path=XFSecretFile();
    NSMutableDictionary *all=[NSMutableDictionary dictionaryWithContentsOfFile:path];
    if(!all)all=[NSMutableDictionary dictionary];
    if(secret.length)all[aid]=secret;else [all removeObjectForKey:aid];
    if(![all writeToFile:path atomically:YES])return NO;
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600,
      NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:path error:NULL];
    return YES;
}
static void XFDeleteSecret(NSString *aid) {
    SecItemDelete((__bridge CFDictionaryRef)XFQuery(aid,XFSecretService));
    SecItemDelete((__bridge CFDictionaryRef)XFQuery(aid,@"com.finn.xiaofeiagent.profiles"));
    XFSaveFileSecret(aid,@"");
}
static void XFMigrate(void){
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    if([d objectForKey:XFAccountsKey])return;
    NSArray *legacy=[d arrayForKey:@"xf_saved_profiles"];
    NSMutableArray *accounts=[NSMutableArray array];
    NSMutableDictionary *selection=[NSMutableDictionary dictionary];
    NSString *active=[d stringForKey:@"xf_active_profile"];
    for(NSDictionary *old in legacy){
        NSString *aid=old[@"id"];
        if(![aid isKindOfClass:[NSString class]] || !aid.length)continue;
        NSString *base=XFBaseFromEndpoint(old[@"endpoint"]);
        if(!base.length)continue;
        NSString *mid=old[@"model"]?:@"";
        NSString *cap=old[@"capability"]?:@"chat";
        NSString *category=[cap isEqualToString:@"vision"]?@"图片理解":
          [cap isEqualToString:@"image"]?@"图片生成":
          [cap isEqualToString:@"stt"]?@"语音识别":
          [cap isEqualToString:@"tts"]?@"语音朗读":
          [cap isEqualToString:@"web"]?@"联网搜索":@"文字对话";
        [accounts addObject:@{@"id":aid,@"name":old[@"name"]?:old[@"provider"]?:@"旧 API",
          @"base":base,@"models_url":@"",@"models":@[@{@"id":mid,@"name":mid,@"user_category":category}],
          @"legacy_endpoint":old[@"endpoint"]?:@""}];
        if([active isEqualToString:aid] || !selection[cap])selection[cap]=@{@"account":aid,@"model":mid};
    }
    [d setObject:accounts forKey:XFAccountsKey];
    [d setObject:selection forKey:XFSelectionKey];
    [d synchronize];
}
static NSArray *XFAccounts(void){XFMigrate();return [[NSUserDefaults standardUserDefaults] arrayForKey:XFAccountsKey]?:@[];}
static void XFStoreAccounts(NSArray *items) {[[NSUserDefaults standardUserDefaults] setObject:items forKey:XFAccountsKey];[[NSUserDefaults standardUserDefaults] synchronize];}
static NSDictionary *XFAccountForID(NSString *aid) {
    for(NSDictionary *a in XFAccounts())if([a[@"id"] isEqualToString:aid])return a;
    return nil;
}
static NSDictionary *XFSelected(NSString *cap) {
    return [[[NSUserDefaults standardUserDefaults] dictionaryForKey:XFSelectionKey] objectForKey:cap];
}
static void XFSelect(NSString *cap,NSString *aid,NSString *mid){
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    NSMutableDictionary *map=[[d dictionaryForKey:XFSelectionKey] mutableCopy]?:[NSMutableDictionary dictionary];
    map[cap]=@{@"account":aid,@"model":mid};
    [d setObject:map forKey:XFSelectionKey];
    if([cap isEqualToString:@"chat"])[d setObject:@"direct" forKey:@"connect_mode"];
    [d synchronize];
}
static void XFReplaceAccount(NSDictionary *account) {
    NSMutableArray *all=[XFAccounts() mutableCopy];BOOL replaced=NO;
    for(NSUInteger i=0;i<all.count;i++)if([all[i][@"id"] isEqualToString:account[@"id"]]){
        all[i]=account;replaced=YES;break;
    }
    if(!replaced)[all addObject:account];
    XFStoreAccounts(all);
}
static void XFDropAccount(NSString *aid){
    NSMutableArray *all=[XFAccounts() mutableCopy];
    NSIndexSet *indices=[all indexesOfObjectsPassingTest:^BOOL(NSDictionary *a,NSUInteger i,BOOL *stop){
        return [a[@"id"] isEqualToString:aid];
    }];
    [all removeObjectsAtIndexes:indices];XFStoreAccounts(all);
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    NSMutableDictionary *map=[[d dictionaryForKey:XFSelectionKey] mutableCopy];
    for(NSString *kind in [map allKeys])if([map[kind][@"account"] isEqualToString:aid])[map removeObjectForKey:kind];
    [d setObject:map forKey:XFSelectionKey];[d synchronize];XFDeleteSecret(aid);
}

@interface XFAPIEditor : UIViewController <UITextFieldDelegate>
@property(nonatomic,strong) NSDictionary *account;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UITextField *titleField;
@property(nonatomic,strong) UITextField *baseField;
@property(nonatomic,strong) UITextField *listField;
@property(nonatomic,strong) UITextField *keyField;
@property(nonatomic,copy) void (^onSaved)(NSDictionary *account,NSString *newKey);
@end
@implementation XFAPIEditor
- (UITextField *)fieldAt:(CGFloat)y label:(NSString *)label value:(NSString *)value {
    UILabel *t=[[UILabel alloc] initWithFrame:CGRectMake(14,y,self.view.bounds.size.width-28,22)];
    t.text=label;t.font=[UIFont systemFontOfSize:13];[self.scroll addSubview:t];
    UITextField *f=[[UITextField alloc] initWithFrame:CGRectMake(14,y+25,self.view.bounds.size.width-28,43)];
    f.autoresizingMask=UIViewAutoresizingFlexibleWidth;f.borderStyle=UITextBorderStyleRoundedRect;
    f.backgroundColor=[UIColor whiteColor];f.font=[UIFont systemFontOfSize:14];f.text=value;
    f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;
    f.delegate=self;f.returnKeyType=UIReturnKeyDone;[self.scroll addSubview:f];return f;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"API 服务配置";
    self.view.backgroundColor=[UIColor colorWithWhite:0.96 alpha:1];
    self.scroll=[[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scroll];
    self.titleField=[self fieldAt:10 label:@"服务名称（如 OpenRouter）" value:self.account[@"name"]];
    self.baseField=[self fieldAt:88 label:@"API Base URL（通常以 /v1 结尾）" value:self.account[@"base"]];
    self.baseField.keyboardType=UIKeyboardTypeURL;
    self.listField=[self fieldAt:166 label:@"模型列表地址（留空自动推导 /models）" value:self.account[@"models_url"]];
    self.listField.keyboardType=UIKeyboardTypeURL;
    self.keyField=[self fieldAt:244 label:@"API Key（编辑时留空保持原密钥）" value:nil];
    self.keyField.secureTextEntry=YES;
    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(14,335,self.view.bounds.size.width-28,96)];
    hint.autoresizingMask=UIViewAutoresizingFlexibleWidth;hint.numberOfLines=0;
    hint.font=[UIFont systemFontOfSize:12];hint.textColor=[UIColor grayColor];
    hint.text=@"一个服务只需要保存一次密钥。保存后会自动读取模型列表。部分厂商不提供标准 /models，可以手动指定模型列表地址或手动添加模型。";
    [self.scroll addSubview:hint];
    self.scroll.contentSize=CGSizeMake(self.view.bounds.size.width,480);
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardClose) name:UIKeyboardWillHideNotification object:nil];
}
- (void)dealloc {[[NSNotificationCenter defaultCenter] removeObserver:self];}
- (void)keyboard:(NSNotification *)n {
    CGRect frame=[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    self.scroll.contentInset=UIEdgeInsetsMake(0,0,frame.size.height+10,0);
}
- (void)keyboardClose {self.scroll.contentInset=UIEdgeInsetsZero;}
- (BOOL)textFieldShouldReturn:(UITextField *)f {[f resignFirstResponder];return YES;}
- (void)save {
    [self.view endEditing:YES];
    NSString *name=XFTrim(self.titleField.text),*base=XFTrim(self.baseField.text);
    NSString *list=XFTrim(self.listField.text),*secret=XFTrim(self.keyField.text);
    NSURL *u=[NSURL URLWithString:base],*l=list.length?[NSURL URLWithString:list]:nil;
    if(!name.length || ![[u scheme] isEqualToString:@"https"] || ![u host].length ||
       (list.length && (![[l scheme] isEqualToString:@"https"] || ![l host].length))) {
        UIAlertController *e=[UIAlertController alertControllerWithTitle:@"请检查信息" message:@"需要服务名称和完整 HTTPS Base URL。模型列表地址可留空。" preferredStyle:UIAlertControllerStyleAlert];
        [e addAction:[UIAlertAction actionWithTitle:@"继续编辑" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:e animated:YES completion:nil];return;
    }
    NSString *aid=self.account[@"id"]?:[[NSUUID UUID] UUIDString];
    NSMutableDictionary *a=[self.account mutableCopy]?:[NSMutableDictionary dictionary];
    a[@"id"]=aid;a[@"name"]=name;a[@"base"]=XFBaseFromEndpoint(base);a[@"models_url"]=list;
    if(!a[@"models"])a[@"models"]=@[];
    if(self.onSaved)self.onSaved(a,secret);
}
@end

@interface XFAPIAccountsController : UITableViewController
@property(nonatomic,copy) void (^changed)(void);
@end
@implementation XFAPIAccountsController
- (NSArray *)presets {
    return @[
      @{@"name":@"DeepSeek",@"base":@"https://api.deepseek.com",@"models_url":@"https://api.deepseek.com/models"},
      @{@"name":@"通义千问（北京）",@"base":@"https://dashscope.aliyuncs.com/compatible-mode/v1",@"models_url":@"https://dashscope.aliyuncs.com/api/v1/models"},
      @{@"name":@"Kimi",@"base":@"https://api.moonshot.cn/v1",@"models_url":@"https://api.moonshot.cn/v1/models"},
      @{@"name":@"智谱 GLM",@"base":@"https://open.bigmodel.cn/api/paas/v4",@"models_url":@"https://open.bigmodel.cn/api/paas/v4/models"},
      @{@"name":@"MiniMax",@"base":@"https://api.minimax.io/v1",@"models_url":@"https://api.minimax.io/v1/models"},
      @{@"name":@"OpenRouter",@"base":@"https://openrouter.ai/api/v1",@"models_url":@"https://openrouter.ai/api/v1/models"},
      @{@"name":@"自定义 API",@"base":@"https://",@"models_url":@""}
    ];
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"API 服务";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)];
    self.tableView.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {return XFAccounts().count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[t dequeueReusableCellWithIdentifier:@"account"];
    if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"account"];
    NSDictionary *a=XFAccounts()[ip.row];
    c.textLabel.text=a[@"name"];
    c.detailTextLabel.text=[NSString stringWithFormat:@"%lu 个模型 · 点击同步 / 编辑",(unsigned long)[a[@"models"] count]];
    c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;
}
- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip {return YES;}
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if(style!=UITableViewCellEditingStyleDelete)return;
    NSString *aid=XFAccounts()[ip.row][@"id"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"删除 API 服务？"
       message:@"该服务下保存的模型及密钥会一并删除。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *b) {
        XFDropAccount(aid);[self.tableView reloadData];if(self.changed)self.changed();
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *account=XFAccounts()[ip.row];
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:account[@"name"]
      message:[NSString stringWithFormat:@"当前保存 %lu 个模型",(unsigned long)[account[@"models"] count]]
      preferredStyle:UIAlertControllerStyleAlert];
    [menu addAction:[UIAlertAction actionWithTitle:@"刷新模型列表" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self fetchModels:account];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"编辑服务与密钥" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self editor:account];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"手动添加模型" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self manualModel:account];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)add {
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"添加 API 服务"
        message:@"只需要添加一次服务，之后自动同步模型库" preferredStyle:UIAlertControllerStyleAlert];
    for(NSDictionary *preset in [self presets]) {
        [menu addAction:[UIAlertAction actionWithTitle:preset[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self editor:preset];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)editor:(NSDictionary *)account {
    XFAPIEditor *editor=[[XFAPIEditor alloc] init];
    editor.account=account;
    __weak XFAPIEditor *weakEditor=editor;
    editor.onSaved=^(NSDictionary *newAccount,NSString *newKey) {
        if(newKey.length) {
            OSStatus error=XFSaveKey(newAccount[@"id"],newKey);
            if(error!=errSecSuccess) {
                [self fallbackForAccount:newAccount key:newKey error:error];
                return;
            }
        } else if(!XFSecret(newAccount[@"id"]).length) {
            UIAlertController *e=[UIAlertController alertControllerWithTitle:@"未填写密钥"
              message:@"首次添加这个 API 服务需要填写 API Key。" preferredStyle:UIAlertControllerStyleAlert];
            [e addAction:[UIAlertAction actionWithTitle:@"继续填写" style:UIAlertActionStyleDefault handler:nil]];
            [weakEditor presentViewController:e animated:YES completion:nil];return;
        }
        [self completeAccount:newAccount];
    };
    [self.navigationController pushViewController:editor animated:YES];
}
- (void)fallbackForAccount:(NSDictionary *)account key:(NSString *)key error:(OSStatus)code {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"系统钥匙串写入失败"
      message:[NSString stringWithFormat:@"错误码 %ld。越狱设备可选择仅在 App 私有文件中保存，安全性低于钥匙串。",(long)code]
      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"同意兼容存储" style:UIAlertActionStyleDefault handler:^(UIAlertAction *b){
        if(!XFSaveFileSecret(account[@"id"],key)){[self alert:@"本机文件保存失败"];return;}
        [self completeAccount:account];
    }]];
    [self.navigationController.topViewController presentViewController:a animated:YES completion:nil];
}
- (void)completeAccount:(NSDictionary *)a {
    XFReplaceAccount(a);
    [self.navigationController popViewControllerAnimated:YES];
    [self.tableView reloadData];if(self.changed)self.changed();
    [self fetchModels:a];
}
- (void)alert:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"API 服务" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)manualModel:(NSDictionary *)a {
    UIAlertController *form=[UIAlertController alertControllerWithTitle:@"手动添加模型"
      message:@"适合厂商不支持 /models 的情况" preferredStyle:UIAlertControllerStyleAlert];
    [form addTextFieldWithConfigurationHandler:^(UITextField *f){
        f.placeholder=@"模型 ID，如 qwen-plus";
        f.autocapitalizationType=UITextAutocapitalizationTypeNone;
        f.autocorrectionType=UITextAutocorrectionTypeNo;
    }];
    [form addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [form addAction:[UIAlertAction actionWithTitle:@"继续选择分类" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *mid=XFTrim(form.textFields[0].text);
        if(!mid.length){[self alert:@"模型 ID 不能为空"];return;}
        UIAlertController *pick=[UIAlertController alertControllerWithTitle:mid message:@"选择这个模型的主要用途"
           preferredStyle:UIAlertControllerStyleAlert];
        for(NSString *category in XFCategories()) {
            [pick addAction:[UIAlertAction actionWithTitle:category style:UIAlertActionStyleDefault handler:^(UIAlertAction *p) {
                NSMutableDictionary *updated=[a mutableCopy];
                NSMutableArray *list=[a[@"models"] mutableCopy]?:[NSMutableArray array];
                NSIndexSet *existing=[list indexesOfObjectsPassingTest:^BOOL(NSDictionary *m,NSUInteger i,BOOL *stop) {
                    return [m[@"id"] isEqualToString:mid];
                }];
                [list removeObjectsAtIndexes:existing];
                [list addObject:@{@"id":mid,@"name":mid,@"user_category":category}];
                updated[@"models"]=list;XFReplaceAccount(updated);
                [self.tableView reloadData];if(self.changed)self.changed();
            }]];
        }
        [pick addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:pick animated:YES completion:nil];
    }]];
    [self presentViewController:form animated:YES completion:nil];
}
- (void)fetchModels:(NSDictionary *)a {
    NSString *base=a[@"base"]?:@"";
    NSString *url=a[@"models_url"];
    if(!url.length) url=[base hasSuffix:@"/"]?[base stringByAppendingString:@"models"]:[base stringByAppendingString:@"/models"];
    NSURL *location=[NSURL URLWithString:url];
    if(![[location scheme] isEqualToString:@"https"]){[self alert:@"模型列表地址必须为 HTTPS"];return;}
    NSString *secret=XFSecret(a[@"id"]);
    if(!secret.length){[self alert:@"请先为这个服务保存 API Key"];return;}
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:location];
    request.HTTPMethod=@"GET";request.timeoutInterval=35;
    [request setValue:[@"Bearer " stringByAppendingString:secret] forHTTPHeaderField:@"Authorization"];
    self.title=@"正在获取模型…";
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
      completionHandler:^(NSURLResponse *response,NSData *data,NSError *error) {
        self.title=@"API 服务";
        if(error){[self alert:[NSString stringWithFormat:@"模型同步失败（网络错误 %ld）。旧版 iOS 可能无法连接现代 HTTPS。可手动添加模型。",(long)error.code]];return;}
        NSInteger status=[(NSHTTPURLResponse *)response statusCode];
        if(status<200 || status>=300){[self alert:[NSString stringWithFormat:@"模型接口返回 HTTP %ld。请检查密钥及厂商专用模型列表地址。",(long)status]];return;}
        if(data.length>6*1024*1024){[self alert:@"模型列表太大，已停止加载以保护 iPhone 4S 内存"];return;}
        id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSArray *rows=[json isKindOfClass:[NSDictionary class]]?json[@"data"]:nil;
        if(![rows isKindOfClass:[NSArray class]]) rows=[json isKindOfClass:[NSDictionary class]]?json[@"models"]:nil;
        if(![rows isKindOfClass:[NSArray class]]){[self alert:@"未识别模型列表格式，可选择手动添加模型"];return;}
        NSDictionary *current=XFAccountForID(a[@"id"]);
        NSMutableDictionary *overrides=[NSMutableDictionary dictionary];
        for(NSDictionary *item in current[@"models"])if([item[@"user_category"] isKindOfClass:[NSString class]])overrides[item[@"id"]]=item[@"user_category"];
        NSMutableArray *models=[NSMutableArray array];
        NSMutableSet *seen=[NSMutableSet set];
        for(id raw in rows){
            if(models.count>=700)break;
            NSDictionary *item=[raw isKindOfClass:[NSDictionary class]]?raw:nil;
            NSString *mid=item[@"id"];
            if(![mid isKindOfClass:[NSString class]] || !mid.length || [seen containsObject:mid])continue;
            [seen addObject:mid];
            // Only keep property-list values; API JSON often contains NSNull.
            NSMutableDictionary *model=[NSMutableDictionary dictionary];
            model[@"id"]=mid;
            model[@"name"]=[item[@"name"] isKindOfClass:[NSString class]]?item[@"name"]:mid;
            NSDictionary *arch=[item[@"architecture"] isKindOfClass:[NSDictionary class]]?item[@"architecture"]:nil;
            NSArray *inModalities=[item[@"input_modalities"] isKindOfClass:[NSArray class]]?item[@"input_modalities"]:arch[@"input_modalities"];
            NSArray *outModalities=[item[@"output_modalities"] isKindOfClass:[NSArray class]]?item[@"output_modalities"]:arch[@"output_modalities"];
            if([inModalities isKindOfClass:[NSArray class]]) {
                NSMutableArray *safe=[NSMutableArray array];
                for(id x in inModalities)if([x isKindOfClass:[NSString class]])[safe addObject:x];
                model[@"input_modalities"]=safe;
            }
            if([outModalities isKindOfClass:[NSArray class]]) {
                NSMutableArray *safe=[NSMutableArray array];
                for(id x in outModalities)if([x isKindOfClass:[NSString class]])[safe addObject:x];
                model[@"output_modalities"]=safe;
            }
            if([item[@"supports_image_in"] isKindOfClass:[NSNumber class]])model[@"supports_image_in"]=item[@"supports_image_in"];
            if([item[@"supports_reasoning"] isKindOfClass:[NSNumber class]])model[@"supports_reasoning"]=item[@"supports_reasoning"];
            if(overrides[mid])model[@"user_category"]=overrides[mid];
            [models addObject:model];
        }
        if(!models.count){[self alert:@"模型列表为空。可手动添加模型。"];return;}
        NSMutableDictionary *updated=[current mutableCopy]?:[a mutableCopy];
        updated[@"models"]=models;
        XFReplaceAccount(updated);
        [self.tableView reloadData];if(self.changed)self.changed();
        [self alert:[NSString stringWithFormat:@"同步成功：%lu 个模型。点击返回，按类别浏览、选择使用。",(unsigned long)models.count]];
    }];
}
@end

@interface XFModelsController () <UISearchBarDelegate>
@property(nonatomic,strong) NSArray *sections;
@property(nonatomic,strong) NSDictionary *categoryModels;
@property(nonatomic,strong) UISearchBar *search;
@property(nonatomic,copy) NSString *term;
@end
@implementation XFModelsController
+ (NSDictionary *)activeProfile {return [self activeProfileForCapability:@"chat"];}
+ (NSDictionary *)activeProfileForCapability:(NSString *)capability {
    NSDictionary *selected=XFSelected(capability);
    if(!selected)return nil;
    NSDictionary *account=XFAccountForID(selected[@"account"]);
    if(!account)return nil;
    NSString *modelId=selected[@"model"];
    NSDictionary *model=nil;
    for(NSDictionary *m in account[@"models"])if([m[@"id"] isEqualToString:modelId]){model=m;break;}
    if(!model)return nil;
    NSString *endpoint=XFEndpoint(account,capability);
    NSString *legacy=account[@"legacy_endpoint"];
    if(legacy.length && [account[@"models"] count]==1)endpoint=legacy;
    return @{@"id":modelId,@"name":model[@"name"]?:modelId,@"model":modelId,
      @"provider":account[@"name"],@"endpoint":endpoint,@"capability":capability,
      @"account_id":account[@"id"]};
}
+ (NSString *)secretForProfile:(NSDictionary *)profile {
    return XFSecret(profile[@"account_id"]?:profile[@"id"]);
}
- (void)viewDidLoad {
    [super viewDidLoad];XFMigrate();self.title=@"选择模型";
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
      target:self action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"API 管理"
      style:UIBarButtonItemStylePlain target:self action:@selector(accountsTapped)];
    self.search=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,44)];
    self.search.placeholder=@"搜索模型 ID / 名称 / 服务";
    self.search.delegate=self;
    self.tableView.tableHeaderView=self.search;
    self.tableView.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero];
    [self refresh];
}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
    self.term=[text lowercaseString];[self refresh];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {[bar resignFirstResponder];}
- (void)closeTapped {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)accountsTapped {
    [self.search resignFirstResponder];
    XFAPIAccountsController *c=[[XFAPIAccountsController alloc] initWithStyle:UITableViewStyleGrouped];
    c.changed=^{[self refresh];};
    [self.navigationController pushViewController:c animated:YES];
}
- (void)refresh {
    NSMutableDictionary *grouped=[NSMutableDictionary dictionary];
    for(NSString *name in XFCategories())grouped[name]=[NSMutableArray array];
    for(NSDictionary *a in XFAccounts())for(NSDictionary *m in a[@"models"]){
        NSString *idText=m[@"id"]?:@"";
        NSString *name=m[@"name"]?:idText;
        NSString *text=[[NSString stringWithFormat:@"%@ %@ %@",idText,name,a[@"name"]] lowercaseString];
        if(self.term.length && [text rangeOfString:self.term].location==NSNotFound)continue;
        NSString *group=XFKind(m);
        [(NSMutableArray *)grouped[group] addObject:@{@"account":a,@"model":m}];
    }
    NSMutableArray *groups=[NSMutableArray array];
    for(NSString *name in XFCategories())if([grouped[name] count]) [groups addObject:name];
    self.sections=groups;self.categoryModels=grouped;
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return MAX((NSInteger)self.sections.count,1);}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if(!self.sections.count)return @"暂无模型：点击右上角「API 管理」添加服务";
    return [NSString stringWithFormat:@"%@（%lu）",self.sections[s],(unsigned long)[self.categoryModels[self.sections[s]] count]];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return self.sections.count?[self.categoryModels[self.sections[s]] count]:1;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell=[t dequeueReusableCellWithIdentifier:@"model"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"model"];
    if(!self.sections.count){
        cell.textLabel.text=@"请先添加 API 服务并同步模型";cell.detailTextLabel.text=@"支持自动获取模型列表";
        cell.accessoryType=UITableViewCellAccessoryNone;return cell;
    }
    NSDictionary *entry=self.categoryModels[self.sections[ip.section]][ip.row];
    NSDictionary *a=entry[@"account"],*m=entry[@"model"];
    NSString *category=self.sections[ip.section],*cap=XFCapability(category);
    NSDictionary *selected=XFSelected(cap);
    BOOL active=[selected[@"account"] isEqualToString:a[@"id"]] && [selected[@"model"] isEqualToString:m[@"id"]];
    cell.textLabel.text=m[@"name"]?:m[@"id"];
    cell.textLabel.font=[UIFont systemFontOfSize:15];
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",a[@"name"],m[@"id"]];
    cell.accessoryType=active?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryDetailButton;
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];if(!self.sections.count){[self accountsTapped];return;}
    NSDictionary *entry=self.categoryModels[self.sections[ip.section]][ip.row];
    NSString *category=self.sections[ip.section],*cap=XFCapability(category);
    if([cap isEqualToString:@"other"]){
        [self editCategoryForEntry:entry];
        return;
    }
    XFSelect(cap,entry[@"account"][@"id"],entry[@"model"][@"id"]);
    [self.tableView reloadData];self.title=@"已切换模型";
}
- (void)tableView:(UITableView *)t accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    if(!self.sections.count)return;
    NSDictionary *entry=self.categoryModels[self.sections[ip.section]][ip.row];
    [self editCategoryForEntry:entry];
}
- (void)editCategoryForEntry:(NSDictionary *)entry {
    NSDictionary *a=entry[@"account"],*m=entry[@"model"];
    UIAlertController *pick=[UIAlertController alertControllerWithTitle:m[@"id"] message:@"修改此模型的分类（优先使用手动分类）"
      preferredStyle:UIAlertControllerStyleAlert];
    for(NSString *category in XFCategories()){
        [pick addAction:[UIAlertAction actionWithTitle:category style:UIAlertActionStyleDefault handler:^(UIAlertAction *act){
            NSMutableDictionary *updated=[a mutableCopy];
            NSMutableArray *models=[a[@"models"] mutableCopy];
            for(NSUInteger i=0;i<models.count;i++)if([models[i][@"id"] isEqualToString:m[@"id"]]){
                NSMutableDictionary *new=[models[i] mutableCopy];
                new[@"user_category"]=category;models[i]=new;break;
            }
            updated[@"models"]=models;XFReplaceAccount(updated);[self refresh];
        }]];
    }
    [pick addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:pick animated:YES completion:nil];
}
@end
