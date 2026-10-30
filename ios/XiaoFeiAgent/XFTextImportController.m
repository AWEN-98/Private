#import "XFTextImportController.h"
#import "XFTheme.h"
#import <QuartzCore/QuartzCore.h>
@interface XFTextImportController () <UITextViewDelegate>
@property(nonatomic,strong) UITextView *editor;
@property(nonatomic,strong) UILabel *caption;
@property(nonatomic,strong) UIButton *pasteButton;
@property(nonatomic,strong) UIButton *useButton;
@end
@implementation XFTextImportController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"导入文本";
    XFApplyNavigation(self.navigationController);
    self.view.backgroundColor=XFCanvas();
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"收起键盘" style:UIBarButtonItemStylePlain target:self action:@selector(hideKeyboard)];
    self.caption=[[UILabel alloc] init];
    self.caption.text=@"粘贴 TXT / Markdown 等纯文本，最多 12000 字。";
    self.caption.font=[UIFont systemFontOfSize:12];
    self.caption.textColor=XFSecondary();
    [self.view addSubview:self.caption];
    self.editor=[[UITextView alloc] init];
    self.editor.font=[UIFont systemFontOfSize:15];
    self.editor.delegate=self;
    XFCard(self.editor,12);
    self.editor.textColor=XFInk();
    self.editor.text=@"";
    [self.view addSubview:self.editor];
    self.pasteButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.pasteButton setTitle:@"粘贴剪贴板" forState:UIControlStateNormal];
    self.pasteButton.backgroundColor=XFAccentPale();
    [self.pasteButton setTitleColor:XFAccent() forState:UIControlStateNormal];
    self.pasteButton.layer.cornerRadius=12;
    [self.pasteButton addTarget:self action:@selector(pasteText) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.pasteButton];
    self.useButton=[UIButton buttonWithType:UIButtonTypeSystem];
    self.useButton.backgroundColor=XFAccent();
    self.useButton.layer.cornerRadius=12;
    [self.useButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.useButton setTitle:@"添加到当前对话" forState:UIControlStateNormal];
    [self.useButton addTarget:self action:@selector(useText) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.useButton];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardShown:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
}
- (void)dealloc {[[NSNotificationCenter defaultCenter] removeObserver:self];}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    self.caption.frame=CGRectMake(12,9,w-24,30);
    self.editor.frame=CGRectMake(12,42,w-24,MAX(100,h-104));
    self.pasteButton.frame=CGRectMake(12,h-53,(w-36)/2,44);
    self.useButton.frame=CGRectMake(w/2+6,h-53,(w-36)/2,44);
}
- (void)keyboardShown:(NSNotification *)notice {
    CGRect frame=[notice.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local=[self.view convertRect:frame fromView:nil];
    CGFloat cover=MAX(0,CGRectGetMaxY(self.view.bounds)-CGRectGetMinY(local));
    self.editor.contentInset=UIEdgeInsetsMake(0,0,cover+8,0);
    self.editor.scrollIndicatorInsets=self.editor.contentInset;
}
- (void)keyboardHidden:(NSNotification *)notice {
    self.editor.contentInset=UIEdgeInsetsZero;
    self.editor.scrollIndicatorInsets=UIEdgeInsetsZero;
}
- (void)hideKeyboard {[self.editor resignFirstResponder];}
- (void)close {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)pasteText {
    NSString *clip=[UIPasteboard generalPasteboard].string;
    if(!clip.length){self.caption.text=@"剪贴板内没有文字";return;}
    if(clip.length>12000)clip=[clip substringToIndex:12000];
    self.editor.text=clip;
    self.caption.text=[NSString stringWithFormat:@"已粘贴 %lu 字，可编辑后添加",(unsigned long)clip.length];
}
- (void)useText {
    NSString *text=[self.editor.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!text.length){self.caption.text=@"请先粘贴或输入文本";return;}
    if(text.length>12000)text=[text substringToIndex:12000];
    if(self.onUseText)self.onUseText(text);
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end
