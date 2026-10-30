#import "XFViewController.h"
#import "XFModelsController.h"
#import "XFChatStore.h"
#import "XFHistoryController.h"
#import "XFChatView.h"
#import "XFTextImportController.h"
#import "XFPromptToolsController.h"
#import "XFCompareController.h"
#import "XFDiagnostics.h"
#import "XFJarvisController.h"
#import "XFImageGeneration.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

@interface XFViewController () <UIImagePickerControllerDelegate,UINavigationControllerDelegate,AVAudioRecorderDelegate,NSURLConnectionDataDelegate,UITextViewDelegate,AVSpeechSynthesizerDelegate>
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
@property(nonatomic,strong) UIButton *composerAttachButton;
@property(nonatomic,strong) UIButton *composerGenerateButton;
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
@property(nonatomic,strong) XFJarvisController *jarvis;
@property(nonatomic,strong) UINavigationController *jarvisNavigation;
@property(nonatomic,strong) AVSpeechSynthesizer *speechSynth;
@property(nonatomic,assign) BOOL voiceActive;
@property(nonatomic,assign) BOOL voiceCapture;
@property(nonatomic,assign) BOOL voiceAwaitingChat;
@property(nonatomic,assign) BOOL voiceAutoSpeak;
@property(nonatomic,assign) BOOL voiceContinuous;
@property(nonatomic,assign) BOOL voiceMechanical;
@property(nonatomic,assign) BOOL previousIdleTimerDisabled;
@property(nonatomic,assign) BOOL voiceSpeechDetected;
@property(nonatomic,assign) NSInteger voiceLoudSamples;
@property(nonatomic,assign) NSTimeInterval voiceLastSpeechAt;
@property(nonatomic,assign) BOOL voiceStarting;
@property(nonatomic,assign) BOOL imageGenerating;
@property(nonatomic,assign) NSUInteger imageRequestToken;
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
    self.voiceAutoSpeak=[[NSUserDefaults standardUserDefaults] objectForKey:@"xf_jarvis_auto_speak"]?
        [[NSUserDefaults standardUserDefaults] boolForKey:@"xf_jarvis_auto_speak"]:YES;
    self.voiceContinuous=[[NSUserDefaults standardUserDefaults] boolForKey:@"xf_jarvis_continuous"];
    self.voiceMechanical=[[NSUserDefaults standardUserDefaults] objectForKey:@"xf_jarvis_mechanical"]?
      [[NSUserDefaults standardUserDefaults] boolForKey:@"xf_jarvis_mechanical"]:YES;
    if(self.voiceContinuous)self.voiceAutoSpeak=YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(voiceAppWillResignActive:)
        name:UIApplicationWillResignActiveNotification object:nil];
    self.speechSynth=[[AVSpeechSynthesizer alloc] init];
    self.speechSynth.delegate=self;
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
    self.brandTitle.userInteractionEnabled=YES;
    UITapGestureRecognizer *jarvisTap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openJarvis)];
    [self.brandTitle addGestureRecognizer:jarvisTap];

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
    NSArray *items=@[@[@"◉ JARVIS",@"jarvis"],@[@"＋ 新对话",@"new"],@[@"≡ 文本",@"file"],
      @[@"● 录音",@"record"],@[@"♪ 朗读",@"tts"],@[@"生图协议",@"imagemode"],@[@"◎ 联网",@"web"],@[@"复制回复",@"copyreply"],@[@"提示词",@"prompts"],@[@"双模型",@"compare"],@[@"诊断",@"diagnostics"]];
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
    self.composerAttachButton=[UIButton buttonWithType:UIButtonTypeCustom];
    [self.composerAttachButton setTitle:@"＋" forState:UIControlStateNormal];
    self.composerAttachButton.titleLabel.font=[UIFont systemFontOfSize:24];
    [self styleNavigationButton:self.composerAttachButton filled:NO];
    [self.composerAttachButton addTarget:self action:@selector(composerAttachTapped)
        forControlEvents:UIControlEventTouchUpInside];
    [self.footerBar addSubview:self.composerAttachButton];

    self.composerGenerateButton=[UIButton buttonWithType:UIButtonTypeCustom];
    [self.composerGenerateButton setTitle:@"生图" forState:UIControlStateNormal];
    self.composerGenerateButton.titleLabel.font=[UIFont boldSystemFontOfSize:12.5];
    [self styleNavigationButton:self.composerGenerateButton filled:NO];
    [self.composerGenerateButton addTarget:self action:@selector(generateImage)
        forControlEvents:UIControlEventTouchUpInside];
    [self.footerBar addSubview:self.composerGenerateButton];

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
    [UIApplication sharedApplication].idleTimerDisabled=self.voiceActive?self.previousIdleTimerDisabled:[UIApplication sharedApplication].idleTimerDisabled;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.connection cancel];
    [self.recordTimer invalidate];
    [self.speechSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
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
    // Image actions remain visible with the keyboard; text paste lives in the + menu.
    self.pasteButton.hidden=YES;
    CGFloat top=typing?0:88;
    BOOL hasImage=self.pendingImage!=nil;
    CGFloat footerHeight=typing?MIN(hasImage?110:62,availableBottom):(hasImage?192:125);
    CGFloat footerY=MAX(0,availableBottom-footerHeight);
    self.chat.frame=CGRectMake(0,top,w,MAX(0,footerY-top));
    self.footerBar.frame=CGRectMake(0,footerY,w,footerHeight);
    self.recordingBadge.frame=CGRectMake(6,typing?4:94,w-12,30);
    if(typing){
        CGFloat margin=7,gap=5,attachW=35,generateW=45,sendW=54;
        CGFloat inputW=MAX(80,w-2*margin-3*gap-attachW-generateW-sendW);
        CGFloat y=hasImage?MAX(2,footerHeight-48):MAX(2,(footerHeight-44)/2);
        self.composerAttachButton.frame=CGRectMake(margin,y,attachW,44);
        self.message.frame=CGRectMake(margin+attachW+gap,y,inputW,44);
        self.messagePlaceholder.frame=CGRectMake(margin+attachW+gap+11,y+6,inputW-15,27);
        self.composerGenerateButton.frame=CGRectMake(margin+attachW+gap+inputW+gap,y,generateW,44);
        self.sendButton.frame=CGRectMake(w-margin-sendW,y,sendW,44);
    } else {
        self.tools.frame=CGRectMake(10,7,w-20,42);
        CGFloat inputY=hasImage?130:57;
        CGFloat margin=8,gap=5,attachW=36,generateW=45,sendW=57;
        CGFloat inputW=MAX(82,w-2*margin-3*gap-attachW-generateW-sendW);
        self.composerAttachButton.frame=CGRectMake(margin,inputY+3,attachW,45);
        self.message.frame=CGRectMake(margin+attachW+gap,inputY,inputW,53);
        self.messagePlaceholder.frame=CGRectMake(margin+attachW+gap+11,inputY+8,inputW-17,26);
        self.composerGenerateButton.frame=CGRectMake(margin+attachW+gap+inputW+gap,inputY+3,generateW,44);
        self.sendButton.frame=CGRectMake(w-margin-sendW,inputY+3,sendW,44);
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
- (void)composerAttachTapped {
    [self.message resignFirstResponder];
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"添加到对话"
      message:@"可以从相册或剪贴板添加图片" preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"选择相册图片" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        [self pickImage];
    }]];
    UIImage *pasted=[UIPasteboard generalPasteboard].image;
    if(pasted){
        [menu addAction:[UIAlertAction actionWithTitle:@"粘贴图片" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            [self attachImage:pasted];
        }]];
    }
    if([UIPasteboard generalPasteboard].string.length){
        [menu addAction:[UIAlertAction actionWithTitle:@"粘贴文字" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            [self pasteTapped];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
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
    BOOL recovered=NO;
    if(!self.message.text.length && self.lastSubmittedDraft.length){
        self.message.text=self.lastSubmittedDraft;
        [self textViewDidChange:self.message];
        recovered=YES;
    }
    if(!self.pendingImage && self.sendingImageName.length){
        UIImage *saved=[XFChatStore imageForName:self.sendingImageName];
        if(saved){self.pendingImage=saved;[self layoutForKeyboard:self.keyboardOffset];recovered=YES;}
    }
    if(recovered)self.status.text=@"请求失败，已恢复文字及图片附件";
}
- (void)showAlert:(NSString *)title detail:(NSString *)detail {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *presenter=(self.voiceActive && self.jarvisNavigation)?self.jarvisNavigation:self;
    [presenter presentViewController:a animated:YES completion:nil];
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
    self.composerGenerateButton.enabled=!value;
    self.composerGenerateButton.alpha=value?.45:1.0;
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
    if([name isEqualToString:@"jarvis"]) {[self openJarvis];return;}
    if([name isEqualToString:@"photo"]) {[self pickImage];return;}
    if([name isEqualToString:@"file"]) {[self pickFile];return;}
    if([name isEqualToString:@"prompts"]) {[self showPromptToolbox];return;}
    if([name isEqualToString:@"compare"]) {[self showComparison];return;}
    if([name isEqualToString:@"diagnostics"]) {[self showDiagnostics];return;}
    if([name isEqualToString:@"record"]) {[self toggleRecord];return;}
    if([name isEqualToString:@"tts"]) {[self speakLastAnswer];return;}
    if([name isEqualToString:@"image"]) {[self generateImage];return;}
    if([name isEqualToString:@"imagemode"]) {[self chooseImageProtocol:NO profile:nil prompt:nil];return;}
    if([name isEqualToString:@"web"]) {[self sendAsSearch];return;}
}
- (void)voiceUpdate:(NSString *)mode message:(NSString *)message {
    if(!self.voiceActive || !self.jarvis)return;
    [self.jarvis updateMode:mode description:message];
}
- (void)voiceError:(NSString *)detail {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(voiceResumeListening) object:nil];
    if(self.voiceContinuous){
        self.voiceContinuous=NO;
        self.jarvis.continuousTalk=NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"xf_jarvis_continuous"];
    }
    self.voiceCapture=NO;
    self.voiceAwaitingChat=NO;
    self.voiceStarting=NO;
    [self voiceUpdate:@"idle" message:detail?:@"出现错误，请检查配置后重试"];
}
- (void)openJarvis {
    if(self.voiceActive)return;
    [self.message resignFirstResponder];
    self.voiceActive=YES;
    self.previousIdleTimerDisabled=[UIApplication sharedApplication].idleTimerDisabled;
    [UIApplication sharedApplication].idleTimerDisabled=YES;
    self.voiceCapture=NO;
    self.voiceAwaitingChat=NO;
    self.voiceStarting=NO;
    XFJarvisController *controller=[[XFJarvisController alloc] init];
    self.jarvis=controller;
    controller.autoSpeak=self.voiceAutoSpeak;
    controller.continuousTalk=self.voiceContinuous;
    controller.mechanicalVoice=self.voiceMechanical;
    __weak XFViewController *weakSelf=self;
    controller.onPrimary=^{[weakSelf voicePrimaryTapped];};
    controller.onStop=^{[weakSelf voiceStopTapped];};
    controller.onTease=^{[weakSelf voiceTeaseTapped];};
    controller.onContinuousTalk=^(BOOL on){
        weakSelf.voiceContinuous=on;
        [NSObject cancelPreviousPerformRequestsWithTarget:weakSelf selector:@selector(voiceResumeListening) object:nil];
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"xf_jarvis_continuous"];
        if(on && !weakSelf.voiceAutoSpeak){
            weakSelf.voiceAutoSpeak=YES;
            weakSelf.jarvis.autoSpeak=YES;
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xf_jarvis_auto_speak"];
        }
        if(on && !weakSelf.isRecording && !weakSelf.isWorking && ![weakSelf.speechSynth isSpeaking])
            [weakSelf voiceUpdate:@"idle" message:@"连聊已开启。点击开始说话，之后会自动接着听。"];
    };
    controller.onMechanicalVoice=^(BOOL on){
        weakSelf.voiceMechanical=on;
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"xf_jarvis_mechanical"];
    };
    controller.onClose=^{[weakSelf closeJarvis];};
    controller.onAutoSpeak=^(BOOL on){
        weakSelf.voiceAutoSpeak=on;
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"xf_jarvis_auto_speak"];
        if(!on){
            weakSelf.voiceContinuous=NO;
            weakSelf.jarvis.continuousTalk=NO;
            [NSObject cancelPreviousPerformRequestsWithTarget:weakSelf selector:@selector(voiceResumeListening) object:nil];
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"xf_jarvis_continuous"];
        }
        if(!on && [weakSelf.speechSynth isSpeaking]){
            [weakSelf.speechSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
            [weakSelf voiceUpdate:@"idle" message:@"已停止朗读，可以再次提问"];
        }
    };
    self.jarvisNavigation=[[UINavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:self.jarvisNavigation animated:YES completion:nil];
}
- (void)closeJarvis {
    if(!self.voiceActive)return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(voiceResumeListening) object:nil];
    [UIApplication sharedApplication].idleTimerDisabled=self.previousIdleTimerDisabled;
    self.voiceActive=NO;
    self.voiceCapture=NO;
    self.voiceAwaitingChat=NO;
    self.voiceStarting=NO;
    if(self.isRecording){
        [self.recorder stop];
        self.isRecording=NO;
        [self.recordTimer invalidate];self.recordTimer=nil;
        [self setRecordingDisplay:NO];
    }
    [self.speechSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    [self.jarvisNavigation dismissViewControllerAnimated:YES completion:nil];
    self.jarvisNavigation=nil;
    self.jarvis=nil;
}
- (void)voiceTeaseTapped {
    if(!self.voiceActive || self.isWorking || self.isRecording || self.voiceAwaitingChat)return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(voiceResumeListening) object:nil];
    [self.speechSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    self.message.text=@"我有点无聊。请以小斐的冷幽默风格，吐槽我一句，或者讲一个简短的奇怪笑话，30到70字。";
    [self textViewDidChange:self.message];
    self.voiceAwaitingChat=YES;
    [self voiceUpdate:@"thinking" message:@"正在扫描你的无聊程度…"];
    [self sendChat:NO];
    if(!self.isWorking)self.voiceAwaitingChat=NO;
}
- (void)voicePrimaryTapped {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(voiceResumeListening) object:nil];
    if(!self.voiceActive || self.voiceStarting)return;
    if(self.isRecording){[self finishRecording];return;}
    if(self.voiceAwaitingChat || self.isWorking)return;
    if([self.speechSynth isSpeaking])
        [self.speechSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    NSDictionary *stt=[XFModelsController activeProfileForCapability:@"stt"];
    NSDictionary *chat=[XFModelsController activeProfileForCapability:@"chat"];
    if(!chat){[self voiceError:@"请先在模型库选择文字聊天模型"];return;}
    if(!stt || ![XFModelsController secretForProfile:stt].length){
        [self voiceError:@"请先在模型库配置语音识别（STT）模型与 API Key"];
        return;
    }
    self.voiceCapture=YES;
    self.voiceStarting=YES;
    [self voiceUpdate:@"transcribing" message:@"正在申请麦克风权限…"];
    [self toggleRecord];
}
- (void)voiceStopTapped {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(voiceResumeListening) object:nil];
    self.voiceContinuous=NO;
    self.jarvis.continuousTalk=NO;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"xf_jarvis_continuous"];
    self.voiceCapture=NO;
    self.voiceAwaitingChat=NO;
    self.voiceStarting=NO;
    if(self.isRecording){
        [self.recorder stop];self.isRecording=NO;
        [self.recordTimer invalidate];self.recordTimer=nil;
        [self setRecordingDisplay:NO];
    }
    if(self.isWorking){
        [self.connection cancel];self.connection=nil;[self setWorking:NO];
        [self restoreSubmittedDraft];
    }
    if([self.speechSynth isSpeaking])
        [self.speechSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    [self voiceUpdate:@"idle" message:@"已停止，点击开始说话"];
}
- (void)voiceReadAnswer:(NSString *)answer {
    if(!self.voiceActive || !self.voiceAutoSpeak){
        [self voiceUpdate:@"idle" message:@"已生成回答，可再次提问"];return;
    }
    NSString *plain=[answer stringByReplacingOccurrencesOfString:@"\n" withString:@"。"];
    if(plain.length>900)plain=[plain substringToIndex:900];
    if(!plain.length){[self voiceUpdate:@"idle" message:@"回答为空"];return;}
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [self.speechSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    AVSpeechUtterance *utterance=[AVSpeechUtterance speechUtteranceWithString:plain];
    utterance.voice=[AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
    utterance.rate=self.voiceMechanical?0.44f:0.49f;
    utterance.pitchMultiplier=self.voiceMechanical?0.87f:1.08f;
    utterance.volume=0.95f;
    [self voiceUpdate:@"speaking" message:@"正在朗读回答；点击停止可以中断"];
    [self.speechSynth speakUtterance:utterance];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer utterance:(AVSpeechUtterance *)utterance willSpeakRangeOfSpeechString:(NSRange)characterRange {
    if(!self.voiceActive || !self.jarvis)return;
    [self.jarvis updateSpeechPulse];
    NSString *text=utterance.speechString;
    if(characterRange.location==NSNotFound || characterRange.location>=text.length)return;
    NSUInteger start=characterRange.location>9?characterRange.location-9:0;
    NSUInteger end=MIN(text.length,NSMaxRange(characterRange)+18);
    if(end>start){
        NSRange safe=[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(start,end-start)];
        [self.jarvis updateSpeechText:[text substringWithRange:safe]];
    }
}
- (void)voiceResumeListening {
    if(!self.voiceActive || !self.voiceContinuous || !self.voiceAutoSpeak ||
       [UIApplication sharedApplication].applicationState!=UIApplicationStateActive ||
       !self.jarvis.isViewLoaded || !self.jarvis.view.window ||
       self.voiceStarting || self.voiceAwaitingChat || self.isWorking || self.isRecording ||
       [self.speechSynth isSpeaking])return;
    [self voicePrimaryTapped];
}
- (void)voiceAppWillResignActive:(NSNotification *)note {
    if(self.voiceActive)[self voiceStopTapped];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if(!self.voiceActive)return;
    if(self.voiceContinuous && self.voiceAutoSpeak) {
        [self voiceUpdate:@"idle" message:@"连聊中… 正在重新打开麦克风"];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(voiceResumeListening) object:nil];
        [self performSelector:@selector(voiceResumeListening) withObject:nil afterDelay:0.85];
    } else [self voiceUpdate:@"idle" message:@"回答结束，点击开始继续提问"];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(voiceResumeListening) object:nil];
    if(self.voiceActive && !self.voiceCapture && !self.voiceAwaitingChat && ![synthesizer isSpeaking])
        [self voiceUpdate:@"idle" message:@"已停止朗读"];
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
        if(self.imageGenerating){
            self.imageRequestToken++;
            self.imageGenerating=NO;
            [self setWorking:NO];
            self.status.text=@"已停止显示本次生图结果（服务器可能仍在生成并计费）";
            return;
        }
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
    NSDictionary *profile=nil;
    if(self.pendingImage && !web){
        // Prefer the explicit vision model. A multimodal chat model also accepts image_url.
        profile=[XFModelsController activeProfileForCapability:@"vision"];
        if(!profile){
            NSDictionary *chat=[XFModelsController activeProfileForCapability:@"chat"];
            if([chat[@"supports_image"] boolValue])profile=chat;
        }
        if(!profile){
            [self showAlert:@"请选择图片理解模型" detail:@"当前聊天模型没有声明图片输入能力。打开「模型库 > 视觉」，选择支持图片理解的模型后，可直接发送此图。图片与输入文字都会保留。"];
            return;
        }
    }else{
        profile=[self profileFor:web?@"web":@"chat"];
    }
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
    if(self.voiceAwaitingChat)
        msg=[NSString stringWithFormat:@"请用自然、简短、清晰的中文口语回答，尽量不超过150字。问题：%@",msg];
    NSString *imageName=nil;
    if(self.pendingFileText.length) {
        msg=[NSString stringWithFormat:@"%@\n\n以下为文档内容：\n%@",msg,self.pendingFileText];
        sent=[sent stringByAppendingString:@" [文本文件]"];
    }
    NSString *karenPrompt=@"你是小斐，一位住在复古电脑终端里的中文AI伙伴。个性冷静、聪明、有一点毒舌和自嘲，偶尔用一句简短吐槽或荒诞笑话解闷，风格参考经典复古科幻电脑角色；不要冒充真实人物。保持尊重，避免人身攻击。用户认真求助时请给准确有效的答案，遇到不确定信息直说。回答尽量口语化，不啰嗦。";
    BOOL karenMode=self.voiceActive;
    NSMutableArray *messages=[NSMutableArray arrayWithObject:@{@"role":@"system",@"content":karenMode?karenPrompt:@"你是小斐，中文智能助手。准确回答问题，信息不确定时如实说明。"}];
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
        imageName=[XFChatStore saveImage:resized];
        if(!imageName.length){
            self.status.text=@"保存图片预览失败，请检查剩余空间";
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
    if(compatible && messages.count && [messages[0][@"role"] isEqualToString:@"system"]){
        [messages removeObjectAtIndex:0];
        // Certain providers reject system-role messages. Keep persona in user text.
        if(karenMode && !self.pendingImage && messages.count){
            NSUInteger last=messages.count-1;
            NSDictionary *tail=messages[last];
            if([tail[@"role"] isEqualToString:@"user"] && [tail[@"content"] isKindOfClass:[NSString class]]){
                messages[last]=@{@"role":@"user",@"content":[NSString stringWithFormat:@"%@\n\n%@",karenPrompt,tail[@"content"]]};
            }
        }
    }
    NSMutableDictionary *payload=[@{@"model":profile[@"model"],@"messages":messages,@"stream":[NSNumber numberWithBool:!compatible]} mutableCopy];
    if(web && !compatible) payload[@"web_search_options"]=@{};
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    self.lastChatRequest=[req mutableCopy];
    self.lastChatProfile=profile;
    self.usingCompatibilityMode=compatible;
    self.lastChatUsedSearch=web;
    self.sendingContent=sent;
    self.sendingImageName=imageName;
    self.lastSubmittedDraft=self.message.text?:@"";
    [self.message resignFirstResponder];self.message.text=@"";
    [self textViewDidChange:self.message];
    self.pendingFileText=nil;self.pendingImage=nil;
    [self layoutForKeyboard:self.keyboardOffset];
    if(imageName.length)[self.chat addImageMessage:sent imageName:imageName];
    else [self appendLine:[NSString stringWithFormat:@"我：%@",sent]];
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
        if(self.voiceAwaitingChat)[self voiceError:@"回答数据太大，已停止以保护设备"];
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
    if(self.voiceAwaitingChat)[self voiceError:@"聊天连接失败，检查网络或 HTTPS"];
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
        if(self.voiceAwaitingChat && self.voiceActive){
            [self voiceError:[NSString stringWithFormat:@"HTTP %ld：%@",(long)self.httpCode,
               reason.length>85?[reason substringToIndex:85]:reason]];
        } else [self showAPIErrorWithReason:reason status:self.httpCode];
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
        if(self.voiceAwaitingChat)[self voiceError:@"模型没有返回可朗读的文字"];
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
    if(self.voiceAwaitingChat){
        self.voiceAwaitingChat=NO;
        [self voiceReadAnswer:answer];
    }
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
        if([first isKindOfClass:[NSDictionary class]] && [first[@"role"] isEqualToString:@"system"]){
            NSString *instructions=[first[@"content"] isKindOfClass:[NSString class]]?first[@"content"]:nil;
            [messages removeObjectAtIndex:0];
            if(self.voiceActive && instructions.length && messages.count) {
                NSUInteger last=messages.count-1;
                NSDictionary *tail=messages[last];
                if([tail[@"role"] isEqualToString:@"user"] && [tail[@"content"] isKindOfClass:[NSString class]]){
                    messages[last]=@{@"role":@"user",@"content":[NSString stringWithFormat:@"%@\n\n%@",instructions,tail[@"content"]]};
                }
            }
        }
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
    [self.message resignFirstResponder];
    if(![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]){
        [self showAlert:@"相册不可用" detail:@"请检查照片权限，也可以通过左侧＋号粘贴图片。"];
        return;
    }
    UIImagePickerController *picker=[[UIImagePickerController alloc] init];
    picker.delegate=self;
    picker.sourceType=UIImagePickerControllerSourceTypePhotoLibrary;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)attachImage:(UIImage *)img {
    if(!img || img.size.width<1 || img.size.height<1){
        self.status.text=@"图片读取失败";return;
    }
    // Keep the 512MB iPhone 4S within a bounded decode and upload size.
    CGFloat scale=MIN(1.0,640.0/MAX(img.size.width,img.size.height));
    CGSize size=CGSizeMake(MAX(1,round(img.size.width*scale)),MAX(1,round(img.size.height*scale)));
    UIGraphicsBeginImageContextWithOptions(size,YES,1.0);
    [img drawInRect:CGRectMake(0,0,size.width,size.height)];
    self.pendingImage=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [self layoutForKeyboard:0];
    self.status.text=self.pendingImage?@"图片已添加，输入问题并点击发送":@"图片读取失败";
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *img=info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        [self attachImage:img];
    }];
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
    if(self.voiceCapture && self.voiceActive) {
        [self.recorder updateMeters];
        float db=[self.recorder averagePowerForChannel:0];
        float level=MAX(0,MIN(1,(db+53.0f)/48.0f));
        [self.jarvis updateMeter:level seconds:seconds];
        if(self.voiceContinuous){
            // Energy-based end-of-utterance detection. The old phone does not
            // need any local ASR model. Manual tap still works in noisy rooms.
            if(level>0.35f){
                self.voiceLoudSamples++;
                if(self.voiceLoudSamples>=2)self.voiceSpeechDetected=YES;
                if(self.voiceSpeechDetected)self.voiceLastSpeechAt=elapsed;
            }else self.voiceLoudSamples=0;
            if(self.voiceSpeechDetected && elapsed-self.voiceLastSpeechAt>=1.7){
                [self finishRecording];
                return;
            }
            if(!self.voiceSpeechDetected && elapsed>=12){
                [self voiceStopTapped];
                [self voiceUpdate:@"idle" message:@"暂时没有听到说话，连聊已暂停。"];
                return;
            }
        }
    }
    if(seconds>=60)[self finishRecording];
}
- (void)finishRecording {
    if(!self.isRecording)return;
    self.isRecording=NO;
    [self.recorder stop];
    [self.recordTimer invalidate];self.recordTimer=nil;
    [self setRecordingDisplay:NO];
    self.status.text=@"录音结束，正在识别语音…";
    if(self.voiceCapture)[self voiceUpdate:@"transcribing" message:@"录音已结束，正在转换为文字…"];
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
        if(self.voiceCapture)[self voiceError:@"麦克风无法启动，请检查录音权限"];
        else [self showAlert:@"无法启动录音" detail:sessionError.localizedDescription];
        return;
    }
    self.status.text=@"正在请求麦克风权限…";
    [session requestRecordPermission:^(BOOL granted) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if(self.voiceActive && !self.voiceCapture)return;
            if(!granted){
                self.status.text=@"未获得麦克风权限";
                if(self.voiceCapture)[self voiceError:@"没有麦克风权限，请到系统设置中开启"];
                else [self showAlert:@"没有麦克风权限" detail:@"请到系统设置允许小斐 AI 使用麦克风。"];
                return;
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
                if(self.voiceCapture)[self voiceError:@"录音启动失败，请检查存储空间与系统权限"];
                else [self showAlert:@"录音失败" detail:error.localizedDescription?:@"检查麦克风权限及设备剩余空间。"];
                return;
            }
            self.isRecording=YES;
            self.voiceStarting=NO;
            self.recordStarted=[NSDate date];
            self.voiceSpeechDetected=NO;
            self.voiceLoudSamples=0;
            self.voiceLastSpeechAt=0;
            if(self.voiceCapture)[self voiceUpdate:@"listening" message:self.voiceContinuous?@"请直接说话，停顿约两秒后自动发送":@"请说话，结束后点击「结束并提问」"];
            self.recorder.meteringEnabled=YES;
            [self setRecordingDisplay:YES];
            [self.recordTimer invalidate];
            self.recordTimer=[NSTimer scheduledTimerWithTimeInterval:(self.voiceContinuous?0.35:1.0) target:self
                  selector:@selector(updateRecordingClock:) userInfo:nil repeats:YES];
            self.status.text=self.voiceContinuous?@"连聊录音中，说完停顿即可自动发送":@"正在录音，点击红色停止按钮结束";
        }];
    }];
}
- (void)transcribeRecording {
    BOOL wasVoice=self.voiceCapture;
    NSDictionary *p=[self profileFor:@"stt"];
    if(!p){if(wasVoice)[self voiceError:@"没有语音识别模型"];return;}
    NSData *audio=[NSData dataWithContentsOfURL:self.recorder.url];
    if(!audio.length) {
        self.status.text=@"录音文件为空";[XFDiagnostics record:@"录音文件为空" code:0 detail:@"无音频数据"];
        if(wasVoice)[self voiceError:@"没有录到声音，请重新尝试"];return;
    }
    if(audio.length>3*1024*1024){
        self.status.text=@"录音数据超过 3MB，未上传";
        [XFDiagnostics record:@"音频超过限制" code:0 detail:@"录音超过 3MB"];
        if(wasVoice)[self voiceError:@"录音过长，请缩短后重试"];
        return;
    }
    NSMutableURLRequest *req=[self requestForProfile:p];
    if(!req){if(wasVoice)[self voiceError:@"请检查语音识别 API 配置"];return;}
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
        if(wasVoice && (!self.voiceActive || !self.voiceCapture))return;
        if(err){
            [XFDiagnostics record:@"语音识别网络失败" code:err.code detail:err.domain?:@""];
            self.status.text=[NSString stringWithFormat:@"语音请求失败 %ld",(long)err.code];
            if(wasVoice)[self voiceError:@"语音识别连接失败，请检查网络"];
            return;
        }
        NSInteger code=[(NSHTTPURLResponse *)resp statusCode];
        NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSString *text=[json isKindOfClass:[NSDictionary class]]?json[@"text"]:nil;
        if(code>=300 || ![text isKindOfClass:[NSString class]]){
            [XFDiagnostics record:@"语音识别接口失败" code:code detail:@"API 不兼容或模型权限不足"];
            self.status.text=[NSString stringWithFormat:@"语音识别失败 HTTP %ld；查看诊断",(long)code];
            if(wasVoice)[self voiceError:[NSString stringWithFormat:@"语音识别错误 HTTP %ld，请检查 STT 模型",(long)code]];
            return;
        }
        if(!text.length){if(wasVoice)[self voiceError:@"没有识别出文字，请再试一次"];return;}
        self.message.text=text;[self textViewDidChange:self.message];
        self.status.text=@"已识别语音，点击发送";
        if(wasVoice) {
            self.voiceCapture=NO;
            self.voiceAwaitingChat=YES;
            [self voiceUpdate:@"thinking" message:@"已识别，正在生成回答…"];
            [self sendChat:NO];
            if(!self.isWorking)[self voiceError:@"无法发送，请检查聊天模型配置"];
        }
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
- (NSString *)imageProtocolKey:(NSDictionary *)profile {
    NSString *account=profile[@"account_id"]?:@"";
    return [@"xf_image_generation_protocol_v1_" stringByAppendingString:account];
}
- (void)chooseImageProtocol:(BOOL)start profile:(NSDictionary *)profile prompt:(NSString *)prompt {
    NSDictionary *p=profile?:[XFModelsController activeProfileForCapability:@"image"];
    if(!p){
        [self showAlert:@"尚未选择生图模型" detail:@"打开模型库，将生图模型分类为「图片生成」并选中，然后再试。"];
        return;
    }
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"选择生图接口协议"
       message:[NSString stringWithFormat:@"当前：%@\n标准图片 API 适用于 OpenAI / 千问及 OpenRouter Images；聊天式生图适用于部分 Gemini、OpenRouter 模型。\n\n只会执行你选择的方式，不会自动重复扣费。",p[@"model"]?:@"未命名模型"]
       preferredStyle:UIAlertControllerStyleAlert];
    __weak XFViewController *weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"标准图像 API（推荐）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        [[NSUserDefaults standardUserDefaults] setObject:@"images" forKey:[weakSelf imageProtocolKey:p]];
        weakSelf.status.text=@"已选择标准图像接口";
        if(start)[weakSelf startImageGenerationWithProfile:p prompt:prompt chat:NO];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"聊天式生图 API" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        [[NSUserDefaults standardUserDefaults] setObject:@"chat" forKey:[weakSelf imageProtocolKey:p]];
        weakSelf.status.text=@"已选择聊天式生图接口";
        if(start)[weakSelf startImageGenerationWithProfile:p prompt:prompt chat:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)generateImage {
    if(self.isWorking)return;
    if(self.pendingImage){
        [self showAlert:@"当前已附加图片" detail:@"点击「发送」可将图片交给视觉模型分析。当前生图功能根据文字描述创建新图片，暂不支持参考图修改。请先移除附件再生图。"];
        return;
    }
    NSDictionary *profile=[XFModelsController activeProfileForCapability:@"image"];
    if(!profile){
        [self showAlert:@"无法生图：尚未选择模型"
             detail:@"进入「切换模型」，选择「图片生成」分类，点选一个有权限的生图模型。聊天模型和视觉识图模型不一定支持生图。"];
        return;
    }
    NSString *prompt=[self.message.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!prompt.length){
        self.status.text=@"请先输入生图描述";
        return;
    }
    if(prompt.length>5000){
        [self showAlert:@"生图提示词过长" detail:@"请将描述缩短至 5000 字以内。"];
        return;
    }
    NSString *mode=[[NSUserDefaults standardUserDefaults] stringForKey:[self imageProtocolKey:profile]];
    if(![@[@"images",@"chat"] containsObject:mode]){
        // First use: pick a single protocol without another modal.
        NSString *mid=[profile[@"model"] lowercaseString]?:@"";
        NSString *host=[[NSURL URLWithString:profile[@"endpoint"]] host].lowercaseString?:@"";
        BOOL chatStyle=([host hasSuffix:@"openrouter.ai"] && [mid containsString:@"gemini"]);
        mode=chatStyle?@"chat":@"images";
        [[NSUserDefaults standardUserDefaults] setObject:mode forKey:[self imageProtocolKey:profile]];
    }
    [self startImageGenerationWithProfile:profile prompt:prompt chat:[mode isEqualToString:@"chat"]];
}
- (void)startImageGenerationWithProfile:(NSDictionary *)p prompt:(NSString *)prompt chat:(BOOL)chat {
    if(self.isWorking)return;
    NSString *key=[XFModelsController secretForProfile:p];
    if(!key.length) {
        [self showAlert:@"生图密钥未配置" detail:@"请在 API 管理中填写有效 API Key。"];
        return;
    }
    NSString *endpoint=chat?(p[@"chat_endpoint"]?:@""):p[@"endpoint"];
    NSURL *endpointURL=[NSURL URLWithString:endpoint];
    if(![[endpointURL.scheme lowercaseString] isEqualToString:@"https"] || !endpointURL.host.length){
        [self showAlert:@"生图接口地址无效" detail:@"请检查当前 API 服务的 base URL 是否正确，并使用 HTTPS。"];
        return;
    }
    self.imageRequestToken++;
    NSUInteger token=self.imageRequestToken;
    self.imageGenerating=YES;
    [self setWorking:YES];
    [self.message resignFirstResponder];
    [self.chat addMessage:[NSString stringWithFormat:@"生成图片：%@",prompt] fromUser:YES];
    self.status.text=chat?@"正在通过聊天式接口生图…":@"正在通过图像接口生图…";
    __weak XFViewController *weakSelf=self;
    [XFImageGeneration generateWithEndpoint:endpoint model:p[@"model"] apiKey:key prompt:prompt
       chatMode:chat completion:^(UIImage *image,NSString *reason,NSInteger statusCode){
        XFViewController *controller=weakSelf;
        if(!controller || token!=controller.imageRequestToken)return;
        controller.imageGenerating=NO;
        [controller setWorking:NO];
        if(!image){
            NSString *safeReason=reason?:@"生图失败";
            if(key.length)safeReason=[safeReason stringByReplacingOccurrencesOfString:key withString:@"[密钥已隐藏]"];
            NSString *shortReason=safeReason.length>330?[safeReason substringToIndex:330]:safeReason;
            [XFDiagnostics record:@"生图失败" code:statusCode
                             detail:[NSString stringWithFormat:@"模式：%@，服务：%@",
                               chat?@"聊天式":@"标准",p[@"provider"]?:@"API"]];
            controller.status.text=@"生图失败，点击「生图协议」可切换接口";
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:
                [NSString stringWithFormat:@"生图失败 · %@",chat?@"聊天式":@"标准图片"]
                message:[NSString stringWithFormat:@"模型：%@\n接口：%@\n原因：%@",
                         p[@"model"]?:@"",endpointURL.host?:@"",shortReason]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"复制原因" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
                [UIPasteboard generalPasteboard].string=safeReason;
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"切换生图协议" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
                [controller chooseImageProtocol:NO profile:p prompt:nil];
            }]];
            [controller presentViewController:alert animated:YES completion:nil];
            return;
        }
        NSString *filename=[XFChatStore saveImage:image];
        NSString *requestText=[NSString stringWithFormat:@"生成图片：%@",prompt];
        NSString *description=@"图片已生成，点击图片预览或保存到相册。";
        [controller.history addObject:@{@"role":@"user",@"content":requestText}];
        if(filename.length){
            [controller.chat addGeneratedImageMessage:description imageName:filename];
            [controller.history addObject:@{@"role":@"assistant",
                   @"content":description,@"image_file":filename}];
        } else{
            [controller.chat showNotice:@"图片已生成，但本地保存失败。请检查剩余空间。"];
        }
        [XFChatStore saveConversationID:controller.conversationID messages:controller.history];
        if([controller.message.text isEqualToString:prompt]){
            controller.message.text=@"";
            [controller textViewDidChange:controller.message];
        }
        controller.status.text=filename.length?@"生图完成，图片已显示在对话中":@"图片保存失败，请检查手机存储空间";
        // The result stays inline. Tap the thumbnail to open the full-size viewer.
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
