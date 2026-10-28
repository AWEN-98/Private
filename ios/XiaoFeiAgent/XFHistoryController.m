#import "XFHistoryController.h"
#import "XFChatStore.h"
@interface XFHistoryController ()
@property(nonatomic,strong) NSMutableArray *items;
@end
@implementation XFHistoryController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"历史对话";
    self.tableView.rowHeight=66;
    self.tableView.backgroundColor=[UIColor colorWithRed:0.964 green:0.972 blue:0.986 alpha:1];
    self.tableView.separatorColor=[UIColor colorWithRed:0.90 green:0.92 blue:0.96 alpha:1];
    self.tableView.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero];
    self.navigationController.navigationBar.translucent=NO;
    self.navigationController.navigationBar.barTintColor=[UIColor whiteColor];
    self.navigationController.navigationBar.tintColor=[UIColor colorWithRed:0.32 green:0.38 blue:0.79 alpha:1];
    self.navigationController.navigationBar.titleTextAttributes=@{NSForegroundColorAttributeName:[UIColor colorWithRed:0.15 green:0.20 blue:0.31 alpha:1]};
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(newTapped)];
    [self reload];
}
- (void)reload {self.items=[[XFChatStore conversations] mutableCopy];[self.tableView reloadData];}
- (void)doneTapped {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)newTapped {
    NSString *cid=[XFChatStore createConversation];
    if(self.onChoose) self.onChoose(cid);
    [self doneTapped];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return self.items.count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell=[t dequeueReusableCellWithIdentifier:@"history"];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"history"];
    NSDictionary *item=self.items[ip.row];
    cell.backgroundColor=[UIColor whiteColor];
    cell.tintColor=[UIColor colorWithRed:0.32 green:0.38 blue:0.79 alpha:1];
    cell.textLabel.text=item[@"title"]?:@"新对话";
    cell.textLabel.font=[UIFont boldSystemFontOfSize:15];
    cell.textLabel.textColor=[UIColor colorWithRed:0.15 green:0.20 blue:0.31 alpha:1];
    NSDate *date=[NSDate dateWithTimeIntervalSince1970:[item[@"updated"] doubleValue]];
    cell.detailTextLabel.text=[NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
    cell.detailTextLabel.font=[UIFont systemFontOfSize:12];
    cell.detailTextLabel.textColor=[UIColor colorWithRed:0.48 green:0.51 blue:0.61 alpha:1];
    cell.accessoryType=UITableViewCellAccessoryDetailButton;
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if(self.onChoose) self.onChoose(self.items[ip.row][@"id"]);
    [self doneTapped];
}
- (void)tableView:(UITableView *)t accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    NSString *cid=self.items[ip.row][@"id"];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"重命名对话" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=self.items[ip.row][@"title"];}];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        [XFChatStore renameConversationID:cid title:alert.textFields[0].text];[self reload];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip {return YES;}
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if(style!=UITableViewCellEditingStyleDelete) return;
    [XFChatStore deleteConversationID:self.items[ip.row][@"id"]];[self reload];
}
@end
