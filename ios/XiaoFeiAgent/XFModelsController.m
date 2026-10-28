#import "XFModelsController.h"
#import <Security/Security.h>
#import "XFModelProbe.h"


static UIColor *XFUIBackground(void) {return [UIColor colorWithRed:0.964 green:0.972 blue:0.986 alpha:1];}
static UIColor *XFUIAccent(void) {return [UIColor colorWithRed:0.32 green:0.38 blue:0.79 alpha:1];}
static UIColor *XFUIText(void) {return [UIColor colorWithRed:0.15 green:0.20 blue:0.31 alpha:1];}
static UIColor *XFUIHint(void) {return [UIColor colorWithRed:0.45 green:0.49 blue:0.58 alpha:1];}
static void XFStyleNav(UINavigationController *nav) {
    if(!nav)return;
    nav.navigationBar.translucent=NO;
    nav.navigationBar.barTintColor=[UIColor whiteColor];
    nav.navigationBar.tintColor=XFUIAccent();
    nav.navigationBar.titleTextAttributes=@{NSForegroundColorAttributeName:XFUIText(),
        NSFontAttributeName:[UIFont boldSystemFontOfSize:17]};
}

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
    t.text=label;t.font=[UIFont boldSystemFontOfSize:12.5];t.textColor=XFUIText();[self.scroll addSubview:t];
    UITextField *f=[[UITextField alloc] initWithFrame:CGRectMake(14,y+25,self.view.bounds.size.width-28,43)];
    f.autoresizingMask=UIViewAutoresizingFlexibleWidth;f.borderStyle=UITextBorderStyleNone;
    f.backgroundColor=[UIColor whiteColor];f.font=[UIFont systemFontOfSize:14];f.textColor=XFUIText();f.text=value;
    f.layer.cornerRadius=8;f.layer.borderWidth=0.5;
    f.layer.borderColor=[UIColor colorWithRed:0.86 green:0.89 blue:0.94 alpha:1].CGColor;
    UIView *pad=[[UIView alloc] initWithFrame:CGRectMake(0,0,10,10)];
    f.leftView=pad;f.leftViewMode=UITextFieldViewModeAlways;
    f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;
    f.delegate=self;f.returnKeyType=UIReturnKeyDone;[self.scroll addSubview:f];return f;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"API 服务配置";
    XFStyleNav(self.navigationController);
    self.view.backgroundColor=XFUIBackground();
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
    XFStyleNav(self.navigationController);
    self.tableView.backgroundColor=XFUIBackground();
    self.tableView.rowHeight=65;
    self.tableView.separatorColor=[UIColor colorWithRed:0.90 green:0.92 blue:0.95 alpha:1];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)];
    self.tableView.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {return XFAccounts().count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[t dequeueReusableCellWithIdentifier:@"account"];
    if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"account"];
    NSDictionary *a=XFAccounts()[ip.row];
    c.backgroundColor=[UIColor whiteColor];
    c.textLabel.text=a[@"name"];c.textLabel.font=[UIFont boldSystemFontOfSize:15.5];
    c.textLabel.textColor=XFUIText();
    c.detailTextLabel.text=[NSString stringWithFormat:@"%lu 个可用模型  ·  点击同步与编辑",(unsigned long)[a[@"models"] count]];
    c.detailTextLabel.font=[UIFont systemFontOfSize:12];
    c.detailTextLabel.textColor=XFUIHint();
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
            [XFModelProbe clearAccount:newAccount[@"id"]];
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
    NSDictionary *old=XFAccountForID(a[@"id"]);
    if(old && ![old[@"base"] isEqualToString:a[@"base"]]) [XFModelProbe clearAccount:a[@"id"]];
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


// Favorites are references to models, never copies of API credentials.
// Persist them independently so refreshing the provider's model list preserves favorites.
static NSString *const XFFavoriteKey=@"xf_model_favorites_v1";
static NSString *XFFavoriteID(NSDictionary *account,NSDictionary *model) {
    return [NSString stringWithFormat:@"%@|%@",account[@"id"]?:@"",model[@"id"]?:@""];
}
static NSSet *XFFavorites(void) {
    NSArray *saved=[[NSUserDefaults standardUserDefaults] arrayForKey:XFFavoriteKey];
    return [NSSet setWithArray:saved?:@[]];
}
static BOOL XFIsFavorite(NSDictionary *account,NSDictionary *model) {
    return [XFFavorites() containsObject:XFFavoriteID(account,model)];
}
static void XFSetFavorite(NSDictionary *account,NSDictionary *model,BOOL favorite) {
    NSMutableSet *all=[XFFavorites() mutableCopy];
    NSString *key=XFFavoriteID(account,model);
    if(favorite)[all addObject:key];else [all removeObject:key];
    [[NSUserDefaults standardUserDefaults] setObject:[[all allObjects] sortedArrayUsingSelector:@selector(compare:)] forKey:XFFavoriteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@interface XFModelsController () <UISearchBarDelegate>
@property(nonatomic,strong) UISearchBar *search;
@property(nonatomic,strong) UIView *filterPanel;
@property(nonatomic,strong) UIButton *providerButton;
@property(nonatomic,strong) UIButton *statusFilterButton;
@property(nonatomic,copy) NSString *selectedStatus;
@property(nonatomic,strong) UIScrollView *categoryScroll;
@property(nonatomic,strong) NSMutableArray *categoryButtons;
@property(nonatomic,copy) NSString *selectedCategory;
@property(nonatomic,copy) NSString *selectedProviderID;
@property(nonatomic,copy) NSString *term;
@property(nonatomic,strong) NSArray *visibleModels;
@property(nonatomic,strong) UIButton *probeButton;
@property(nonatomic,strong) NSMutableArray *probeQueue;
@property(nonatomic,assign) BOOL probeRunning;
@property(nonatomic,assign) BOOL probeStop;
@property(nonatomic,assign) NSUInteger probeIndex;
@property(nonatomic,assign) NSUInteger probeBatchRemaining;
@property(nonatomic,assign) NSUInteger probeBatchTotal;
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
+ (NSArray *)allChatProfiles {
    NSMutableArray *profiles=[NSMutableArray array];
    for(NSDictionary *account in XFAccounts()){
        for(NSDictionary *model in account[@"models"]){
            NSString *kind=XFKind(model);
            if(![@[@"文字对话",@"深度推理",@"图片理解"] containsObject:kind])continue;
            NSString *mid=model[@"id"];
            if(![mid isKindOfClass:[NSString class]] || !mid.length)continue;
            NSString *endpoint=XFEndpoint(account,@"chat");
            NSString *legacy=account[@"legacy_endpoint"];
            if(legacy.length && [account[@"models"] count]==1)endpoint=legacy;
            [profiles addObject:@{@"id":mid,@"model":mid,
                @"name":model[@"name"]?:mid,@"provider":account[@"name"]?:@"API",
                @"endpoint":endpoint,@"account_id":account[@"id"]}];
            if(profiles.count>=700)break;
        }
        if(profiles.count>=700)break;
    }
    [profiles sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return profiles;
}

- (NSArray *)filterCategories {
    return @[@"常用",@"全部",@"文字对话",@"深度推理",@"图片理解",@"图片生成",
       @"语音识别",@"语音朗读",@"联网搜索",@"其他模型"];
}
- (NSString *)shortCategoryName:(NSString *)name {
    NSDictionary *display=@{@"文字对话":@"对话",@"深度推理":@"推理",@"图片理解":@"视觉",
       @"图片生成":@"生图",@"语音识别":@"语音输入",@"语音朗读":@"语音输出",@"联网搜索":@"联网",
       @"其他模型":@"其他"};
    return display[name]?:name;
}
- (void)viewDidLoad {
    [super viewDidLoad];XFMigrate();
    self.title=@"模型库";
    XFStyleNav(self.navigationController);
    self.tableView.backgroundColor=XFUIBackground();
    self.tableView.separatorColor=[UIColor colorWithRed:0.90 green:0.92 blue:0.96 alpha:1];
    self.tableView.rowHeight=62;
    self.tableView.sectionHeaderHeight=27;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
      target:self action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"API 管理"
      style:UIBarButtonItemStylePlain target:self action:@selector(accountsTapped)];

    CGFloat width=self.view.bounds.size.width;
    self.filterPanel=[[UIView alloc] initWithFrame:CGRectMake(0,0,width,162)];
    self.filterPanel.backgroundColor=XFUIBackground();
    self.filterPanel.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.providerButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.providerButton.frame=CGRectMake(11,5,width-125,32);
    self.providerButton.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.providerButton.backgroundColor=[UIColor whiteColor];
    self.providerButton.layer.cornerRadius=8;
    self.providerButton.layer.borderWidth=0.5;
    self.providerButton.layer.borderColor=[UIColor colorWithWhite:0.86 alpha:1].CGColor;
    [self.providerButton setTitleColor:XFUIText() forState:UIControlStateNormal];
    self.providerButton.titleLabel.font=[UIFont boldSystemFontOfSize:12.5];
    [self.providerButton addTarget:self action:@selector(chooseProvider) forControlEvents:UIControlEventTouchUpInside];
    [self.filterPanel addSubview:self.providerButton];
    self.probeButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.probeButton.frame=CGRectMake(width-105,5,94,32);
    self.probeButton.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
    self.probeButton.backgroundColor=XFUIAccent();
    [self.probeButton setTitle:@"一键检测" forState:UIControlStateNormal];
    [self.probeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.probeButton.titleLabel.font=[UIFont boldSystemFontOfSize:12.5];
    self.probeButton.layer.cornerRadius=8;
    [self.probeButton addTarget:self action:@selector(testTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.filterPanel addSubview:self.probeButton];

    self.categoryScroll=[[UIScrollView alloc] initWithFrame:CGRectMake(0,42,width,39)];
    self.categoryScroll.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.categoryScroll.showsHorizontalScrollIndicator=NO;
    self.categoryScroll.alwaysBounceHorizontal=YES;
    [self.filterPanel addSubview:self.categoryScroll];
    self.categoryButtons=[NSMutableArray array];
    CGFloat x=11;
    NSArray *cats=[self filterCategories];
    for(NSUInteger index=0;index<cats.count;index++) {
        NSString *category=cats[index];
        NSString *label=[self shortCategoryName:category];
        CGFloat bw=MAX(52,MIN(85,label.length*14+21));
        UIButton *btn=[UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame=CGRectMake(x,2,bw,33);
        btn.tag=(NSInteger)index;
        btn.titleLabel.font=[UIFont systemFontOfSize:12.5];
        btn.layer.cornerRadius=8;
        [btn setTitle:label forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(categoryTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.categoryScroll addSubview:btn];
        [self.categoryButtons addObject:btn];
        x+=bw+7;
    }
    self.categoryScroll.contentSize=CGSizeMake(x+5,39);

    self.search=[[UISearchBar alloc] initWithFrame:CGRectMake(0,118,width,44)];
    self.search.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.search.placeholder=@"搜索模型名称、ID 或服务";
    self.search.tintColor=XFUIAccent();
    self.search.delegate=self;
    [self.filterPanel addSubview:self.search];
    self.statusFilterButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.statusFilterButton.frame=CGRectMake(11,83,width-22,31);
    self.statusFilterButton.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.statusFilterButton.backgroundColor=[UIColor whiteColor];
    self.statusFilterButton.layer.cornerRadius=8;
    self.statusFilterButton.layer.borderWidth=0.5;
    self.statusFilterButton.layer.borderColor=[UIColor colorWithWhite:0.86 alpha:1].CGColor;
    self.statusFilterButton.titleLabel.font=[UIFont boldSystemFontOfSize:12];
    [self.statusFilterButton setTitleColor:XFUIText() forState:UIControlStateNormal];
    [self.statusFilterButton addTarget:self action:@selector(filterStatusTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.filterPanel addSubview:self.statusFilterButton];
    self.tableView.tableHeaderView=self.filterPanel;
    self.tableView.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero];

    NSString *saved=[[NSUserDefaults standardUserDefaults] stringForKey:@"xf_model_last_filter"];
    self.selectedCategory=[[self filterCategories] containsObject:saved]?saved:@"全部";
    self.selectedStatus=@"all";
    [self refresh];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}
- (void)closeTapped {[self.search resignFirstResponder];[self dismissViewControllerAnimated:YES completion:nil];}
- (void)accountsTapped {
    [self.search resignFirstResponder];
    XFAPIAccountsController *controller=[[XFAPIAccountsController alloc] initWithStyle:UITableViewStyleGrouped];
    __weak XFModelsController *weakSelf=self;
    controller.changed=^{[weakSelf refresh];};
    [self.navigationController pushViewController:controller animated:YES];
}
- (void)categoryTapped:(UIButton *)sender {
    NSArray *options=[self filterCategories];
    if(sender.tag<0 || (NSUInteger)sender.tag>=options.count)return;
    [self.search resignFirstResponder];
    if(self.probeQueue && !self.probeRunning)[self.probeQueue removeAllObjects];
    self.selectedCategory=options[(NSUInteger)sender.tag];
    [[NSUserDefaults standardUserDefaults] setObject:self.selectedCategory forKey:@"xf_model_last_filter"];
    [self refresh];
}
- (void)updateFilterButtons {
    for(UIButton *button in self.categoryButtons){
        NSString *category=[self filterCategories][(NSUInteger)button.tag];
        BOOL on=[category isEqualToString:self.selectedCategory];
        button.backgroundColor=on?XFUIAccent():[UIColor whiteColor];
        [button setTitleColor:on?[UIColor whiteColor]:XFUIHint() forState:UIControlStateNormal];
        button.titleLabel.font=on?[UIFont boldSystemFontOfSize:12.5]:[UIFont systemFontOfSize:12.5];
    }
    NSString *name=@"全部 API 服务";
    if(self.selectedProviderID.length){
        NSDictionary *a=XFAccountForID(self.selectedProviderID);
        name=a[@"name"]?:@"全部 API 服务";
        if(!a)self.selectedProviderID=nil;
    }
    [self.providerButton setTitle:[NSString stringWithFormat:@"服务：%@  ▾",name] forState:UIControlStateNormal];
    [self.statusFilterButton setTitle:[NSString stringWithFormat:@"检测：%@  ▾",[self statusLabel:self.selectedStatus?:@"all"]] forState:UIControlStateNormal];
}
- (void)chooseProvider {
    [self.search resignFirstResponder];
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"筛选 API 服务"
      message:@"只显示所选服务下的模型" preferredStyle:UIAlertControllerStyleAlert];
    [menu addAction:[UIAlertAction actionWithTitle:@"全部服务" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act){
        if(self.probeQueue && !self.probeRunning)[self.probeQueue removeAllObjects];
        self.selectedProviderID=nil;[self refresh];
    }]];
    for(NSDictionary *account in XFAccounts()){
        NSString *aid=account[@"id"];
        [menu addAction:[UIAlertAction actionWithTitle:account[@"name"]?:@"未命名服务" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act){
            if(self.probeQueue && !self.probeRunning)[self.probeQueue removeAllObjects];
            self.selectedProviderID=aid;[self refresh];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
    self.term=[text lowercaseString];[self refresh];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {[bar resignFirstResponder];}
- (NSString *)statusLabel:(NSString *)status {
    NSDictionary *names=@{@"all":@"全部状态",@"ok":@"● 可用",@"bad":@"● 模型无效",
      @"unactivated":@"未开通",@"balance":@"余额不足",@"rate":@"限流",
      @"incompatible":@"接口不兼容",@"auth":@"鉴权失败",@"unknown":@"待确认",
      @"untested":@"未检测",@"notprobed":@"未验证"};
    return names[status]?:@"待确认";
}
- (void)filterStatusTapped {
    [self.search resignFirstResponder];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"筛选检测状态"
        message:@"账号、额度、接口和模型错误分开显示。测试结果不会永久有效。"
        preferredStyle:UIAlertControllerStyleAlert];
    for(NSString *status in @[@"all",@"ok",@"unactivated",@"balance",@"rate",@"incompatible",@"auth",@"bad",@"unknown",@"untested"]){
        [alert addAction:[UIAlertAction actionWithTitle:[self statusLabel:status]
          style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            self.selectedStatus=status;
            [self refresh];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)refresh {
    [self updateFilterButtons];
    NSString *category=self.selectedCategory?:@"全部";
    BOOL favoritesOnly=[category isEqualToString:@"常用"];
    BOOL all=[category isEqualToString:@"全部"];
    NSSet *favorites=XFFavorites();
    NSString *filter=self.selectedStatus?:@"all";
    NSMutableArray *matching=[NSMutableArray array];
    for(NSDictionary *account in XFAccounts()){
        if(self.selectedProviderID.length && ![self.selectedProviderID isEqualToString:account[@"id"]])continue;
        for(NSDictionary *model in account[@"models"]){
            if(![model isKindOfClass:[NSDictionary class]])continue;
            NSString *mid=model[@"id"];
            if(![mid isKindOfClass:[NSString class]] || !mid.length)continue;
            NSString *kind=XFKind(model);
            NSString *identifier=XFFavoriteID(account,model);
            BOOL favorite=[favorites containsObject:identifier];
            BOOL selected=NO;
            NSString *cap=XFCapability(kind);
            NSDictionary *current=XFSelected(cap);
            if([current[@"account"] isEqualToString:account[@"id"]] && [current[@"model"] isEqualToString:mid])
                selected=YES;
            if(favoritesOnly && !favorite && !selected)continue;
            if(!all && !favoritesOnly && ![category isEqualToString:kind])continue;
            NSString *name=[model[@"name"] isKindOfClass:[NSString class]]?model[@"name"]:mid;
            NSString *searchText=[[NSString stringWithFormat:@"%@ %@ %@",name,mid,account[@"name"]?:@""] lowercaseString];
            if(self.term.length && [searchText rangeOfString:self.term].location==NSNotFound)continue;
            NSDictionary *result=[XFModelProbe cachedForAccount:account model:model];
            NSString *status=result[@"status"]?:@"untested";
            if(![filter isEqualToString:@"all"] && ![filter isEqualToString:status])continue;
            [matching addObject:@{@"account":account,@"model":model,@"category":kind,
              @"favorite":@(favorite),@"active":@(selected),
              @"probe":result?:@{}}];
        }
    }
    [matching sortUsingComparator:^NSComparisonResult(NSDictionary *lhs,NSDictionary *rhs) {
        // Keep verified working models near the top, followed by untested and finally failed.
        NSString *ls=lhs[@"probe"][@"status"],*rs=rhs[@"probe"][@"status"];
        NSInteger lx=[ls isEqualToString:@"ok"]?0:([ls isEqualToString:@"bad"]?3:([ls isEqualToString:@"unactivated"]||[ls isEqualToString:@"balance"]?2:1));
        NSInteger rx=[rs isEqualToString:@"ok"]?0:([rs isEqualToString:@"bad"]?3:([rs isEqualToString:@"unactivated"]||[rs isEqualToString:@"balance"]?2:1));
        if(lx!=rx)return lx<rx?NSOrderedAscending:NSOrderedDescending;
        BOOL l=[lhs[@"favorite"] boolValue],r=[rhs[@"favorite"] boolValue];
        if(l!=r)return l?NSOrderedAscending:NSOrderedDescending;
        BOOL la=[lhs[@"active"] boolValue],ra=[rhs[@"active"] boolValue];
        if(la!=ra)return la?NSOrderedAscending:NSOrderedDescending;
        NSString *ln=lhs[@"model"][@"name"]?:lhs[@"model"][@"id"];
        NSString *rn=rhs[@"model"][@"name"]?:rhs[@"model"][@"id"];
        return [ln localizedCaseInsensitiveCompare:rn];
    }];
    self.visibleModels=matching;
    [self updateProbeButton];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {return 1;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)self.visibleModels.count,1);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if(!self.visibleModels.count)return @"没有符合筛选条件的模型";
    NSUInteger good=0,bad=0,unknown=0;
    for(NSDictionary *item in self.visibleModels){
        NSString *status=item[@"probe"][@"status"];
        if([status isEqualToString:@"ok"])good++;
        else if([status isEqualToString:@"bad"])bad++;
        else if(status.length)unknown++;
    }
    return [NSString stringWithFormat:@"%lu 个模型 · 可用 %lu · 不可用 %lu · 待确认 %lu",
      (unsigned long)self.visibleModels.count,(unsigned long)good,(unsigned long)bad,(unsigned long)unknown];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"model"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"model"];
    cell.backgroundColor=[UIColor whiteColor];
    cell.tintColor=XFUIAccent();
    cell.textLabel.font=[UIFont systemFontOfSize:14.5];
    cell.detailTextLabel.font=[UIFont systemFontOfSize:11.5];
    cell.detailTextLabel.textColor=XFUIHint();
    if(!self.visibleModels.count){
        cell.textLabel.text=XFAccounts().count?@"换个分类，或选择「全部」":@"先点击右上角添加 API 服务";
        cell.detailTextLabel.text=@"收藏常用模型后，可在「常用」快速切换";
        cell.accessoryType=UITableViewCellAccessoryNone;return cell;
    }
    NSDictionary *item=self.visibleModels[(NSUInteger)index.row];
    NSDictionary *model=item[@"model"],*account=item[@"account"];
    BOOL favorite=[item[@"favorite"] boolValue],active=[item[@"active"] boolValue];
    NSString *status=item[@"probe"][@"status"];
    BOOL passed=[status isEqualToString:@"ok"],failed=[status isEqualToString:@"bad"];

    BOOL probeCapable=[XFModelProbe canProbeCategory:item[@"category"]];
    NSString *state=[self statusLabel:status.length?status:(probeCapable?@"untested":@"notprobed")];
    NSString *name=model[@"name"]?:model[@"id"];
    cell.textLabel.text=[NSString stringWithFormat:@"%@%@%@",active?@"✓  ":@"",favorite?@"★  ":@"",name];
    cell.textLabel.textColor=failed?[UIColor colorWithWhite:0.70 alpha:1]:(active?XFUIAccent():XFUIText());
    cell.textLabel.font=active?[UIFont boldSystemFontOfSize:14.5]:[UIFont systemFontOfSize:14.5];
    NSNumber *latency=item[@"probe"][@"latency_ms"];
    NSString *speed=latency && [latency integerValue]>0 && passed?
        [NSString stringWithFormat:@" · %.1fs",[latency doubleValue]/1000.0]:@"";
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@%@ · %@ · %@",state,speed,account[@"name"]?:@"",
      [self shortCategoryName:item[@"category"]]];
    cell.detailTextLabel.textColor=passed?[UIColor colorWithRed:0.24 green:0.57 blue:0.40 alpha:1]:
      (failed?[UIColor colorWithWhite:0.73 alpha:1]:XFUIHint());
    cell.accessoryType=UITableViewCellAccessoryDetailButton;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES];
    if(!self.visibleModels.count){
        if(!XFAccounts().count)[self accountsTapped];
        else {self.selectedCategory=@"全部";[self refresh];}
        return;
    }
    NSDictionary *item=self.visibleModels[(NSUInteger)index.row];
    NSDictionary *account=item[@"account"],*model=item[@"model"];
    NSDictionary *probe=item[@"probe"];
    if([probe[@"status"] isEqualToString:@"bad"]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"暂不可用"
          message:[NSString stringWithFormat:@"上次检测：%@\n请检查模型名称或 API 服务。修复后可以重新检测。",
              probe[@"reason"]?:@"模型调用未通过"] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"返回" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"重新检测" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            [self testSingleItem:item];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSString *capability=XFCapability(item[@"category"]);
    if([capability isEqualToString:@"other"]){[self editCategoryForEntry:item];return;}
    XFSelect(capability,account[@"id"],model[@"id"]);
    // Vision chat models can also answer ordinary text questions.
    // Keep the main chat selector in sync when the user selects a vision model.
    if([capability isEqualToString:@"vision"]) XFSelect(@"chat",account[@"id"],model[@"id"]);
    [self refresh];
    self.title=@"已切换";
    // No success popup; return directly to chat after choosing a verified model.
    if([probe[@"status"] isEqualToString:@"ok"]) [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)index {
    if(self.visibleModels.count && (NSUInteger)index.row<self.visibleModels.count)
        [self manageModel:self.visibleModels[(NSUInteger)index.row]];
}
- (void)manageModel:(NSDictionary *)item {
    NSDictionary *account=item[@"account"],*model=item[@"model"];
    BOOL favorite=XFIsFavorite(account,model);
    NSString *name=model[@"name"]?:model[@"id"];
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:name
      message:[NSString stringWithFormat:@"%@\n当前分类：%@",account[@"name"]?:@"",item[@"category"]]
      preferredStyle:UIAlertControllerStyleAlert];
    [menu addAction:[UIAlertAction actionWithTitle:favorite?@"取消收藏":@"★ 加入常用"
      style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        XFSetFavorite(account,model,!favorite);[self refresh];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"检测这个模型" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self testSingleItem:item];
    }]];
    NSDictionary *record=item[@"probe"];
    NSNumber *latency=record[@"latency_ms"];
    if([latency integerValue]>0){
        [menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"测速：%.2f 秒 · 查看原因",[latency doubleValue]/1000.0]
         style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            NSString *detail=[NSString stringWithFormat:@"状态：%@\n响应耗时：%.2f 秒\n服务端信息：%@",
              [self statusLabel:record[@"status"]],[latency doubleValue]/1000.0,record[@"reason"]?:@""];
            UIAlertController *popup=[UIAlertController alertControllerWithTitle:@"模型检测详情" message:detail preferredStyle:UIAlertControllerStyleAlert];
            [popup addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:popup animated:YES completion:nil];
        }]];
    }
    if([record[@"reason"] length]){
        [menu addAction:[UIAlertAction actionWithTitle:@"查看检测原因" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            UIAlertController *details=[UIAlertController alertControllerWithTitle:@"检测详情"
               message:record[@"reason"] preferredStyle:UIAlertControllerStyleAlert];
            [details addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:details animated:YES completion:nil];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"修改分类" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        [self editCategoryForEntry:item];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)editCategoryForEntry:(NSDictionary *)entry {
    NSDictionary *account=entry[@"account"],*model=entry[@"model"];
    UIAlertController *picker=[UIAlertController alertControllerWithTitle:model[@"id"]
        message:@"自动分类仅供参考，手动分类会在同步后保留"
        preferredStyle:UIAlertControllerStyleAlert];
    for(NSString *category in XFCategories()){
        [picker addAction:[UIAlertAction actionWithTitle:category style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            // Read latest account data to avoid overwriting a newer model sync.
            NSDictionary *latest=XFAccountForID(account[@"id"]);
            NSMutableDictionary *changed=[latest mutableCopy]?:[account mutableCopy];
            NSMutableArray *models=[changed[@"models"] mutableCopy]?:[NSMutableArray array];
            for(NSUInteger i=0;i<models.count;i++){
                NSDictionary *old=models[i];
                if([old[@"id"] isEqualToString:model[@"id"]]){
                    NSMutableDictionary *updatedModel=[old mutableCopy];
                    updatedModel[@"user_category"]=category;
                    models[i]=updatedModel;break;
                }
            }
            changed[@"models"]=models;
            XFReplaceAccount(changed);
            [self refresh];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)updateProbeButton {
    if(!self.probeButton)return;
    NSString *label=@"一键检测";
    if(self.probeRunning){
        label=[NSString stringWithFormat:@"停止 %lu/%lu",(unsigned long)self.probeIndex,(unsigned long)self.probeBatchTotal];
    } else if(self.probeQueue.count) {
        label=@"继续检测";
    }
    [self.probeButton setTitle:label forState:UIControlStateNormal];
}
- (void)testTapped {
    if(self.probeRunning){
        self.probeStop=YES;
        [self.probeButton setTitle:@"正在停止…" forState:UIControlStateNormal];
        return;
    }
    if(!self.probeQueue.count) {
        self.probeQueue=[NSMutableArray array];
        for(NSDictionary *item in self.visibleModels) {
            if([XFModelProbe canProbeCategory:item[@"category"]]) [self.probeQueue addObject:item];
        }
    }
    if(!self.probeQueue.count){
        UIAlertController *info=[UIAlertController alertControllerWithTitle:@"此分类暂不支持低成本检测"
           message:@"一键检测目前验证对话、推理和视觉模型的文字调用。生图、音频等可能额外收费，暂不会自动请求；未测模型不会置灰。"
           preferredStyle:UIAlertControllerStyleAlert];
        [info addAction:[UIAlertAction actionWithTitle:@"了解" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:info animated:YES completion:nil];return;
    }
    NSUInteger total=MIN((NSUInteger)12,self.probeQueue.count);
    NSString *message=[NSString stringWithFormat:
      @"将检测当前筛选中的 %lu 个模型（本批 %lu 个），逐个发送一次极短文字请求。每次调用可能产生 API 费用。网络错误和限流只标为「待确认」，不会直接置灰。\\n\\n生图和语音暂不自动测试。",
      (unsigned long)self.probeQueue.count,(unsigned long)total];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"确认开始模型检测？"
       message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"开始检测" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        self.probeRunning=YES;self.probeStop=NO;self.probeIndex=0;
        self.probeBatchRemaining=total;self.probeBatchTotal=total;
        [self updateProbeButton];
        [self probeNext];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)testSingleItem:(NSDictionary *)item {
    if(![XFModelProbe canProbeCategory:item[@"category"]]){
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"尚不支持此类检测"
           message:@"图片生成、录音识别或语音合成的真实调用可能收费，本版一键检测只支持聊天类接口。"
           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];return;
    }
    if(self.probeRunning)return;
    self.probeQueue=[NSMutableArray arrayWithObject:item];
    [self testTapped];
}
- (void)probeNext {
    if(!self.probeRunning)return;
    if(self.probeStop || self.probeBatchRemaining==0 || self.probeQueue.count==0) {
        self.probeRunning=NO;
        self.probeStop=NO;
        self.probeBatchRemaining=0;
        [self updateProbeButton];
        [self refresh];
        return;
    }
    NSDictionary *item=self.probeQueue[0];
    [self.probeQueue removeObjectAtIndex:0];
    NSDictionary *account=item[@"account"],*model=item[@"model"];
    NSString *secret=XFSecret(account[@"id"]);
    self.probeIndex++;
    self.probeBatchRemaining--;
    [self updateProbeButton];
    __weak XFModelsController *weakSelf=self;
    [XFModelProbe probeAccount:account model:model apiKey:secret completion:^(NSDictionary *result){
        XFModelsController *controller=weakSelf;
        if(!controller)return;
        [controller refresh];
        [controller probeNext];
    }];
}

@end
