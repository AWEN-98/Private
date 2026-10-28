#import "XFCompareController.h"
#import "XFModelsController.h"
#import <QuartzCore/QuartzCore.h>

@interface XFComparePicker : UITableViewController <UISearchBarDelegate>
@property(nonatomic,strong) NSArray *all;
@property(nonatomic,strong) NSArray *filtered;
@property(nonatomic,strong) UISearchBar *search;
@property(nonatomic,copy) void (^onSelect)(NSDictionary *profile);
@end
@implementation XFComparePicker
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"选择对比模型";
    self.all=[XFModelsController allChatProfiles];
    self.filtered=self.all;
    self.search=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,44)];
    self.search.delegate=self;self.search.placeholder=@"搜索模型 / 服务";
    self.tableView.tableHeaderView=self.search;
    self.tableView.rowHeight=60;
    self.tableView.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero];
}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
    if(!text.length){self.filtered=self.all;}
    else {
        NSString *needle=[text lowercaseString];
        self.filtered=[self.all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *p,NSDictionary *b){
            NSString *hay=[[NSString stringWithFormat:@"%@ %@ %@",p[@"name"],p[@"model"],p[@"provider"]] lowercaseString];
            return [hay rangeOfString:needle].location!=NSNotFound;
        }]];
    }
    [self.tableView reloadData];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {[bar resignFirstResponder];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return self.filtered.count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell=[t dequeueReusableCellWithIdentifier:@"compare"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"compare"];
    NSDictionary *p=self.filtered[(NSUInteger)ip.row];
    cell.textLabel.text=p[@"name"];
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",p[@"provider"],p[@"model"]];
    cell.textLabel.font=[UIFont systemFontOfSize:14.5];
    cell.detailTextLabel.font=[UIFont systemFontOfSize:11.5];
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if(self.onSelect)self.onSelect(self.filtered[(NSUInteger)ip.row]);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface XFCompareController () <UITextViewDelegate>
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIButton *modelAButton;
@property(nonatomic,strong) UIButton *modelBButton;
@property(nonatomic,strong) UIButton *compareButton;
@property(nonatomic,strong) UITextView *question;
@property(nonatomic,strong) UITextView *resultA;
@property(nonatomic,strong) UITextView *resultB;
@property(nonatomic,strong) UILabel *headA;
@property(nonatomic,strong) UILabel *headB;
@property(nonatomic,strong) UILabel *hint;
@property(nonatomic,strong) NSDictionary *profileA;
@property(nonatomic,strong) NSDictionary *profileB;
@property(nonatomic,assign) BOOL busy;
@property(nonatomic,assign) NSInteger outstanding;
@end

@implementation XFCompareController
- (UIColor *)accent {return [UIColor colorWithRed:.32 green:.38 blue:.79 alpha:1];}
- (UIButton *)buttonWithTitle:(NSString *)title selector:(SEL)selector {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.backgroundColor=[UIColor whiteColor];b.layer.cornerRadius=8;
    b.titleLabel.font=[UIFont systemFontOfSize:13];
    [b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:b];
    return b;
}
- (UITextView *)textArea:(NSString *)text {
    UITextView *view=[[UITextView alloc] init];
    view.font=[UIFont systemFontOfSize:14];view.text=text;
    view.backgroundColor=[UIColor whiteColor];view.layer.cornerRadius=8;
    [self.scroll addSubview:view];return view;
}
- (UILabel *)label:(NSString *)text {
    UILabel *label=[[UILabel alloc] init];
    label.text=text;label.font=[UIFont boldSystemFontOfSize:13];
    label.textColor=[UIColor colorWithRed:.17 green:.21 blue:.31 alpha:1];
    label.numberOfLines=1;[self.scroll addSubview:label];return label;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"双模型对比";
    self.view.backgroundColor=[UIColor colorWithRed:.96 green:.97 blue:.99 alpha:1];
    self.scroll=[[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.scroll.alwaysBounceVertical=YES;[self.view addSubview:self.scroll];
    self.modelAButton=[self buttonWithTitle:@"选择模型 A" selector:@selector(pickA)];
    self.modelBButton=[self buttonWithTitle:@"选择模型 B" selector:@selector(pickB)];
    self.question=[self textArea:self.initialPrompt?:@""];self.question.delegate=self;
    self.compareButton=[self buttonWithTitle:@"开始对比（调用两次 API）" selector:@selector(compare)];
    self.compareButton.backgroundColor=[self accent];
    [self.compareButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.hint=[self label:@"相同问题，两份独立回答；每次可能产生两笔费用"];
    self.hint.textColor=[UIColor grayColor];self.hint.font=[UIFont systemFontOfSize:11.5];
    self.headA=[self label:@"模型 A"];
    self.resultA=[self textArea:@"等待回答…"];self.resultA.editable=NO;
    self.headB=[self label:@"模型 B"];
    self.resultB=[self textArea:@"等待回答…"];self.resultB.editable=NO;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"收起键盘" style:UIBarButtonItemStylePlain target:self action:@selector(hideKeyboard)];
    NSArray *models=[XFModelsController allChatProfiles];
    self.profileA=[XFModelsController activeProfile];
    if(!self.profileA && models.count)self.profileA=models[0];
    for(NSDictionary *p in models) {
        if(!self.profileA || !([p[@"account_id"] isEqualToString:self.profileA[@"account_id"]]&&
            [p[@"model"] isEqualToString:self.profileA[@"model"]])){
            self.profileB=p;break;
        }
    }
    [self updateButtons];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardShown:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
}
- (void)dealloc {[[NSNotificationCenter defaultCenter] removeObserver:self];}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w=self.view.bounds.size.width,ww=w-24;
    self.modelAButton.frame=CGRectMake(12,13,(ww-8)/2,39);
    self.modelBButton.frame=CGRectMake(20+(ww-8)/2,13,(ww-8)/2,39);
    self.question.frame=CGRectMake(12,61,ww,100);
    self.compareButton.frame=CGRectMake(12,170,ww,42);
    self.hint.frame=CGRectMake(12,216,ww,27);
    self.headA.frame=CGRectMake(12,252,ww,25);
    self.resultA.frame=CGRectMake(12,280,ww,142);
    self.headB.frame=CGRectMake(12,432,ww,25);
    self.resultB.frame=CGRectMake(12,460,ww,142);
    self.scroll.contentSize=CGSizeMake(w,620);
}
- (void)keyboardShown:(NSNotification *)notification {
    CGRect keyboard=[self.view convertRect:[notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat cover=MAX(0,CGRectGetMaxY(self.view.bounds)-CGRectGetMinY(keyboard));
    self.scroll.contentInset=UIEdgeInsetsMake(0,0,cover+12,0);
    self.scroll.scrollIndicatorInsets=self.scroll.contentInset;
}
- (void)keyboardHidden:(NSNotification *)notification {
    self.scroll.contentInset=UIEdgeInsetsZero;
    self.scroll.scrollIndicatorInsets=UIEdgeInsetsZero;
}
- (void)hideKeyboard {[self.question resignFirstResponder];}
- (void)updateButtons {
    NSString *a=self.profileA[@"name"]?:@"选择模型 A";
    NSString *b=self.profileB[@"name"]?:@"选择模型 B";
    if(a.length>15)a=[[a substringToIndex:15] stringByAppendingString:@"…"];
    if(b.length>15)b=[[b substringToIndex:15] stringByAppendingString:@"…"];
    [self.modelAButton setTitle:[@"A: " stringByAppendingString:a] forState:UIControlStateNormal];
    [self.modelBButton setTitle:[@"B: " stringByAppendingString:b] forState:UIControlStateNormal];
}
- (void)pickA {[self pickFirst:YES];}
- (void)pickB {[self pickFirst:NO];}
- (void)pickFirst:(BOOL)first {
    if(self.busy)return;
    XFComparePicker *picker=[[XFComparePicker alloc] initWithStyle:UITableViewStylePlain];
    __weak XFCompareController *weakSelf=self;
    picker.onSelect=^(NSDictionary *profile){
        if(first)weakSelf.profileA=profile;else weakSelf.profileB=profile;
        [weakSelf updateButtons];
    };
    [self.navigationController pushViewController:picker animated:YES];
}
- (void)alert:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"双模型对比" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)compare {
    if(self.busy)return;
    NSString *question=[self.question.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!question.length){[self alert:@"先输入一个问题"];return;}
    if(question.length>3500){[self alert:@"问题太长，请控制在 3500 字以内"];return;}
    if(!self.profileA || !self.profileB){[self alert:@"至少需要在 API 管理中添加两个聊天模型"];return;}
    if([self.profileA[@"account_id"] isEqualToString:self.profileB[@"account_id"]] &&
       [self.profileA[@"model"] isEqualToString:self.profileB[@"model"]]){
        [self alert:@"请选择两个不同的模型"];return;
    }
    [self hideKeyboard];
    self.busy=YES;self.outstanding=2;self.compareButton.enabled=NO;
    self.hint.text=@"对比进行中…";
    self.resultA.text=@"请求模型 A…";self.resultB.text=@"请求模型 B…";
    [self request:self.profileA question:question result:self.resultA heading:self.headA];
    [self request:self.profileB question:question result:self.resultB heading:self.headB];
}
- (void)request:(NSDictionary *)profile question:(NSString *)question result:(UITextView *)result heading:(UILabel *)heading {
    NSString *key=[XFModelsController secretForProfile:profile];
    NSURL *url=[NSURL URLWithString:profile[@"endpoint"]];
    if(!key.length || ![[url scheme] isEqualToString:@"https"] || !url.host.length){
        result.text=@"未配置有效 API Key 或 HTTPS 接口。";
        [self finishedOne];return;
    }
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:90];
    req.HTTPMethod=@"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"model":profile[@"model"],
        @"messages":@[@{@"role":@"user",@"content":question}],@"stream":@NO} options:0 error:NULL];
    CFAbsoluteTime started=CFAbsoluteTimeGetCurrent();
    __weak XFCompareController *weakSelf=self;
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:
        ^(NSURLResponse *response,NSData *data,NSError *error) {
        XFCompareController *controller=weakSelf;
        if(!controller)return;
        NSTimeInterval seconds=CFAbsoluteTimeGetCurrent()-started;
        NSInteger http=[response isKindOfClass:[NSHTTPURLResponse class]]?[(NSHTTPURLResponse *)response statusCode]:0;
        NSString *output=nil;
        if(error)output=[NSString stringWithFormat:@"连接失败 %ld",(long)error.code];
        else if(data.length>512*1024)output=@"回答过大，已停止解析";
        else {
            id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if(http>=200 && http<300 && [json isKindOfClass:[NSDictionary class]]) {
                NSArray *choices=json[@"choices"];
                if([choices isKindOfClass:[NSArray class]] && choices.count){
                    NSDictionary *entry=choices[0];
                    NSDictionary *message=[entry[@"message"] isKindOfClass:[NSDictionary class]]?entry[@"message"]:@{};
                    if([message[@"content"] isKindOfClass:[NSString class]])output=message[@"content"];
                }
            }
            if(!output.length) {
                NSDictionary *err=[json isKindOfClass:[NSDictionary class]]?json[@"error"]:nil;
                NSString *reason=[err isKindOfClass:[NSDictionary class]]?err[@"message"]:nil;
                if(![reason isKindOfClass:[NSString class]])reason=@"该模型未返回兼容的对话内容";
                if(reason.length>250)reason=[reason substringToIndex:250];
                if(key.length)reason=[reason stringByReplacingOccurrencesOfString:key withString:@"[密钥已隐藏]"];
                output=[NSString stringWithFormat:@"HTTP %ld：%@",(long)http,reason];
            }
        }
        if(output.length>12000)output=[[output substringToIndex:12000] stringByAppendingString:@"…"];
        result.text=output?:@"空回复";
        heading.text=[NSString stringWithFormat:@"%@ · %.2f秒",profile[@"name"]?:@"模型",seconds];
        [controller finishedOne];
    }];
}
- (void)finishedOne {
    self.outstanding--;
    if(self.outstanding<=0){
        self.busy=NO;self.compareButton.enabled=YES;
        self.hint.text=@"对比完成 · 可以修改问题再次调用";
    }
}
@end
