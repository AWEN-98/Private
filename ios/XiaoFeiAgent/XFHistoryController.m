#import "XFHistoryController.h"
#import "XFChatStore.h"
@interface XFHistoryController ()
@property(nonatomic,strong) NSMutableArray *items;
@end
@implementation XFHistoryController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"历史对话";
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
    cell.textLabel.text=item[@"title"]?:@"新对话";
    NSDate *date=[NSDate dateWithTimeIntervalSince1970:[item[@"updated"] doubleValue]];
    cell.detailTextLabel.text=[NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
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
