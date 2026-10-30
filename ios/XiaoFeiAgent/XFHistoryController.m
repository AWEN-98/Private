#import "XFHistoryController.h"
#import "XFChatStore.h"
#import "XFTheme.h"
@interface XFHistoryController () <UISearchBarDelegate>
@property(nonatomic,strong) NSMutableArray *items;
@property(nonatomic,strong) NSArray *allItems;
@property(nonatomic,strong) UISearchBar *searchBar;
@end
@implementation XFHistoryController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"会话";
    self.tableView.rowHeight=66;
    self.tableView.backgroundColor=XFCanvas();
    self.tableView.separatorColor=XFLine();
    self.tableView.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero];
    XFApplyNavigation(self.navigationController);
    self.searchBar=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,52)];
    self.searchBar.searchBarStyle=UISearchBarStyleMinimal;
    self.searchBar.placeholder=@"搜索历史会话";
    self.searchBar.tintColor=XFAccent();
    self.searchBar.delegate=self;
    self.tableView.tableHeaderView=self.searchBar;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(newTapped)];
    [self reload];
}
- (void)reload {
    self.allItems=[XFChatStore conversations];
    NSString *term=[[self.searchBar.text?:@"" lowercaseString] stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.items=[NSMutableArray array];
    for(NSDictionary *item in self.allItems){
        NSString *title=[item[@"title"] isKindOfClass:[NSString class]]?item[@"title"]:@"";
        if(!term.length || [[title lowercaseString] rangeOfString:term].location!=NSNotFound)
            [self.items addObject:item];
    }
    [self.tableView reloadData];
}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {[self reload];}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {[bar resignFirstResponder];}
- (void)doneTapped {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)newTapped {
    NSString *cid=[XFChatStore createConversation];
    if(self.onChoose) self.onChoose(cid);
    [self doneTapped];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)self.items.count,1);
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell=[t dequeueReusableCellWithIdentifier:@"history"];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"history"];
    if(!self.items.count){
        cell.textLabel.text=@"还没有匹配的会话";
        cell.detailTextLabel.text=@"尝试其他关键词，或创建一个新对话";
        cell.textLabel.textColor=XFSecondary();
        cell.accessoryType=UITableViewCellAccessoryNone;
        return cell;
    }
    NSDictionary *item=self.items[(NSUInteger)ip.row];
    cell.backgroundColor=XFPaper();
    cell.tintColor=XFAccent();
    cell.textLabel.text=item[@"title"]?:@"新对话";
    cell.textLabel.font=[UIFont boldSystemFontOfSize:15];
    cell.textLabel.textColor=XFInk();
    NSDate *date=[NSDate dateWithTimeIntervalSince1970:[item[@"updated"] doubleValue]];
    cell.detailTextLabel.text=[NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
    cell.detailTextLabel.font=[UIFont systemFontOfSize:12];
    cell.detailTextLabel.textColor=XFSecondary();
    cell.accessoryType=UITableViewCellAccessoryDetailButton;
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if(!self.items.count)return;
    if(self.onChoose) self.onChoose(self.items[ip.row][@"id"]);
    [self doneTapped];
}
- (void)tableView:(UITableView *)t accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    if(!self.items.count)return;
    NSString *cid=self.items[ip.row][@"id"];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"重命名对话" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=self.items[ip.row][@"title"];}];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        [XFChatStore renameConversationID:cid title:alert.textFields[0].text];[self reload];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip {return self.items.count>0;}
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if(style!=UITableViewCellEditingStyleDelete || !self.items.count)return;
    NSString *cid=self.items[(NSUInteger)ip.row][@"id"];
    UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"删除这段对话？"
        message:@"删除后无法恢复，其他会话不会受到影响。"
        preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        [XFChatStore deleteConversationID:cid];
        [self reload];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}
@end
