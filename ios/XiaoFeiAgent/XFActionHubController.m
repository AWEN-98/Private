#import "XFActionHubController.h"
#import "XFTheme.h"

@interface XFActionHubCell : UITableViewCell
@property(nonatomic,strong) XFLineButton *glyph;
@property(nonatomic,strong) UILabel *heading;
@property(nonatomic,strong) UILabel *summary;
@end
@implementation XFActionHubCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if((self=[super initWithStyle:style reuseIdentifier:identifier])){
        self.backgroundColor=XFPaper();
        self.glyph=[[XFLineButton alloc] initWithSymbol:@"plus"];
        self.glyph.symbolColor=XFAccent();
        self.glyph.backgroundColor=[UIColor clearColor];
        self.glyph.layer.cornerRadius=11;
        self.glyph.userInteractionEnabled=NO;
        [self.contentView addSubview:self.glyph];
        self.heading=[[UILabel alloc] init];
        self.heading.font=[UIFont boldSystemFontOfSize:14.5];
        self.heading.textColor=XFInk();
        [self.contentView addSubview:self.heading];
        self.summary=[[UILabel alloc] init];
        self.summary.font=[UIFont systemFontOfSize:11.5];
        self.summary.textColor=XFSecondary();
        self.summary.lineBreakMode=NSLineBreakByTruncatingTail;
        [self.contentView addSubview:self.summary];
        self.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w=self.contentView.bounds.size.width;
    self.glyph.frame=CGRectMake(13,10,38,38);
    self.heading.frame=CGRectMake(62,8,MAX(1,w-79),22);
    self.summary.frame=CGRectMake(62,29,MAX(1,w-80),18);
}
@end

@interface XFActionHubController ()
@property(nonatomic,strong) NSArray *sections;
@end
@implementation XFActionHubController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"工具箱";
    XFApplyNavigation(self.navigationController);
    self.tableView.backgroundColor=XFCanvas();
    self.tableView.separatorColor=XFLine();
    self.tableView.rowHeight=59;
    self.tableView.sectionHeaderHeight=33;
    self.tableView.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"返回"
        style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    // title, short explanatory copy, action key, and vector icon.
    self.sections=@[
      @{@"title":@"快速开始",@"items":@[
        @[@"选择图片",@"从相册发图或让模型识图",@"photo",@"image"],
        @[@"语音助手",@"打开小斐语音终端",@"jarvis",@"mic"],
        @[@"录音转文字",@"说完后直接转换为文本",@"record",@"mic"],
        @[@"新对话",@"开启一个独立的会话",@"new",@"plus"]]},
      @{@"title":@"创作",@"items":@[
        @[@"生成图片",@"使用当前生图模型",@"image",@"spark"],
        @[@"导入文本",@"粘贴长篇内容参与对话",@"file",@"more"],
        @[@"提示词工具箱",@"模板、灵感和常用提示词",@"prompts",@"spark"],
        @[@"双模型对比",@"同一问题并行测试两个模型",@"compare",@"models"]]},
      @{@"title":@"实用工具",@"items":@[
        @[@"联网提问",@"通过已配置的联网模型搜索",@"web",@"search"],
        @[@"朗读回复",@"播报最近一条回答",@"tts",@"mic"],
        @[@"复制回复",@"复制最近一条回答内容",@"copyreply",@"more"],
        @[@"粘贴文字",@"从系统剪贴板导入",@"paste",@"plus"],
        @[@"生图协议",@"选择图片接口兼容模式",@"imagemode",@"image"],
        @[@"诊断中心",@"检查接口地址和请求错误",@"diagnostics",@"more"]]}
    ];
    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,52)];
    hint.numberOfLines=2;
    hint.font=[UIFont systemFontOfSize:12];
    hint.textColor=XFSecondary();
    hint.textAlignment=NSTextAlignmentCenter;
    hint.text=@"常用功能一次找到\n轻量原生工具，适配 iPhone 4S";
    self.tableView.tableHeaderView=hint;
}
- (void)close {[self dismissViewControllerAnimated:YES completion:nil];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t {return self.sections.count;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)section {
    return self.sections[(NSUInteger)section][@"title"];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section {
    return [self.sections[(NSUInteger)section][@"items"] count];
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)index {
    XFActionHubCell *c=[t dequeueReusableCellWithIdentifier:@"hub"];
    if(!c)c=[[XFActionHubCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"hub"];
    NSArray *entry=self.sections[(NSUInteger)index.section][@"items"][(NSUInteger)index.row];
    c.heading.text=entry[0];
    c.summary.text=entry[1];
    c.glyph.symbol=entry[3];
    c.accessibilityLabel=[NSString stringWithFormat:@"%@，%@",entry[0],entry[1]];
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)index {
    [t deselectRowAtIndexPath:index animated:YES];
    NSArray *entry=self.sections[(NSUInteger)index.section][@"items"][(NSUInteger)index.row];
    NSString *key=[entry[2] copy];
    void (^callback)(NSString *)=[self.onAction copy];
    [self dismissViewControllerAnimated:YES completion:^{if(callback)callback(key);}];
}
@end
