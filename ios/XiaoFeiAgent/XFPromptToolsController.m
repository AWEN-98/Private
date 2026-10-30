#import "XFPromptToolsController.h"
#import "XFTheme.h"
#import <QuartzCore/QuartzCore.h>
static NSString *const XFCustomPrompts=@"xf_prompt_templates_v1";

@interface XFPromptEditor : UIViewController
@property(nonatomic,copy) NSString *promptTitle;
@property(nonatomic,copy) NSString *promptText;
@property(nonatomic,strong) UITextView *editor;
@property(nonatomic,copy) void (^onUse)(NSString *text);
@property(nonatomic,copy) void (^onSave)(NSString *text);
@end
@implementation XFPromptEditor
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=self.promptTitle?:@"提示词";
    self.view.backgroundColor=XFCanvas();
    XFApplyNavigation(self.navigationController);
    self.editor=[[UITextView alloc] init];
    self.editor.font=[UIFont systemFontOfSize:15];
    XFCard(self.editor,12);
    self.editor.textColor=XFInk();
    self.editor.text=self.promptText?:@"";
    self.editor.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.editor];
    NSArray *titles=@[@"填入聊天",@"复制",@"保存模板"];
    for(NSInteger i=0;i<3;i++){
        UIButton *btn=[UIButton buttonWithType:UIButtonTypeSystem];
        btn.tag=i;btn.titleLabel.font=[UIFont boldSystemFontOfSize:13];
        [btn setTitle:titles[(NSUInteger)i] forState:UIControlStateNormal];
        if(i==0){btn.backgroundColor=XFAccent();[btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];}
        else {btn.backgroundColor=XFAccentPale();[btn setTitleColor:XFAccent() forState:UIControlStateNormal];}
        btn.layer.cornerRadius=11;
        [btn addTarget:self action:@selector(action:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:btn];
    }
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"收起键盘" style:UIBarButtonItemStylePlain target:self action:@selector(hideKeyboard)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardShown:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
}
- (void)dealloc {[[NSNotificationCenter defaultCenter] removeObserver:self];}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    self.editor.frame=CGRectMake(10,10,w-20,MAX(80,h-73));
    for(UIView *view in self.view.subviews){
        if(![view isKindOfClass:[UIButton class]])continue;
        UIButton *b=(UIButton *)view;
        CGFloat available=w-20,space=5,bw=(available-2*space)/3;
        b.frame=CGRectMake(10+b.tag*(bw+space),h-53,bw,43);
    }
}
- (void)keyboardShown:(NSNotification *)n {
    CGRect k=[self.view convertRect:[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat covered=MAX(0,CGRectGetMaxY(self.view.bounds)-CGRectGetMinY(k));
    self.editor.contentInset=UIEdgeInsetsMake(0,0,covered+12,0);
    self.editor.scrollIndicatorInsets=self.editor.contentInset;
}
- (void)keyboardHidden:(NSNotification *)n {self.editor.contentInset=UIEdgeInsetsZero;self.editor.scrollIndicatorInsets=UIEdgeInsetsZero;}
- (void)hideKeyboard {[self.editor resignFirstResponder];}
- (void)action:(UIButton *)button {
    NSString *text=[self.editor.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!text.length)return;
    if(text.length>10000)text=[text substringToIndex:10000];
    [self.editor resignFirstResponder];
    if(button.tag==0){if(self.onUse)self.onUse(text);}
    else if(button.tag==1){[UIPasteboard generalPasteboard].string=text;self.title=@"已复制提示词";}
    else {if(self.onSave)self.onSave(text);}
}
@end

@interface XFPromptToolsController ()
@property(nonatomic,strong) NSMutableArray *custom;
@property(nonatomic,strong) NSArray *builtins;
@end
@implementation XFPromptToolsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"提示词";
    XFApplyNavigation(self.navigationController);
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addCustom)];
    self.tableView.rowHeight=57;
    self.tableView.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero];
    self.tableView.backgroundColor=XFCanvas();
    self.tableView.separatorColor=XFLine();
    self.builtins=@[
        @{@"title":@"AI 生图提示词",@"category":@"视觉创作",@"text":@"请把以下主题写成适合 AI 生图的完整中文提示词，重点描述主体、外貌、服装、姿态、机位、场景、光影、材质、构图，语言清晰可直接复制。主题：{填写主题}"},
        @{@"title":@"CG 角色设计",@"category":@"视觉创作",@"text":@"设计一个完整的高品质 CG 角色。写出角色定位、剪影、形体语言、重心姿态、服饰层级、材质 CMF、色彩比例、关键装备和角色叙事。不要堆无意义装饰。角色主题：{填写主题}"},
        @{@"title":@"Seedance 分镜",@"category":@"影视创作",@"text":@"把以下故事改写为15秒电影级视频分镜：镜头数量精简，写清景别、机位、主体动作、环境风场、光影、声音和连续性。保持非居中构图和明确的视觉冲击。故事：{填写故事}"},
        @{@"title":@"短片故事构思",@"category":@"影视创作",@"text":@"请围绕主题创作一个适合3至10分钟短片的故事，给出一句话卖点、人物目标、反差、冲突升级、情感转折、结尾余味和五个关键画面。主题：{填写主题}"},
        @{@"title":@"图片反推提示词",@"category":@"视觉创作",@"text":@"请分析我提供的图片，输出可用于 AI 生图的短词提示词，覆盖人物、服装、机位、构图、场景、光线和摄影质感；不要加入图中看不到的细节。"},
        @{@"title":@"中文文案润色",@"category":@"日常办公",@"text":@"请改写以下文字，保留真实含义，语言更自然简洁，不要套话；提供完成稿并简要说明改动。原文：{粘贴文字}"},
        @{@"title":@"中英双向翻译",@"category":@"日常办公",@"text":@"请将以下内容自然、准确地翻译为另一种语言。保留语气和专有名词；只输出译文。内容：{粘贴文字}"},
        @{@"title":@"问题深度分析",@"category":@"推理研究",@"text":@"请分析以下问题，先明确目标与信息缺口，再区分事实、假设与不确定性，提出3种可行方案及优缺点，给出最可执行的建议。问题：{填写问题}"},
        @{@"title":@"学习讲解",@"category":@"推理研究",@"text":@"请像老师一样循序渐进地讲解这个概念，先用通俗比喻，再给出一个真实例子、常见误区和练习题。概念：{填写概念}"},
        @{@"title":@"代码助手",@"category":@"技术开发",@"text":@"请检查以下代码或开发需求，定位原因，给出最小修复补丁、完整可运行示例和验证步骤。说明兼容性风险。需求或代码：{粘贴内容}"}
    ];
    self.custom=[[[NSUserDefaults standardUserDefaults] arrayForKey:XFCustomPrompts] mutableCopy]?:[NSMutableArray array];
}
- (void)close {[self dismissViewControllerAnimated:YES completion:nil];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t {return 2;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {return s==0?@"内置模板 · 点击后可以修改":@"我的模板 · 右上角添加";}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {return s==0?self.builtins.count:self.custom.count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[t dequeueReusableCellWithIdentifier:@"template"];
    if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"template"];
    NSDictionary *item=ip.section==0?self.builtins[(NSUInteger)ip.row]:self.custom[(NSUInteger)ip.row];
    c.backgroundColor=XFPaper();
    c.textLabel.textColor=XFInk();
    c.detailTextLabel.textColor=XFSecondary();
    c.textLabel.text=item[@"title"];
    c.textLabel.font=[UIFont boldSystemFontOfSize:14.5];
    c.detailTextLabel.text=item[@"category"]?:@"自定义";
    c.detailTextLabel.font=[UIFont systemFontOfSize:11.5];
    c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *item=ip.section==0?self.builtins[(NSUInteger)ip.row]:self.custom[(NSUInteger)ip.row];
    [self openEditor:item];
}
- (void)openEditor:(NSDictionary *)item {
    XFPromptEditor *editor=[[XFPromptEditor alloc] init];
    editor.promptTitle=item[@"title"];
    editor.promptText=item[@"text"];
    __weak XFPromptToolsController *weakSelf=self;
    __weak XFPromptEditor *weakEditor=editor;
    editor.onUse=^(NSString *text){
        if(weakSelf.onUsePrompt)weakSelf.onUsePrompt(text);
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    };
    editor.onSave=^(NSString *text){
        [weakSelf saveTemplateWithTitle:item[@"title"] text:text];
        weakEditor.title=@"模板已保存";
    };
    [self.navigationController pushViewController:editor animated:YES];
}
- (void)saveTemplateWithTitle:(NSString *)title text:(NSString *)text {
    if(!title.length || !text.length)return;
    NSIndexSet *matches=[self.custom indexesOfObjectsPassingTest:^BOOL(NSDictionary *p,NSUInteger i,BOOL *stop){
        return [p[@"title"] isEqualToString:title];
    }];
    [self.custom removeObjectsAtIndexes:matches];
    [self.custom insertObject:@{@"title":title,@"text":text,@"category":@"自定义"} atIndex:0];
    while(self.custom.count>80)[self.custom removeLastObject];
    [[NSUserDefaults standardUserDefaults] setObject:self.custom forKey:XFCustomPrompts];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self.tableView reloadData];
}
- (void)addCustom {
    UIAlertController *prompt=[UIAlertController alertControllerWithTitle:@"新建提示词"
        message:@"先输入模板名称，再编辑内容" preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"模板名称";}];
    [prompt addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [prompt addAction:[UIAlertAction actionWithTitle:@"编辑内容" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSString *name=[prompt.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if(!name.length)return;
        [self openEditor:@{@"title":name,@"text":@"请在这里填写提示词…"}];
    }]];
    [self presentViewController:prompt animated:YES completion:nil];
}
- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip {return ip.section==1;}
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if(ip.section!=1 || style!=UITableViewCellEditingStyleDelete)return;
    [self.custom removeObjectAtIndex:(NSUInteger)ip.row];
    [[NSUserDefaults standardUserDefaults] setObject:self.custom forKey:XFCustomPrompts];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self.tableView reloadData];
}
@end
