#import "XFViewController.h"
#import "XFModelsController.h"
#import "XFChatStore.h"
#import "XFHistoryController.h"
#import "XFChatView.h"
#import "XFTextImportController.h"
#import "XFPromptToolsController.h"
#import "XFCompareController.h"
#import "XFDiagnostics.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

@interface XFViewController () <UIImagePickerControllerDelegate,UINavigationControllerDelegate,AVAudioRecorderDelegate,NSURLConnectionDataDelegate,UITextViewDelegate>
@property(nonatomic,strong) XFChatView *chat;
@property(nonatomic,strong) UIView *headerBar;
@property(nonatomic,strong) UIView *footerBar;
@property(nonatomic,strong) UILabel *brandTitle;
@property(nonatomic,strong) UIButton *modelsButton;
@property(nonatomic,strong) UIButton *sessionsButton;
@property(nonatomic,assign) CGFloat keyboardOffset;
@property(nonatomic,strong) UITextView *message;
@property(nonatomic,strong) UILabel *messagePlaceholder;
@property(nonatomic,assign) BOOL chatPayloadExceeded;
@property(nonatomic,copy) NSString *lastSubmittedDraft;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *sendButton;
@property(nonatomic,strong) UIButton *pasteButton;
@property(nonatomic,strong) UIButton *recordButton;
@property(nonatomic,strong) UILabel *recordingBadge;
@property(nonatomic,strong) NSTimer *recordTimer;
@property(nonatomic,strong) NSDate *recordStarted;
@property(nonatomic,strong) UIScrollView *tools;
@property(nonatomic,strong) NSMutableArray *history;
@property(nonatomic,copy) NSString *conversationID;
@property(nonatomic,strong) UIImage *pendingImage;
@property(nonatomic,copy) NSString *sendingImageName;
@property(nonatomic,strong) UIImageView *attachmentPreview;
@property(nonatomic,strong) UIButton *removeAttachmentButton;
@property(nonatomic,strong) UILabel *attachmentCaption;
@property(nonatomic,copy) NSString *pendingFileText;
@property(nonatomic,copy) NSString *lastAnswer;
@property(nonatomic,strong) AVAudioRecorder *recorder;
@property(nonatomic,strong) AVAudioPlayer *player;
@property(nonatomic,strong) NSURLConnection *connection;
@property(nonatomic,strong) NSMutableData *streamBuffer;
@property(nonatomic,strong) NSMutableString *streamText;
@property(nonatomic,copy) NSString *sendingContent;
@property(nonatomic,assign) NSInteger httpCode;
@property(nonatomic,assign) BOOL isWorking;
@property(nonatomic,assign) BOOL isRecording;
@property(nonatomic,strong) NSMutableURLRequest *lastChatRequest;
@property(nonatomic,strong) NSDictionary *lastChatProfile;
@property(nonatomic,assign) BOOL usingCompatibilityMode;
@property(nonatomic,assign) BOOL lastChatUsedSearch;
@end

@implementation XFViewController

- (UIColor *)accent {
    return [UIColor colorWithRed:0.32 green:0.38 blue:0.79 alpha:1];
}
- (UIColor *)ink {
    return [UIColor colorWithRed:0.14 green:0.19 blue:0.30 alpha:1];
}
- (void)styleNavigationButton:(UIButton *)button filled:(BOOL)filled {
    button.backgroundColor=filled?[self accent]:[UIColor colorWithRed:0.94 green:0.95 blue:0.99 alpha:1];
    [button setTitleColor:filled?[UIColor whiteColor]:[self accent] forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    button.layer.cornerRadius=9;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor colorWithRed:0.966 green:0.973 blue:0.987 alpha:1];
    self.history=[NSMutableArray array];
    CGFloat w=self.view.bounds.size.width;
    self.headerBar=[[UIView alloc] initWithFrame:CGRectMake(0,0,w,88)];
    self.headerBar.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.headerBar.backgroundColor=[UIColor whiteColor];
    [self.view addSubview:self.headerBar];
    UIView *rule=[[UIView alloc] initWithFrame:CGRectMake(0,87,w,0.5)];
    rule.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    rule.backgroundColor=[UIColor colorWithRed:0.90 green:0.92 blue:0.96 alpha:1];
    [self.headerBar addSubview:rule];

    self.sessionsButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.sessionsButton.frame=CGRectMake(12,27,62,33);
    [self.sessionsButton setTitle:@"会话" forState:UIControlStateNormal];
    [self styleNavigationButton:self.sessionsButton filled:NO];
    [self.sessionsButton addTarget:self action:@selector(historyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerBar addSubview:self.sessionsButton];

    self.brandTitle=[[UILabel alloc] initWithFrame:CGRectMake(80,25,w-160,38)];
    self.brandTitle.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.brandTitle.text=@"小斐 AI";
    self.brandTitle.font=[UIFont boldSystemFontOfSize:20];
    self.brandTitle.textColor=[self ink];
    self.brandTitle.textAlignment=NSTextAlignmentCenter;
    [self.headerBar addSubview:self.brandTitle];

    self.modelsButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.modelsButton.frame=CGRectMake(w-76,27,64,33);
    self.modelsButton.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
    [self.modelsButton setTitle:@"切换模型" forState:UIControlStateNormal];
    [self styleNavigationButton:self.modelsButton filled:YES];
    self.modelsButton.titleLabel.font=[UIFont boldSystemFontOfSize:11.5];
    [self.modelsButton addTarget:self action:@selector(modelsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerBar addSubview:self.modelsButton];

    self.status=[[UILabel alloc] initWithFrame:CGRectMake(13,65,w-26,18)];
    self.status.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.status.textColor=[UIColor colorWithRed:0.43 green:0.48 blue:0.59 alpha:1];
    self.status.font=[UIFont systemFontOfSize:11];
    self.status.lineBreakMode=NSLineBreakByTruncatingMiddle;
    [self.headerBar addSubview:self.status];

    self.chat=[[XFChatView alloc] initWithFrame:CGRectZero];
    self.chat.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.chat];
    __weak XFViewController *weakSelf=self;
    self.chat.onImageTap=^(UIImage *image) {
        [weakSelf showGeneratedImage:image];
    };
    self.recordingBadge=[[UILabel alloc] initWithFrame:CGRectMake(6,94,w-12,30)];
    self.recordingBadge.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.recordingBadge.font=[UIFont boldSystemFontOfSize:13];
    self.recordingBadge.textAlignment=NSTextAlignmentCenter;
    self.recordingBadge.layer.cornerRadius=7;
    self.recordingBadge.layer.masksToBounds=YES;
    self.recordingBadge.backgroundColor=[UIColor colorWithRed:.86 green:.19 blue:.23 alpha:1];
    self.recordingBadge.textColor=[UIColor whiteColor];
    self.recordingBadge.hidden=YES;
    [self.view addSubview:self.recordingBadge];

    self.footerBar=[[UIView alloc] initWithFrame:CGRectZero];
    self.footerBar.backgroundColor=[UIColor whiteColor];
    [self.view addSubview:self.footerBar];
    UIView *topRule=[[UIView alloc] initWithFrame:CGRectMake(0,0,w,0.5)];
    topRule.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    topRule.backgroundColor=[UIColor colorWithRed:0.89 green:0.91 blue:0.95 alpha:1];
    [self.footerBar addSubview:topRule];

    self.tools=[[UIScrollView alloc] initWithFrame:CGRectZero];
    self.tools.showsHorizontalScrollIndicator=NO;
    self.tools.alwaysBounceHorizontal=YES;
    [self.footerBar addSubview:self.tools];
    NSArray *items=@[@[@"＋ 新对话",@"new"],@[@"▧ 图片",@"photo"],@[@"≡ 文本",@"file"],
      @[@"● 录音",@"record"],@[@"♪ 朗读",@"tts"],@[@"✦ 生图",@"image"],@[@"◎ 联网",@"web"],@[@"复制回复",@"copyreply"],@[@"提示词",@"prompts"],@[@"双模型",@"compare"],@[@"诊断",@"diagnostics"]];
    CGFloat x=1;
    for(NSArray *item in items){
        UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];
        CGFloat bw=[item[1] isEqualToString:@"new"]?77:65;
        button.frame=CGRectMake(x,4,bw,34);
        button.backgroundColor=[UIColor colorWithRed:0.954 green:0.962 blue:0.988 alpha:1];
        [button setTitle:item[0] forState:UIControlStateNormal];
        [button setTitleColor:[self ink] forState:UIControlStateNormal];
        button.titleLabel.font=[UIFont systemFontOfSize:12.5];
        button.layer.cornerRadius=9;
        button.layer.borderWidth=0.5;
        button.layer.borderColor=[UIColor colorWithRed:0.89 green:0.91 blue:0.96 alpha:1].CGColor;
        [button setAccessibilityIdentifier:item[1]];
        if([item[1] isEqualToString:@"record"])self.recordButton=button;
        [button addTarget:self action:@selector(toolTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.tools addSubview:button];
        x+=bw+7;
    }
    self.tools.contentSize=CGSizeMake(x,42);

    self.message=[[UITextView alloc] initWithFrame:CGRectZero];
    self.message.scrollEnabled=YES;
    self.message.backgroundColor=[UIColor colorWithRed:0.965 green:0.973 blue:0.991 alpha:1];
    self.message.textColor=[self ink];
    self.message.font=[UIFont systemFontOfSize:14.5];
    self.message.layer.cornerRadius=12;
    self.message.layer.borderWidth=0.5;
    self.message.layer.borderColor=[UIColor colorWithRed:0.88 green:0.90 blue:0.96 alpha:1].CGColor;
    self.message.textContainerInset=UIEdgeInsetsMake(8,7,7,7);
    self.message.returnKeyType=UIReturnKeyDefault;
    self.message.delegate=self;
    [self.footerBar addSubview:self.message];
    self.messagePlaceholder=[[UILabel alloc] initWithFrame:CGRectZero];
    self.messagePlaceholder.text=@"向 AI 提问…";
    self.messagePlaceholder.textColor=[UIColor colorWithWhite:0.60 alpha:1];
    self.messagePlaceholder.font=[UIFont systemFontOfSize:14.5];
    self.messagePlaceholder.userInteractionEnabled=NO;
    [self.footerBar addSubview:self.messagePlaceholder];

    self.sendButton=[UIButton buttonWithType:UIButtonTypeCustom];
    [self.sendButton setTitle:@"发送" forState:UIControlStateNormal];
    self.sendButton.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    [self styleNavigationButton:self.sendButton filled:YES];
    self.sendButton.layer.cornerRadius=11;
    [self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.footerBar addSubview:self.sendButton];

    self.pasteButton=[UIButton buttonWithType:UIButtonTypeCustom];
    [self.pasteButton setTitle:@"粘贴" forState:UIControlStateNormal];
    self.pasteButton.titleLabel.font=[UIFont boldSystemFontOfSize:12];
    [self styleNavigationButton:self.pasteButton filled:NO];
    self.pasteButton.layer.cornerRadius=10;
    self.pasteButton.hidden=YES;
    [self.pasteButton addTarget:self action:@selector(pasteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.footerBar addSubview:self.pasteButton];

    self.attachmentPreview=[[UIImageView alloc] initWithFrame:CGRectZero];
    self.attachmentPreview.backgroundColor=[UIColor colorWithWhite:0.92 alpha:1];
    self.attachmentPreview.contentMode=UIViewContentModeScaleAspectFill;
    self.attachmentPreview.layer.cornerRadius=8;
    self.attachmentPreview.clipsToBounds=YES;
    self.attachmentPreview.userInteractionEnabled=YES;
    UITapGestureRecognizer *previewTap=[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(previewPendingImage)];
    [self.attachmentPreview addGestureRecognizer:previewTap];
    [self.footerBar addSubview:self.attachmentPreview];
    self.removeAttachmentButton=[UIButton buttonWithType:UIButtonTypeCustom];
    [self.removeAttachmentButton setTitle:@"移除" forState:UIControlStateNormal];
    [self styleNavigationButton:self.removeAttachmentButton filled:NO];
    self.removeAttachmentButton.titleLabel.font=[UIFont boldSystemFontOfSize:11];
    [self.removeAttachmentButton addTarget:self action:@selector(removePendingImage)
        forControlEvents:UIControlEventTouchUpInside];
    [self.footerBar addSubview:self.removeAttachmentButton];
    self.attachmentCaption=[[UILabel alloc] initWithFrame:CGRectZero];
    self.attachmentCaption.text=@"已附加图片 · 点击缩略图预览";
    self.attachmentCaption.font=[UIFont systemFontOfSize:11];
    self.attachmentCaption.textColor=[self ink];
    self.attachmentCaption.numberOfLines=2;
    [self.footerBar addSubview:self.attachmentCaption];
    [self updateAttachmentViews];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
      name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
      name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChangeFrame:)
      name:UIKeyboardWillChangeFrameNotification object:nil];


    NSArray *existing=[XFChatStore conversations];
    NSString *firstConversation=existing.count?existing[0][@"id"]:[XFChatStore createConversation];
    // Do not overwrite a saved draft before the first conversation is restored.
    [self loadConversation:firstConversation];
    [self refreshStatus];
    [self layoutForKeyboard:0];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutForKeyboard:self.keyboardOffset];
}
- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.connection cancel];
    [self.recordTimer invalidate];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStatus];
}
- (void)refreshStatus {
    NSDictionary *profile=[XFModelsController activeProfileForCapability:@"chat"];
    NSString *name=profile[@"name"];
    self.status.text=name.length?[NSString stringWithFormat:@"聊天模型：%@ · %@",name,self.isWorking?@"处理中":@"已就绪"]:@"尚未选择聊天模型，点击右上角「模型」";
}
// The iOS 8 Chinese candidate bar can change keyboard height while editing.
// Use the actual end frame in this view, never cap it to half the screen.
- (void)keyboardWillShow:(NSNotification *)n {[self keyboardWillChangeFrame:n];}
- (void)keyboardWillChangeFrame:(NSNotification *)n {
    NSValue *value=n.userInfo[UIKeyboardFrameEndUserInfoKey];
    if(!value)return;
    CGRect keyboardScreen=[value CGRectValue];
    CGRect keyboardInView=[self.view convertRect:keyboardScreen fromView:nil];
    CGRect overlap=CGRectIntersection(self.view.bounds,keyboardInView);
    CGFloat covered=0;
    if(!CGRectIsNull(overlap) && !CGRectIsEmpty(overlap) &&
       CGRectGetMaxY(overlap)>=CGRectGetMaxY(self.view.bounds)-2) {
        covered=CGRectGetMaxY(self.view.bounds)-CGRectGetMinY(overlap);
    }
    [self layoutForKeyboard:covered];
}
- (void)keyboardWillHide:(NSNotification *)n {[self layoutForKeyboard:0];}
- (void)layoutForKeyboard:(CGFloat)height {
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    if(h<1 || w<1)return;
    self.keyboardOffset=MAX(0,MIN(height,h));
    BOOL typing=self.keyboardOffset>1;
    // Leave a small gap above the Chinese predictive-word bar.
    CGFloat availableBottom=MAX(0,h-self.keyboardOffset-(typing?5:0));
    self.headerBar.hidden=typing;
    self.tools.hidden=typing;
    self.pasteButton.hidden=!typing;
    CGFloat top=typing?0:88;
    BOOL hasImage=self.pendingImage!=nil;
    CGFloat footerHeight=typing?MIN(hasImage?110:62,availableBottom):(hasImage?192:125);
    CGFloat footerY=MAX(0,availableBottom-footerHeight);
    self.chat.frame=CGRectMake(0,top,w,MAX(0,footerY-top));
    self.footerBar.frame=CGRectMake(0,footerY,w,footerHeight);
    self.recordingBadge.frame=CGRectMake(6,typing?4:94,w-12,30);
    if(typing){
        CGFloat margin=8,gap=6,pasteW=46,sendW=58;
        CGFloat inputW=MAX(60,w-2*margin-2*gap-pasteW-sendW);
        CGFloat y=hasImage?MAX(2,footerHeight-51):MAX(2,(footerHeight-44)/2);
        self.message.frame=CGRectMake(margin,y,inputW,MIN(44,footerHeight));
        self.messagePlaceholder.frame=CGRectMake(margin+11,y+6,inputW-17,27);
        self.pasteButton.frame=CGRectMake(margin+inputW+gap,y,pasteW,MIN(44,footerHeight));
        self.sendButton.frame=CGRectMake(w-margin-sendW,y,sendW,MIN(44,footerHeight));
    } else {
        self.tools.frame=CGRectMake(10,7,w-20,42);
        CGFloat inputY=hasImage?130:57;
        self.message.frame=CGRectMake(11,inputY,w-94,53);
        self.messagePlaceholder.frame=CGRectMake(22,inputY+8,w-110,26);
        self.sendButton.frame=CGRectMake(w-75,inputY+3,64,44);
    }
    self.attachmentPreview.frame=typing?CGRectMake(10,7,36,36):CGRectMake(11,54,63,63);
    self.removeAttachmentButton.frame=typing?CGRectMake(53,8,43,30):CGRectMake(82,63,43,30);
    self.attachmentCaption.frame=typing?CGRectMake(102,7,MAX(30,w-112),35):CGRectMake(133,59,MAX(30,w-144),46);
    [self updateAttachmentViews];
}
- (void)updateAttachmentViews {
    BOOL show=self.pendingImage!=nil;
    self.attachmentPreview.hidden=!show;
    self.removeAttachmentButton.hidden=!show;
    self.attachmentCaption.hidden=!show;
    self.attachmentPreview.image=show?self.pendingImage:nil;
}
- (void)removePendingImage {
    self.pendingImage=nil;
    self.status.text=@"已移除图片附件";
    [self layoutForKeyboard:self.keyboardOffset];
}
- (void)previewPendingImage {
    if(self.pendingImage)[self showGeneratedImage:self.pendingImage];
}
- (void)pasteTapped {
    NSString *clip=[UIPasteboard generalPasteboard].string;
    if(!clip.length){
        [self showAlert:@"剪贴板没有文字" detail:@"可以先在其他软件中复制文本，再回到小斐 AI 点击粘贴。"];
        return;
    }
    UITextRange *selection=self.message.selectedTextRange;
    if(selection) [self.message replaceRange:selection withText:clip];
    else self.message.text=[(self.message.text?:@"") stringByAppendingString:clip];
    [self.message becomeFirstResponder];
    [self textViewDidChange:self.message];
}
- (void)textViewDidChange:(UITextView *)view {
    if(view!=self.message)return;
    self.messagePlaceholder.hidden=view.text.length>0;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveDraft) object:nil];
    [self performSelector:@selector(saveDraft) withObject:nil afterDelay:0.50];
}
- (NSString *)draftKeyForConversation:(NSString *)cid {
    return [@"xf_draft_" stringByAppendingString:cid?:@"default"];
}
- (void)saveDraft {
    if(!self.conversationID.length)return;
    NSString *value=self.message.text?:@"";
    if(value.length>6000)value=[value substringToIndex:6000];
    [[NSUserDefaults standardUserDefaults] setObject:value
      forKey:[self draftKeyForConversation:self.conversationID]];
}
- (void)restoreSubmittedDraft {
    if(self.message.text.length || !self.lastSubmittedDraft.length)return;
    self.message.text=self.lastSubmittedDraft;
    [self textViewDidChange:self.message];
    self.status.text=@"请求失败，已恢复输入内容";
}
- (void)showAlert:(NSString *)title detail:(NSString *)detail {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)modelsTapped {
    [self.message resignFirstResponder];
    XFModelsController *m=[[XFModelsController alloc] initWithStyle:UITableViewStyleGrouped];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:m];
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)historyTapped {
    [self.message resignFirstResponder];
    XFHistoryController *controller=[[XFHistoryController alloc] initWithStyle:UITableViewStylePlain];
    controller.onChoose=^(NSString *cid){[self loadConversation:cid];};
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)loadConversation:(NSString *)cid {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveDraft) object:nil];
    [self saveDraft];
    self.conversationID=cid;
    NSDictionary *item=[XFChatStore conversationForID:cid];
    self.history=[item[@"messages"] mutableCopy]?:[NSMutableArray array];
    self.lastAnswer=nil;
    for(NSDictionary *m in self.history) {
        if([m[@"role"] isEqualToString:@"assistant"])self.lastAnswer=m[@"content"];
    }
    [self.chat showConversation:self.history];
    self.pendingFileText=nil;self.pendingImage=nil;
    [self layoutForKeyboard:self.keyboardOffset];
    self.message.text=[[NSUserDefaults standardUserDefaults] stringForKey:[self draftKeyForConversation:cid]]?:@"";
    self.messagePlaceholder.hidden=self.message.text.length>0;
}
- (void)appendLine:(NSString *)line {
    if([line hasPrefix:@"我："]) [self.chat addMessage:[line substringFromIndex:2] fromUser:YES];
    else [self.chat showNotice:line];
}
- (void)addExchange:(NSString *)question answer:(NSString *)answer {
    if(question.length) {
        if(self.sendingImageName.length)
            [self.history addObject:@{@"role":@"user",@"content":question,@"image_file":self.sendingImageName}];
        else [self.history addObject:@{@"role":@"user",@"content":question}];
    }
    self.sendingImageName=nil;
    if(answer.length) [self.history addObject:@{@"role":@"assistant",@"content":answer}];
    [XFChatStore saveConversationID:self.conversationID messages:self.history];
    if(answer.length) self.lastAnswer=answer;
}
- (void)setWorking:(BOOL)value {
    self.isWorking=value;
    [self.sendButton setTitle:value?@"停止":@"发送" forState:UIControlStateNormal];
}
- (void)toolTapped:(UIButton *)button {
    NSString *name=[button accessibilityIdentifier];
    [self.message resignFirstResponder];
    if([name isEqualToString:@"new"]) {[self loadConversation:[XFChatStore createConversation]];return;}
    if([name isEqualToString:@"copyreply"]) {
        if(self.lastAnswer.length) {[UIPasteboard generalPasteboard].string=self.lastAnswer;self.status.text=@"已复制上一次 AI 回复";}
        else [self showAlert:@"暂无可复制的回复" detail:@"收到 AI 回复后即可复制。"];
        return;
    }
    if([name isEqualToString:@"photo"]) {[self pickImage];return;}
    if([name isEqualToString:@"file"]) {[self pickFile];return;}
    if([name isEqualToString:@"prompts"]) {[self showPromptToolbox];return;}
    if([name isEqualToString:@"compare"]) {[self showComparison];return;}
    if([name isEqualToString:@"diagnostics"]) {[self showDiagnostics];return;}
    if([name isEqualToString:@"record"]) {[self toggleRecord];return;}
    if([name isEqualToString:@"tts"]) {[self speakLastAnswer];return;}
    if([name isEqualToString:@"image"]) {[self generateImage];return;}
    if([name isEqualToString:@"web"]) {[self sendAsSearch];return;}
}
- (void)showDiagnostics {
    NSString *report=[XFDiagnostics report];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"运行诊断"
      message:report.length>1300?[[report substringToIndex:1300] stringByAppendingString:@"…"]:report
      preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制全部" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        [UIPasteboard generalPasteboard].string=report;
        self.status.text=@"已复制诊断日志（不含 API Key 或聊天正文）";
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空记录" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        [XFDiagnostics clear];
        self.status.text=@"诊断记录已清空";
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (NSDictionary *)profileFor:(NSString *)capability {
    NSDictionary *p=[XFModelsController activeProfileForCapability:capability];
    if(!p) [self showAlert:@"尚未配置" detail:[NSString stringWithFormat:@"请点击「模型」，添加并选择 %@ 的 API。",capability]];
    return p;
}
- (NSString *)secretFor:(NSDictionary *)profile {
    return [XFModelsController secretForProfile:profile];
}
- (NSMutableURLRequest *)requestForProfile:(NSDictionary *)p {
    NSURL *url=[NSURL URLWithString:p[@"endpoint"]];
    if(![[url scheme] isEqualToString:@"https"] || !url.host.length) {
        [self showAlert:@"接口地址无效" detail:@"请在模型管理中填写完整 HTTPS 接口地址。"];return nil;
    }
    NSString *key=[self secretFor:p];
    if(!key.length){[self showAlert:@"缺少密钥" detail:@"请编辑模型配置并填写 API Key。"];return nil;}
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:75];
    req.HTTPMethod=@"POST";
    [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    return req;
}
- (void)sendTapped {
    if(self.isWorking) {
        [self.connection cancel];self.connection=nil;
        [self setWorking:NO];
        [self restoreSubmittedDraft];
        [XFDiagnostics record:@"手动停止请求" code:0 detail:@"用户中止"];
        self.status.text=@"已停止请求；输入草稿已保留";
        return;
    }
    [self sendChat:NO];
}
- (void)sendAsSearch {
    if(self.isWorking)return;
    [self sendChat:YES];
}
- (void)sendChat:(BOOL)web {
    NSDictionary *profile=[self profileFor:web?@"web":(self.pendingImage?@"vision":@"chat")];
    if(!profile)return;
    NSString *msg=[self.message.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!msg.length && self.pendingImage) msg=@"请详细描述这张图片";
    if(!msg.length && self.pendingFileText.length) msg=@"请分析这份文档";
    if(!msg.length) {self.status.text=@"请先输入问题";return;}
    if(msg.length>6000) {
        [self showAlert:@"输入内容过长" detail:@"iPhone 4S 建议每次不超过 6000 字，请拆成几段发送。"];
        return;
    }
    NSString *sent=msg;
    if(self.pendingFileText.length) {
        msg=[NSString stringWithFormat:@"%@\n\n以下为文档内容：\n%@",msg,self.pendingFileText];
        sent=[sent stringByAppendingString:@" [文本文件]"];
    }
    NSMutableArray *messages=[NSMutableArray arrayWithObject:@{@"role":@"system",@"content":@"你是小斐，中文智能助手。准确回答问题，信息不确定时如实说明。"}];
    NSUInteger start=self.history.count>12?self.history.count-12:0;
    NSUInteger totalChars=0;
    NSMutableArray *recent=[NSMutableArray array];
    for(NSUInteger i=self.history.count;i>start;i--) {
        NSDictionary *old=self.history[i-1];
        NSString *text=[old[@"content"] isKindOfClass:[NSString class]]?old[@"content"]:nil;
        if(!text.length)continue;
        NSUInteger clip=MIN((NSUInteger)3500,text.length);
        if(totalChars+clip>16000)break;
        totalChars+=clip;
        [recent insertObject:@{@"role":old[@"role"]?:@"user",
          @"content":[text substringToIndex:clip]} atIndex:0];
    }
    [messages addObjectsFromArray:recent];
    if(self.pendingImage) {
        UIImage *image=self.pendingImage;
        CGFloat maxDimension=640;
        CGFloat scale=MIN(1.0,maxDimension/MAX(image.size.width,image.size.height));
        CGSize target=CGSizeMake(MAX(1,image.size.width*scale),MAX(1,image.size.height*scale));
        UIGraphicsBeginImageContextWithOptions(target,YES,1);
        [image drawInRect:CGRectMake(0,0,target.width,target.height)];
        UIImage *resized=UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSData *jpeg=UIImageJPEGRepresentation(resized,0.60);
        NSString *encoded=[jpeg base64EncodedStringWithOptions:0];
        if(!encoded.length){
            self.status.text=@"图片编码失败，请换一张图片";
            [XFDiagnostics record:@"图片编码失败" code:0 detail:@"JPEG 编码结果为空"];
            return;
        }
        NSString *uri=[@"data:image/jpeg;base64," stringByAppendingString:encoded];
        [messages addObject:@{@"role":@"user",@"content":@[
            @{@"type":@"text",@"text":msg},
            @{@"type":@"image_url",@"image_url":@{@"url":uri}}
        ]}];
        sent=[sent stringByAppendingString:@" [图片]"];
    } else {
        [messages addObject:@{@"role":@"user",@"content":msg}];
    }
    NSMutableURLRequest *req=[self requestForProfile:profile];if(!req)return;
    NSString *probeKey=[NSString stringWithFormat:@"%@|%@",profile[@"account_id"]?:@"",profile[@"model"]?:@""];
    NSDictionary *probe=[[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"xf_model_probe_results_v1"] objectForKey:probeKey];
    NSTimeInterval elapsed=[[NSDate date] timeIntervalSince1970]-[probe[@"time"] doubleValue];
    BOOL selfTestedOK=([probe[@"status"] isEqualToString:@"ok"] && elapsed>=0 && elapsed<24*3600);
    // A successful self-check used a minimal non-streaming chat payload.
    // Reuse that format for this model, instead of immediately making a
    // stream=true request which some providers reject with HTTP 400.
    BOOL compatible=[[NSUserDefaults standardUserDefaults] boolForKey:[self compatibilityKeyFor:profile]] || selfTestedOK;
    if(compatible && messages.count && [messages[0][@"role"] isEqualToString:@"system"])[messages removeObjectAtIndex:0];
    NSMutableDictionary *payload=[@{@"model":profile[@"model"],@"messages":messages,@"stream":[NSNumber numberWithBool:!compatible]} mutableCopy];
    if(web && !compatible) payload[@"web_search_options"]=@{};
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    self.lastChatRequest=[req mutableCopy];
    self.lastChatProfile=profile;
    self.usingCompatibilityMode=compatible;
    self.lastChatUsedSearch=web;
    self.sendingContent=sent;
    self.lastSubmittedDraft=self.message.text?:@"";
    [self.message resignFirstResponder];self.message.text=@"";
    [self textViewDidChange:self.message];
    self.pendingFileText=nil;self.pendingImage=nil;
    [self appendLine:[NSString stringWithFormat:@"我：%@",sent]];
    self.streamBuffer=[NSMutableData data];self.streamText=[NSMutableString string];self.httpCode=0;
    self.chatPayloadExceeded=NO;
    [self setWorking:YES];self.status.text=web?@"正在联网搜索…":@"正在生成回复…";
    self.connection=[[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:YES];
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    self.httpCode=[response isKindOfClass:[NSHTTPURLResponse class]]?[(NSHTTPURLResponse *)response statusCode]:0;
    self.chatPayloadExceeded=NO;
    [self.streamBuffer setLength:0];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if(self.httpCode>=400) {
        // Error details are useful, but never allow an unlimited error body on 512MB RAM.
        if(self.streamBuffer.length<65536){
            NSUInteger length=MIN((NSUInteger)65536-self.streamBuffer.length,data.length);
            [self.streamBuffer appendBytes:data.bytes length:length];
        }
        return;
    }
    if(self.chatPayloadExceeded)return;
    NSUInteger limit=self.usingCompatibilityMode?512*1024:128*1024;
    if(self.streamBuffer.length+data.length>limit || self.streamText.length>30000){
        self.chatPayloadExceeded=YES;
        [self.connection cancel];self.connection=nil;
        [self setWorking:NO];
        [self restoreSubmittedDraft];
        self.status.text=@"回复太大，已停止以保护旧设备内存";
        [XFDiagnostics record:@"回复超过内存限制" code:0 detail:@"超过 128KB 事件缓存 / 512KB JSON / 30000 字"];
        return;
    }
    [self.streamBuffer appendData:data];
    if(self.usingCompatibilityMode)return;
    // Normalize CRLF to LF so iOS 8 handles both kinds of SSE separators.
    if(self.streamBuffer.length){
        NSString *part=[[NSString alloc] initWithData:self.streamBuffer encoding:NSUTF8StringEncoding];
        if(part && [part rangeOfString:@"\r"].location!=NSNotFound){
            NSString *normalized=[part stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
            self.streamBuffer=[[normalized dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        }
    }
    NSData *separator=[@"\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    while(self.streamBuffer.length) {
        NSRange boundary=[self.streamBuffer rangeOfData:separator options:0 range:NSMakeRange(0,self.streamBuffer.length)];
        if(boundary.location==NSNotFound) break;
        NSData *part=[self.streamBuffer subdataWithRange:NSMakeRange(0,boundary.location)];
        NSUInteger consumed=boundary.location+boundary.length;
        NSData *remaining=[self.streamBuffer subdataWithRange:NSMakeRange(consumed,self.streamBuffer.length-consumed)];
        self.streamBuffer=[remaining mutableCopy];
        NSString *event=[[NSString alloc] initWithData:part encoding:NSUTF8StringEncoding];
        NSArray *lines=[event componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for(NSString *line in lines) {
            if(![line hasPrefix:@"data:"])continue;
            NSString *raw=[[line substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if([raw isEqualToString:@"[DONE]"])continue;
            NSData *jsonData=[raw dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *json=[NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
            NSArray *choices=[json isKindOfClass:[NSDictionary class]]?json[@"choices"]:nil;
            if(![choices isKindOfClass:[NSArray class]] || !choices.count)continue;
            NSDictionary *choice=choices[0];
            NSDictionary *delta=[choice[@"delta"] isKindOfClass:[NSDictionary class]]?choice[@"delta"]:nil;
            NSString *chunk=[delta[@"content"] isKindOfClass:[NSString class]]?delta[@"content"]:nil;
            if(chunk.length){
                [self.streamText appendString:chunk];
                [self showStreamingAnswer];
            }
        }
    }
}
- (void)showStreamingAnswer {
    // UIKit label, no HTML engine or animated blur.
    static CFAbsoluteTime lastPaint=0;
    CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();
    if(now-lastPaint<0.12)return;
    lastPaint=now;
    [self.chat updateStreaming:self.streamText];
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if(connection!=self.connection)return;
    self.connection=nil;[self setWorking:NO];
    [XFDiagnostics record:@"聊天网络错误" code:error.code detail:error.domain?:@""];
    [self restoreSubmittedDraft];
    self.status.text=[NSString stringWithFormat:@"网络失败 %ld；检查 HTTPS/TLS 或当前网络",(long)error.code];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if(connection!=self.connection)return;
    self.connection=nil;[self setWorking:NO];
    if(self.httpCode>=400) {
        NSString *reason=[self explainAPIError:self.streamBuffer];
        NSString *endpointHost=[NSURL URLWithString:self.lastChatProfile[@"endpoint"]].host?:@"未知";
        [XFDiagnostics record:@"API 错误" code:self.httpCode detail:endpointHost];
        [self restoreSubmittedDraft];
        self.status.text=[NSString stringWithFormat:@"HTTP %ld · 查看接口报错原因",(long)self.httpCode];
        [self showAPIErrorWithReason:reason status:self.httpCode];
        return;
    }
    NSString *answer=[self.streamText copy];
    if(!answer.length) {
        NSDictionary *json=[NSJSONSerialization JSONObjectWithData:self.streamBuffer options:0 error:NULL];
        NSArray *choices=[json isKindOfClass:[NSDictionary class]]?json[@"choices"]:nil;
        if([choices isKindOfClass:[NSArray class]] && choices.count) {
            NSDictionary *first=choices[0];
            NSDictionary *message=first[@"message"];
            if([message isKindOfClass:[NSDictionary class]] && [message[@"content"] isKindOfClass:[NSString class]])
                answer=message[@"content"];
        }
    }
    if(!answer.length) {
        [XFDiagnostics record:@"无文本回复" code:self.httpCode detail:@"检查 Chat Completions 兼容性"];
        [self restoreSubmittedDraft];
        self.status.text=@"API 没有返回可用文字：查看诊断或换兼容模型";
        return;
    }
    [self.chat finishStreaming:answer];
    [self addExchange:self.sendingContent answer:answer];
    if(self.usingCompatibilityMode && self.lastChatProfile) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:[self compatibilityKeyFor:self.lastChatProfile]];
    }
    if(self.lastSubmittedDraft.length && [self.message.text isEqualToString:self.lastSubmittedDraft]){
        self.message.text=@"";
        [self textViewDidChange:self.message];
    }
    self.lastSubmittedDraft=nil;
    self.status.text=self.usingCompatibilityMode?@"兼容模式成功，下次将自动使用":@"回复完成，已保存到历史对话";
}
- (NSString *)compatibilityKeyFor:(NSDictionary *)profile {
    NSString *idText=[NSString stringWithFormat:@"%@|%@",profile[@"account_id"]?:@"",profile[@"model"]?:@""];
    return [@"xf_compat_nonstream_" stringByAppendingString:idText];
}
- (NSString *)explainAPIError:(NSData *)data {
    id json=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    NSString *message=nil;
    if([json isKindOfClass:[NSDictionary class]]) {
        id err=json[@"error"];
        if([err isKindOfClass:[NSDictionary class]]) {
            id description=err[@"message"]?:err[@"detail"]?:err[@"description"];
            if([description isKindOfClass:[NSString class]])message=description;
            else if([err[@"code"] isKindOfClass:[NSString class]])message=err[@"code"];
        } else if([err isKindOfClass:[NSString class]])message=err;
        if(!message.length) {
            id value=json[@"message"]?:json[@"detail"]?:json[@"error_description"]?:json[@"msg"];
            if([value isKindOfClass:[NSString class]])message=value;
            else if([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]])
                message=[value description];
        }
    }
    if(!message.length && data.length){
        NSString *raw=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if(raw.length)message=raw;
    }
    if(!message.length)message=@"服务端没有提供详细错误。可能是模型不支持当前接口、请求参数不兼容，或模型 ID 不正确。";
    if(message.length>850)message=[[message substringToIndex:850] stringByAppendingString:@"…"];
    // Some reverse proxy errors echo request headers. Do not include saved API keys in diagnostics.
    NSString *secret=[XFModelsController secretForProfile:self.lastChatProfile];
    if(secret.length)message=[message stringByReplacingOccurrencesOfString:secret withString:@"[密钥已隐藏]"];
    return message;
}
- (void)showAPIErrorWithReason:(NSString *)reason status:(NSInteger)status {
    NSDictionary *p=self.lastChatProfile?:@{};
    NSURL *url=[NSURL URLWithString:p[@"endpoint"]?:@""];
    NSString *endpoint=[NSString stringWithFormat:@"%@%@",url.host?:@"未知",url.path?:@""];
    NSString *detail=[NSString stringWithFormat:@"服务：%@\n模型：%@\n接口：%@\n\n服务端原因：\n%@",
        p[@"provider"]?:@"未知",p[@"model"]?:@"未知",endpoint,reason?:@"未知"];
    NSString *report=[NSString stringWithFormat:@"HTTP %ld\n%@",(long)status,detail];
    NSString *shortDetail=detail.length>430?
        [[detail substringToIndex:430] stringByAppendingString:@"…\n可点「复制诊断」查看全部信息。"]:detail;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:
        [NSString stringWithFormat:@"API 错误 · HTTP %ld",(long)status]
        message:shortDetail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制诊断（不含密钥）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        [UIPasteboard generalPasteboard].string=report;
        self.status.text=@"诊断信息已复制，可直接粘贴给我";
    }]];
    NSString *low=reason.lowercaseString?:@"";
    BOOL accountIssue=[low containsString:@"not activated"] ||
      [low containsString:@"未开通"] || [low containsString:@"insufficient balance"] ||
      [low containsString:@"余额不足"] || [low containsString:@"rate limit"] ||
      [low containsString:@"api key"] || status==401 || status==403 || status==429;
    if((status==400 || status==422) && self.lastChatRequest &&
       !self.usingCompatibilityMode && !accountIssue) {
        [alert addAction:[UIAlertAction actionWithTitle:@"兼容格式重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self retryWithoutStreaming];
        }]];
    }
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)retryWithoutStreaming {
    if(self.isWorking || !self.lastChatRequest || !self.lastChatProfile)return;
    NSMutableURLRequest *request=[self.lastChatRequest mutableCopy];
    id decoded=[NSJSONSerialization JSONObjectWithData:request.HTTPBody options:NSJSONReadingMutableContainers error:NULL];
    if(![decoded isKindOfClass:[NSMutableDictionary class]]){
        self.status.text=@"原请求数据已失效，请重新发送";return;
    }
    NSMutableDictionary *body=(NSMutableDictionary *)decoded;
    body[@"stream"]=[NSNumber numberWithBool:NO];
    [body removeObjectForKey:@"web_search_options"];
    NSMutableArray *messages=body[@"messages"];
    if([messages isKindOfClass:[NSMutableArray class]] && messages.count){
        NSDictionary *first=messages[0];
        if([first isKindOfClass:[NSDictionary class]] && [first[@"role"] isEqualToString:@"system"])
            [messages removeObjectAtIndex:0];
    }
    NSData *bytes=[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    if(!bytes){self.status.text=@"兼容请求编码失败";return;}
    request.HTTPBody=bytes;
    self.lastChatRequest=[request mutableCopy];
    self.usingCompatibilityMode=YES;
    self.streamBuffer=[NSMutableData data];
    self.streamText=[NSMutableString string];
    self.httpCode=0;
    self.chatPayloadExceeded=NO;
    [self setWorking:YES];
    self.status.text=@"兼容模式重试：关闭流式输出与额外参数…";
    self.connection=[[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
}
- (void)pickImage {
    UIImagePickerController *picker=[[UIImagePickerController alloc] init];
    picker.delegate=self;
    picker.sourceType=UIImagePickerControllerSourceTypePhotoLibrary;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *img=info[UIImagePickerControllerOriginalImage];
    self.pendingImage=img;
    [picker dismissViewControllerAnimated:YES completion:nil];
    self.status.text=img?@"已选择图片，发送问题时将使用视觉模型":@"图片读取失败";
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
- (void)pickFile {
    // Legacy iOS 8 devices may not have a working document provider.
    // Use native in-app paste/edit instead of launching UIDocumentPicker.
    XFTextImportController *editor=[[XFTextImportController alloc] init];
    __weak XFViewController *weakSelf=self;
    editor.onUseText=^(NSString *text){
        weakSelf.pendingFileText=text;
        weakSelf.status.text=[NSString stringWithFormat:@"已添加文本（%lu 字），输入问题后发送",(unsigned long)text.length];
        [weakSelf.chat showNotice:@"文本已经添加到当前问题"];
    };
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:editor];
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)showPromptToolbox {
    XFPromptToolsController *tools=[[XFPromptToolsController alloc] initWithStyle:UITableViewStyleGrouped];
    __weak XFViewController *weakSelf=self;
    tools.onUsePrompt=^(NSString *text){
        weakSelf.message.text=text;
        [weakSelf textViewDidChange:weakSelf.message];
        weakSelf.status.text=@"提示词已填入；可编辑后发送";
    };
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:tools];
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)showComparison {
    XFCompareController *controller=[[XFCompareController alloc] init];
    controller.initialPrompt=self.message.text;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:controller];
    controller.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
       initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeComparison)];
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)closeComparison {[self dismissViewControllerAnimated:YES completion:nil];}

- (void)setRecordingDisplay:(BOOL)recording {
    self.recordingBadge.hidden=!recording;
    if(recording){
        self.recordButton.backgroundColor=[UIColor colorWithRed:.84 green:.18 blue:.21 alpha:1];
        [self.recordButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [self.recordButton setTitle:@"■ 停止录音" forState:UIControlStateNormal];
        [self.recordingBadge setText:@"● 正在录音 00:00 · 点击停止"];
    } else {
        self.recordButton.backgroundColor=[UIColor colorWithRed:.954 green:.962 blue:.988 alpha:1];
        [self.recordButton setTitleColor:[self ink] forState:UIControlStateNormal];
        [self.recordButton setTitle:@"● 录音" forState:UIControlStateNormal];
    }
}
- (void)updateRecordingClock:(NSTimer *)timer {
    if(!self.isRecording)return;
    if(![self.recorder isRecording]) {
        [self finishRecording];
        return;
    }
    NSTimeInterval elapsed=[[NSDate date] timeIntervalSinceDate:self.recordStarted];
    NSInteger seconds=MAX(0,(NSInteger)elapsed);
    self.recordingBadge.text=[NSString stringWithFormat:@"● 正在录音 %02ld:%02ld · 点击停止",
         (long)(seconds/60),(long)(seconds%60)];
    self.status.text=@"录音中，点红色「停止录音」结束";
    if(seconds>=60)[self finishRecording];
}
- (void)finishRecording {
    if(!self.isRecording)return;
    self.isRecording=NO;
    [self.recorder stop];
    [self.recordTimer invalidate];self.recordTimer=nil;
    [self setRecordingDisplay:NO];
    self.status.text=@"录音结束，正在识别语音…";
    [self transcribeRecording];
}
- (void)toggleRecord {
    if(self.isRecording){[self finishRecording];return;}
    NSDictionary *p=[self profileFor:@"stt"];if(!p)return;
    AVAudioSession *session=[AVAudioSession sharedInstance];
    NSError *sessionError=nil;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&sessionError];
    [session setActive:YES error:&sessionError];
    if(sessionError){
        [self showAlert:@"无法启动录音" detail:sessionError.localizedDescription];
        return;
    }
    self.status.text=@"正在请求麦克风权限…";
    [session requestRecordPermission:^(BOOL granted) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if(!granted){
                self.status.text=@"未获得麦克风权限";
                [self showAlert:@"没有麦克风权限" detail:@"请到系统设置允许小斐 AI 使用麦克风。"];return;
            }
            NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"xf-recording.m4a"];
            NSDictionary *settings=@{AVFormatIDKey:@(kAudioFormatMPEG4AAC),
                AVSampleRateKey:@16000,AVNumberOfChannelsKey:@1,
                AVEncoderAudioQualityKey:@(AVAudioQualityMedium)};
            NSError *error=nil;
            self.recorder=[[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:path]
                                                       settings:settings error:&error];
            if(error || ![self.recorder prepareToRecord] || ![self.recorder recordForDuration:60]){
                self.status.text=@"录音无法开始";
                [self showAlert:@"录音失败" detail:error.localizedDescription?:@"检查麦克风权限及设备剩余空间。"];return;
            }
            self.isRecording=YES;
            self.recordStarted=[NSDate date];
            [self setRecordingDisplay:YES];
            [self.recordTimer invalidate];
            self.recordTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                  selector:@selector(updateRecordingClock:) userInfo:nil repeats:YES];
            self.status.text=@"正在录音，点击红色停止按钮结束";
        }];
    }];
}
- (void)transcribeRecording {
    NSDictionary *p=[self profileFor:@"stt"];if(!p)return;
    NSData *audio=[NSData dataWithContentsOfURL:self.recorder.url];
    if(!audio.length) {self.status.text=@"录音文件为空";[XFDiagnostics record:@"录音文件为空" code:0 detail:@"无音频数据"];return;}
    if(audio.length>3*1024*1024){
        self.status.text=@"录音数据超过 3MB，未上传";
        [XFDiagnostics record:@"音频超过限制" code:0 detail:@"录音超过 3MB"];
        return;
    }
    NSMutableURLRequest *req=[self requestForProfile:p];if(!req)return;
    NSString *boundary=[[NSUUID UUID] UUIDString];
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary] forHTTPHeaderField:@"Content-Type"];
    NSMutableData *body=[NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n%@\r\n",boundary,p[@"model"]] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:audio];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    req.HTTPBody=body;
    self.status.text=@"正在语音识别…";
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *resp,NSData *data,NSError *err){
        if(err){
            [XFDiagnostics record:@"语音识别网络失败" code:err.code detail:err.domain?:@""];
            self.status.text=[NSString stringWithFormat:@"语音请求失败 %ld",(long)err.code];return;
        }
        NSInteger code=[(NSHTTPURLResponse *)resp statusCode];
        NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSString *text=[json isKindOfClass:[NSDictionary class]]?json[@"text"]:nil;
        if(code>=300 || ![text isKindOfClass:[NSString class]]){
            [XFDiagnostics record:@"语音识别接口失败" code:code detail:@"API 不兼容或模型权限不足"];
            self.status.text=[NSString stringWithFormat:@"语音识别失败 HTTP %ld；查看诊断",(long)code];return;
        }
        self.message.text=text;[self textViewDidChange:self.message];self.status.text=@"已识别语音，点击发送";
    }];
}
- (void)speakLastAnswer {
    if(!self.lastAnswer.length){self.status.text=@"当前没有可朗读的回答";return;}
    NSDictionary *p=[self profileFor:@"tts"];if(!p)return;
    NSMutableURLRequest *req=[self requestForProfile:p];if(!req)return;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"model":p[@"model"],@"input":[self.lastAnswer substringToIndex:MIN((NSUInteger)2500,self.lastAnswer.length)],
       @"voice":@"alloy",@"response_format":@"mp3"} options:0 error:NULL];
    self.status.text=@"生成语音…";
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *resp,NSData *data,NSError *err){
        if(err){[XFDiagnostics record:@"朗读网络错误" code:err.code detail:err.domain?:@""];
            self.status.text=[NSString stringWithFormat:@"朗读连接失败 %ld",(long)err.code];return;}
        NSInteger status=[(NSHTTPURLResponse *)resp statusCode];
        if(status>=300 || !data.length){[XFDiagnostics record:@"朗读 API 失败" code:status detail:@"语音输出接口错误"];
            self.status.text=[NSString stringWithFormat:@"朗读接口 HTTP %ld",(long)status];return;}
        if(data.length>5*1024*1024){
            self.status.text=@"朗读音频过大，已停止播放";
            [XFDiagnostics record:@"朗读结果过大" code:0 detail:@"MP3 超过 5MB"];
            return;
        }
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
        self.player=[[AVAudioPlayer alloc] initWithData:data error:NULL];
        if(![self.player play]) {self.status.text=@"语音格式无法播放";return;}
        self.status.text=@"正在朗读";
    }];
}
- (void)generateImage {
    if(self.isWorking) return;
    NSDictionary *p=[self profileFor:@"image"];if(!p)return;
    NSString *prompt=[self.message.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!prompt.length) {self.status.text=@"请先输入生图描述";return;}
    NSMutableURLRequest *req=[self requestForProfile:p];if(!req)return;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"model":p[@"model"],@"prompt":prompt,
       @"n":@1,@"size":@"1024x1024"} options:0 error:NULL];
    self.status.text=@"正在生成图片…";
    [self setWorking:YES];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *resp,NSData *data,NSError *err){
        [self setWorking:NO];
        if(err){[XFDiagnostics record:@"生图网络错误" code:err.code detail:err.domain?:@""];
            self.status.text=[NSString stringWithFormat:@"生图网络失败 %ld",(long)err.code];return;}
        NSInteger code=[(NSHTTPURLResponse *)resp statusCode];
        if(data.length>7*1024*1024){
            [XFDiagnostics record:@"生图响应过大" code:code detail:@"返回超过 7MB"];
            self.status.text=@"图片返回过大，旧设备无法解码";return;
        }
        NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSArray *results=[json isKindOfClass:[NSDictionary class]]?json[@"data"]:nil;
        NSDictionary *first=[results isKindOfClass:[NSArray class]] && results.count?results[0]:nil;
        NSString *base64=first[@"b64_json"];
        if(code>=300 || ![base64 isKindOfClass:[NSString class]]) {
            [XFDiagnostics record:@"生图接口不兼容" code:code detail:@"需要 b64_json 字段"];
            self.status.text=[NSString stringWithFormat:@"生图失败 HTTP %ld（需要 b64_json）",(long)code];return;
        }
        NSData *bytes=[[NSData alloc] initWithBase64EncodedString:base64 options:0];
        UIImage *image=[UIImage imageWithData:bytes];
        if(!image){self.status.text=@"图片解码失败";return;}
        [self showGeneratedImage:image];
        [self appendLine:[NSString stringWithFormat:@"已生成图片：%@",prompt]];
        self.status.text=@"图片已生成，可保存到相册";
    }];
}
- (void)showGeneratedImage:(UIImage *)image {
    UIViewController *viewer=[[UIViewController alloc] init];
    viewer.view.backgroundColor=[UIColor blackColor];
    UIImageView *iv=[[UIImageView alloc] initWithFrame:viewer.view.bounds];
    iv.image=image;iv.contentMode=UIViewContentModeScaleAspectFit;
    iv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [viewer.view addSubview:iv];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:viewer];
    viewer.title=@"生成图片";
    viewer.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(closeImageViewer)];
    viewer.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"保存相册" style:UIBarButtonItemStylePlain
        target:self action:@selector(saveGeneratedImage)];
    objc_setAssociatedObject(viewer,@"XFGeneratedImage",image,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)closeImageViewer {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)saveGeneratedImage {
    UIViewController *vc=((UINavigationController *)self.presentedViewController).topViewController;
    UIImage *image=objc_getAssociatedObject(vc,@"XFGeneratedImage");
    if(image){UIImageWriteToSavedPhotosAlbum(image,nil,NULL,NULL);vc.title=@"已请求保存到相册";}
}
@end
