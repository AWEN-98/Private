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
#import "XFTheme.h"
#import "XFActionHubController.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

// Qwen3-ASR-Flash uses OpenAI-compatible Chat Completions with input_audio.
// Other STT providers continue using multipart /audio/transcriptions.
static BOOL XFUsesOpenRouterSTT(NSDictionary *profile) {
    NSURL *url=[NSURL URLWithString:profile[@"endpoint"]?:@""];
    return [[url.host lowercaseString] hasSuffix:@"openrouter.ai"];
}
static BOOL XFUsesQwen3ASR(NSDictionary *profile) {
    NSString *model=[profile[@"model"] isKindOfClass:[NSString class]]?[profile[@"model"] lowercaseString]:@"";
    // Providers sometimes prefix the model ID with a namespace.
    return [model containsString:@"qwen3-asr-flash"] && ![model containsString:@"filetrans"];
}
// Official Alibaba Cloud compatible-mode routing. For third-party gateways,
// preserve the configured host and endpoint; never silently switch providers.
static BOOL XFIsAlibabaASRHost(NSString *host) {
    NSString *h=[host lowercaseString]?:@"";
    return [h isEqualToString:@"dashscope.aliyuncs.com"] ||
        [h isEqualToString:@"dashscope-intl.aliyuncs.com"] ||
        [h hasSuffix:@".maas.aliyuncs.com"];
}
static BOOL XFUsesDashScopeAudioASR(NSDictionary *profile) {
    NSString *name=[profile[@"model"] lowercaseString]?:@"";
    NSURL *chat=[NSURL URLWithString:profile[@"chat_endpoint"]?:@""];
    BOOL type=[name containsString:@"qwen-audio-3.1-asr-flash"] ||
        [name containsString:@"qwen-audio-3.0-asr-flash"] ||
        [name containsString:@"fun-asr-flash"];
    return type && ![name containsString:@"filetrans"] &&
        XFIsAlibabaASRHost(chat.host);
}
static NSURL *XFQwenASRURL(NSDictionary *profile) {
    // A custom STT endpoint is explicitly configured for the selected provider.
    NSString *overridden=profile[@"stt_override"];
    if([overridden isKindOfClass:[NSString class]] && overridden.length)
        return [NSURL URLWithString:overridden];
    NSURL *configured=[NSURL URLWithString:profile[@"chat_endpoint"]?:@""];
    if(![[configured.scheme lowercaseString] isEqualToString:@"https"] || !configured.host.length)return nil;
    if(XFIsAlibabaASRHost(configured.host)){
        NSString *target=[NSString stringWithFormat:@"https://%@/compatible-mode/v1/chat/completions",configured.host];
        return [NSURL URLWithString:target];
    }
    return configured;
}
static NSString *XFASRSafeEndpoint(NSURL *url){
    if(!url)return @"未知地址";
    // No query string, credentials, audio data, or token details in diagnostics.
    return [NSString stringWithFormat:@"%@%@",url.host?:@"未知域名",url.path?:@"/"];
}
static NSString *XFASRReadableText(id value) {
    if([value isKindOfClass:[NSString class]])return (NSString *)value;
    if(![value isKindOfClass:[NSArray class]])return nil;
    NSMutableString *joined=[NSMutableString string];
    for(id part in (NSArray *)value){
        if(![part isKindOfClass:[NSDictionary class]])continue;
        NSString *piece=[part[@"text"] isKindOfClass:[NSString class]]?part[@"text"]:nil;
        if(!piece && [part[@"content"] isKindOfClass:[NSString class]])piece=part[@"content"];
        if(piece.length)[joined appendString:piece];
    }
    return joined.length?joined:nil;
}
static NSString *XFASRExtractText(NSDictionary *root) {
    if(!root)return nil;
    NSString *direct=XFASRReadableText(root[@"text"]);
    if(direct.length)return direct;
    for(NSString *envelope in @[@"", @"output", @"data", @"result"]){
        NSDictionary *container=envelope.length?
            ([root[envelope] isKindOfClass:[NSDictionary class]]?root[envelope]:nil):root;
        if(!container)continue;
        for(NSString *field in @[@"text", @"transcription", @"transcript"]){
            NSString *candidate=XFASRReadableText(container[field]);
            if(candidate.length)return candidate;
        }
        NSArray *choices=[container[@"choices"] isKindOfClass:[NSArray class]]?container[@"choices"]:nil;
        if(choices.count && [choices[0] isKindOfClass:[NSDictionary class]]){
            NSDictionary *choice=choices[0];
            NSDictionary *message=[choice[@"message"] isKindOfClass:[NSDictionary class]]?choice[@"message"]:nil;
            NSString *candidate=XFASRReadableText(message[@"content"]);
            if(candidate.length)return candidate;
            candidate=XFASRReadableText(choice[@"text"]);
            if(candidate.length)return candidate;
        }
        NSArray *segments=[container[@"segments"] isKindOfClass:[NSArray class]]?container[@"segments"]:nil;
        if(segments.count){
            NSMutableString *joined=[NSMutableString string];
            for(id seg in segments){
                if([seg isKindOfClass:[NSDictionary class]]){
                    NSString *v=XFASRReadableText(seg[@"text"]);
                    if(v.length)[joined appendString:v];
                }
            }
            if(joined.length)return joined;
        }
    }
    return nil;
}
static NSString *XFASRShapeSummary(NSDictionary *root, NSString *mime) {
    if(!root)return [NSString stringWithFormat:@"响应不是 JSON；类型：%@",mime?:@"未知"];
    NSArray *keys=[[root allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSString *shown=[[keys subarrayWithRange:NSMakeRange(0,MIN((NSUInteger)8,keys.count))] componentsJoinedByString:@","];
    NSDictionary *output=[root[@"output"] isKindOfClass:[NSDictionary class]]?root[@"output"]:nil;
    if(output){
        NSArray *nested=[[output allKeys] sortedArrayUsingSelector:@selector(compare:)];
        shown=[shown stringByAppendingFormat:@"；output字段：%@",[nested componentsJoinedByString:@","]];
    }
    return [NSString stringWithFormat:@"响应字段：%@；类型：%@",shown.length?shown:@"(空)",mime?:@"未知"];
}

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

- (UIColor *)accent {return XFAccent();}
- (UIColor *)ink {return XFInk();}
- (void)styleNavigationButton:(UIButton *)button filled:(BOOL)filled {
    button.backgroundColor=filled?XFAccent():XFAccentPale();
    [button setTitleColor:filled?XFPaper():XFAccent() forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    button.layer.cornerRadius=12;
    button.layer.borderWidth=0;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=XFCanvas();
    [UIApplication sharedApplication].statusBarStyle=UIStatusBarStyleDefault;
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
    self.headerBar=[[UIView alloc] initWithFrame:CGRectMake(0,20,w,66)];
    self.headerBar.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.headerBar.backgroundColor=[UIColor whiteColor];
    [self.view addSubview:self.headerBar];
    UIView *rule=[[UIView alloc] initWithFrame:CGRectMake(0,65,w,0.5)];
    rule.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    rule.backgroundColor=XFLine();
    [self.headerBar addSubview:rule];

    XFLineButton *historyIcon=[[XFLineButton alloc] initWithSymbol:@"history"];
    self.sessionsButton=historyIcon;
    self.sessionsButton.frame=CGRectMake(12,5,44,38);
    historyIcon.symbolColor=XFAccent();
    self.sessionsButton.backgroundColor=[UIColor clearColor];
    self.sessionsButton.layer.cornerRadius=12;
    self.sessionsButton.accessibilityLabel=@"历史对话";
    [self.sessionsButton addTarget:self action:@selector(historyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerBar addSubview:self.sessionsButton];

    self.brandTitle=[[UILabel alloc] initWithFrame:CGRectMake(65,5,w-130,34)];
    self.brandTitle.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.brandTitle.text=@"小斐";
    self.brandTitle.font=[UIFont boldSystemFontOfSize:19];
    self.brandTitle.textColor=[self ink];
    self.brandTitle.textAlignment=NSTextAlignmentCenter;
    [self.headerBar addSubview:self.brandTitle];
    self.brandTitle.userInteractionEnabled=NO;

    XFLineButton *modelIcon=[[XFLineButton alloc] initWithSymbol:@"models"];
    self.modelsButton=modelIcon;
    self.modelsButton.frame=CGRectMake(w-56,5,44,38);
    self.modelsButton.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
    modelIcon.symbolColor=XFAccent();
    self.modelsButton.backgroundColor=[UIColor clearColor];
    self.modelsButton.layer.cornerRadius=12;
    self.modelsButton.accessibilityLabel=@"模型库与 API 管理";
    [self.modelsButton addTarget:self action:@selector(modelsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerBar addSubview:self.modelsButton];

    UIView *online=[[UIView alloc] initWithFrame:CGRectMake(12,46,7,7)];
    online.backgroundColor=XFAccent();
    online.layer.cornerRadius=3.5;
    [self.headerBar addSubview:online];
    self.status=[[UILabel alloc] initWithFrame:CGRectMake(25,39,w-37,21)];
    self.status.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.status.textColor=XFSecondary();
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
    self.chat.onQuickPrompt=^(NSString *prompt) {
        if(weakSelf.isWorking || weakSelf.isRecording)return;
        weakSelf.message.text=prompt;
        [weakSelf textViewDidChange:weakSelf.message];
        [weakSelf.message becomeFirstResponder];
    };
    self.recordingBadge=[[UILabel alloc] initWithFrame:CGRectMake(6,94,w-12,30)];
    self.recordingBadge.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.recordingBadge.font=[UIFont boldSystemFontOfSize:13];
    self.recordingBadge.textAlignment=NSTextAlignmentCenter;
    self.recordingBadge.layer.cornerRadius=7;
    self.recordingBadge.layer.masksToBounds=YES;
    self.recordingBadge.backgroundColor=XFDanger();
    self.recordingBadge.textColor=[UIColor whiteColor];
    self.recordingBadge.hidden=YES;
    [self.view addSubview:self.recordingBadge];

    self.footerBar=[[UIView alloc] initWithFrame:CGRectZero];
    self.footerBar.backgroundColor=[UIColor whiteColor];
    [self.view addSubview:self.footerBar];
    UIView *topRule=[[UIView alloc] initWithFrame:CGRectMake(0,0,w,0.5)];
    topRule.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    topRule.backgroundColor=XFLine();
    [self.footerBar addSubview:topRule];

    // All secondary tools now live in the composer + menu.

    self.message=[[UITextView alloc] initWithFrame:CGRectZero];
    self.message.scrollEnabled=YES;
    self.message.backgroundColor=XFPaper();
    self.message.textColor=[self ink];
    self.message.font=[UIFont systemFontOfSize:15];
    self.message.layer.cornerRadius=15;
    self.message.layer.borderWidth=0.7;
    self.message.layer.borderColor=XFLine().CGColor;
    self.message.textContainerInset=UIEdgeInsetsMake(8,7,7,7);
    self.message.returnKeyType=UIReturnKeyDefault;
    self.message.delegate=self;
    [self.footerBar addSubview:self.message];
    self.messagePlaceholder=[[UILabel alloc] initWithFrame:CGRectZero];
    self.messagePlaceholder.text=@"发消息给小斐…";
    self.messagePlaceholder.textColor=XFSecondary();
    self.messagePlaceholder.font=[UIFont systemFontOfSize:14.5];
    self.messagePlaceholder.userInteractionEnabled=NO;
    [self.footerBar addSubview:self.messagePlaceholder];

    XFLineButton *sendIcon=[[XFLineButton alloc] initWithSymbol:@"send"];
    self.sendButton=sendIcon;
    sendIcon.symbolColor=XFAccent();
    self.sendButton.backgroundColor=[UIColor clearColor];
    self.sendButton.accessibilityLabel=@"发送消息或停止当前生成";
    [self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.footerBar addSubview:self.sendButton];
    XFLineButton *addIcon=[[XFLineButton alloc] initWithSymbol:@"plus"];
    self.composerAttachButton=addIcon;
    addIcon.symbolColor=XFAccent();
    self.composerAttachButton.backgroundColor=[UIColor clearColor];
    self.composerAttachButton.layer.cornerRadius=13;
    [self.composerAttachButton addTarget:self action:@selector(composerAttachTapped)
        forControlEvents:UIControlEventTouchUpInside];
    self.composerAttachButton.accessibilityLabel=@"更多功能：图片、录音、语音助手与工具";
    [self.footerBar addSubview:self.composerAttachButton];

    XFLineButton *imageIcon=[[XFLineButton alloc] initWithSymbol:@"image"];
    self.composerGenerateButton=imageIcon;
    imageIcon.symbolColor=XFAccent();
    self.composerGenerateButton.backgroundColor=[UIColor clearColor];
    self.composerGenerateButton.layer.cornerRadius=13;
    [self.composerGenerateButton addTarget:self action:@selector(generateImage)
        forControlEvents:UIControlEventTouchUpInside];
    self.composerGenerateButton.accessibilityLabel=@"按当前生图模型生成图片";
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
    self.attachmentPreview.backgroundColor=XFCanvas();
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
    self.attachmentCaption.textColor=XFSecondary();
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
    // If the user deleted the currently open conversation in History,
    // select another valid session instead of writing to a missing ID.
    if(self.conversationID.length && ![XFChatStore conversationForID:self.conversationID]){
        NSArray *all=[XFChatStore conversations];
        NSString *cid=all.count?all[0][@"id"]:[XFChatStore createConversation];
        [self loadConversation:cid];
    }
    [self refreshStatus];
}
- (void)refreshStatus {
    NSDictionary *profile=[XFModelsController activeProfileForCapability:@"chat"];
    NSString *name=profile[@"name"];
    self.status.text=name.length?[NSString stringWithFormat:@"%@%@",name,self.isWorking?@" · 思考中":@" · 就绪"]:@"尚未选择模型 · 右上角设置";
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
    CGFloat offsetY=[self.view convertPoint:CGPointZero toView:nil].y;
    CGFloat statusInset=[UIApplication sharedApplication].statusBarHidden?0:MAX(0,MIN(20,20-offsetY));
    self.headerBar.frame=CGRectMake(0,statusInset,w,66);
    BOOL typing=self.keyboardOffset>1;
    // Leave a small gap above the Chinese predictive-word bar.
    CGFloat availableBottom=MAX(0,h-self.keyboardOffset-(typing?5:0));
    self.headerBar.hidden=typing;
    // Image actions remain visible with the keyboard; text paste lives in the + menu.
    self.pasteButton.hidden=YES;
    CGFloat top=typing?statusInset:statusInset+66;
    BOOL hasImage=self.pendingImage!=nil;
    CGFloat footerHeight=typing?MIN(hasImage?102:58,availableBottom):(hasImage?115:62);
    CGFloat footerY=MAX(0,availableBottom-footerHeight);
    self.chat.frame=CGRectMake(0,top,w,MAX(0,footerY-top));
    self.footerBar.frame=CGRectMake(0,footerY,w,footerHeight);
    self.recordingBadge.frame=CGRectMake(12,typing?statusInset+4:statusInset+72,w-24,28);
    if(typing){
        CGFloat margin=8,gap=6,attachW=38,generateW=38,sendW=53;
        CGFloat inputW=MAX(80,w-2*margin-3*gap-attachW-generateW-sendW);
        CGFloat y=MAX(2,footerHeight-48);
        self.composerAttachButton.frame=CGRectMake(margin,y,attachW,44);
        self.message.frame=CGRectMake(margin+attachW+gap,y,inputW,44);
        self.messagePlaceholder.frame=CGRectMake(margin+attachW+gap+11,y+6,inputW-15,27);
        self.composerGenerateButton.frame=CGRectMake(margin+attachW+gap+inputW+gap,y,generateW,44);
        self.sendButton.frame=CGRectMake(w-margin-sendW,y,sendW,44);
    } else {
        CGFloat inputY=hasImage?65:5;
        CGFloat margin=8,gap=6,attachW=38,generateW=38,sendW=57;
        CGFloat inputW=MAX(82,w-2*margin-3*gap-attachW-generateW-sendW);
        self.composerAttachButton.frame=CGRectMake(margin,inputY+3,attachW,45);
        self.message.frame=CGRectMake(margin+attachW+gap,inputY,inputW,53);
        self.messagePlaceholder.frame=CGRectMake(margin+attachW+gap+11,inputY+8,inputW-17,26);
        self.composerGenerateButton.frame=CGRectMake(margin+attachW+gap+inputW+gap,inputY+3,generateW,44);
        self.sendButton.frame=CGRectMake(w-margin-sendW,inputY+3,sendW,44);
    }
    self.attachmentPreview.frame=CGRectMake(10,4,35,35);
    self.removeAttachmentButton.frame=CGRectMake(50,7,44,29);
    self.attachmentCaption.frame=CGRectMake(100,3,MAX(30,w-112),38);
    if(typing && hasImage){
        self.attachmentPreview.frame=CGRectMake(10,4,32,32);
        self.removeAttachmentButton.frame=CGRectMake(47,5,43,27);
        self.attachmentCaption.frame=CGRectMake(96,2,MAX(30,w-106),33);
    }
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
    if(self.isRecording){[self finishRecording];return;}
    [self.message resignFirstResponder];
    XFActionHubController *hub=[[XFActionHubController alloc] initWithStyle:UITableViewStyleGrouped];
    __weak XFViewController *weakSelf=self;
    hub.onAction=^(NSString *key){[weakSelf executeTool:key];};
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:hub];
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)showMoreTools {
    [self composerAttachTapped];
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
    if(self.isWorking || self.isRecording){
        [self showAlert:@"当前任务进行中" detail:@"请先完成或停止当前请求，再切换会话。"];
        return;
    }
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
    XFLineButton *sendIcon=(XFLineButton *)self.sendButton;
    sendIcon.symbol=value?@"stop":@"send";
    sendIcon.symbolColor=value?XFDanger():XFAccent();
    self.sendButton.accessibilityLabel=value?@"停止当前生成":@"发送消息";
    self.composerGenerateButton.enabled=!value;
    self.composerGenerateButton.alpha=value?.45:1.0;
}
- (void)executeTool:(NSString *)name {
    [self.message resignFirstResponder];
    if([name isEqualToString:@"new"]) {
        if(self.isWorking){[self showAlert:@"当前还在回复" detail:@"结束本次生成后再创建新对话。"];return;}
        [self loadConversation:[XFChatStore createConversation]];return;
    }
    if([name isEqualToString:@"copyreply"]) {
        if(self.lastAnswer.length) {[UIPasteboard generalPasteboard].string=self.lastAnswer;self.status.text=@"已复制上一次 AI 回复";}
        else [self showAlert:@"暂无可复制的回复" detail:@"收到 AI 回复后即可复制。"];
        return;
    }
    if([name isEqualToString:@"jarvis"]) {[self openJarvis];return;}
    if([name isEqualToString:@"photo"]) {[self pickImage];return;}
    if([name isEqualToString:@"paste"]) {[self pasteTapped];return;}
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
        NSURL *url=[NSURL URLWithString:chat[@"chat_endpoint"]];
        BOOL openRouter=[[url.host lowercaseString] hasSuffix:@"openrouter.ai"];
        if(openRouter && [XFModelsController secretForProfile:chat].length){
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"启用语音识别"
                message:@"检测到 OpenRouter 聊天账户。可以使用同一个 API Key 选择 Whisper 1 转写语音，调用会消耗 API 额度。"
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"启用 Whisper" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
                if([XFModelsController activateOpenRouterWhisperForAccountID:chat[@"account_id"]])
                    [self voiceUpdate:@"idle" message:@"Whisper 语音识别已启用。请再次点击开始说话。"];
                else [self voiceError:@"启用失败，请检查 OpenRouter 账户与密钥"];
            }]];
            [self.jarvisNavigation presentViewController:alert animated:YES completion:nil];
        }else [self voiceError:@"请在模型库选择真正支持语音转写的 STT 模型。OpenRouter 可在 API 服务菜单一键启用 Whisper。"];
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
    // The same visible + control becomes an explicit stop button when recording.
    UIButton *button=self.composerAttachButton;
    if([button isKindOfClass:[XFLineButton class]]){
        XFLineButton *icon=(XFLineButton *)button;
        icon.symbol=recording?@"stop":@"plus";
        icon.symbolColor=recording?XFPaper():XFInk();
    }
    button.backgroundColor=recording?XFDanger():XFCanvas();
    button.accessibilityLabel=recording?@"停止录音":@"更多功能";
    if(recording)[self.recordingBadge setText:@"正在录音 · 按左下角停止"];
}
- (void)updateRecordingClock:(NSTimer *)timer {
    if(!self.isRecording)return;
    if(![self.recorder isRecording]) {
        [self finishRecording];
        return;
    }
    NSTimeInterval elapsed=[[NSDate date] timeIntervalSinceDate:self.recordStarted];
    NSInteger seconds=MAX(0,(NSInteger)elapsed);
    self.recordingBadge.text=[NSString stringWithFormat:@"录音 %02ld:%02ld · 左下角停止",
         (long)(seconds/60),(long)(seconds%60)];
    self.status.text=@"正在录音，点击左下角红色按钮停止";
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
            // Qwen3-ASR-Flash accepts WAV input. Keep AAC for the multipart
            // providers that already work in the existing client.
            BOOL isQwen=(XFUsesQwen3ASR(p) && !XFUsesOpenRouterSTT(p)) ||
                XFUsesDashScopeAudioASR(p);
            NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:
                isQwen?@"xf-recording.wav":@"xf-recording.m4a"];
            NSDictionary *settings=isQwen?
                @{AVFormatIDKey:@(kAudioFormatLinearPCM),
                  AVSampleRateKey:@16000,AVNumberOfChannelsKey:@1,
                  AVLinearPCMBitDepthKey:@16,
                  AVLinearPCMIsFloatKey:@NO,
                  AVLinearPCMIsBigEndianKey:@NO}:
                @{AVFormatIDKey:@(kAudioFormatMPEG4AAC),
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
    NSString *modelName=p[@"model"]?:@"未知";
    if([[modelName lowercaseString] containsString:@"filetrans"]){
        NSString *reason=@"该 Filetrans 模型只支持异步转写任务。请改选无 filetrans 后缀的实时短录音 ASR 模型。";
        [XFDiagnostics record:@"STT 模型协议" code:0 detail:reason];
        self.status.text=reason;
        if(wasVoice)[self voiceError:reason];
        return;
    }
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
    BOOL openRouter=XFUsesOpenRouterSTT(p);
    BOOL qwen=XFUsesQwen3ASR(p) && !openRouter;
    BOOL dashAudio=XFUsesDashScopeAudioASR(p) && !openRouter;
    if(qwen){
        // Chat Completions is the documented interface for Qwen3-ASR-Flash.
        // Don't send a multipart POST to /audio/transcriptions (HTTP 404).
        NSURL *chatURL=XFQwenASRURL(p);
        if(![[chatURL.scheme lowercaseString] isEqualToString:@"https"] || !chatURL.host.length){
            if(wasVoice)[self voiceError:@"千问语音接口配置错误，请检查 API 服务的 Base URL"];
            else self.status.text=@"千问语音接口无效，请检查 API Base URL";
            return;
        }
        if(![[[self.recorder.url pathExtension] lowercaseString] isEqualToString:@"wav"]){
            if(wasVoice)[self voiceError:@"千问需要 WAV 录音，请重新开始录音"];
            else self.status.text=@"千问录音格式错误，请重新录音";
            return;
        }
        [req setURL:chatURL];
        req.timeoutInterval=90;
        NSString *uri=[@"data:audio/wav;base64," stringByAppendingString:
            [audio base64EncodedStringWithOptions:0]];
        NSDictionary *payload=@{@"model":p[@"model"],
            @"messages":@[@{@"role":@"user",@"content":@[
                @{@"type":@"input_audio",@"input_audio":@{@"data":uri}}
            ]}],@"stream":@NO,@"asr_options":@{@"enable_itn":@NO}};
        req.HTTPBody=[NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    } else if(dashAudio){
        // New Qwen-Audio ASR and Fun-ASR flash use DashScope multimodal-generation.
        // They require input.messages and parameters.format, not a multipart upload.
        NSURL *chat=[NSURL URLWithString:p[@"chat_endpoint"]];
        NSString *override=p[@"stt_override"];
        NSString *target=(override.length?override:
            [NSString stringWithFormat:@"https://%@/api/v1/services/aigc/multimodal-generation/generation",chat.host?:@""]);
        NSURL *url=[NSURL URLWithString:target];
        if(![[url.scheme lowercaseString] isEqualToString:@"https"] || !url.host.length){
            if(wasVoice)[self voiceError:@"阿里云音频模型接口配置不正确"];
            else self.status.text=@"阿里云音频模型接口无效";
            return;
        }
        [req setURL:url];
        NSString *format=[[[self.recorder.url pathExtension] lowercaseString] isEqualToString:@"wav"]?@"wav":@"m4a";
        NSString *mime=[format isEqualToString:@"wav"]?@"audio/wav":@"audio/mp4";
        NSString *uri=[NSString stringWithFormat:@"data:%@;base64,%@",mime,[audio base64EncodedStringWithOptions:0]];
        NSDictionary *payload=@{@"model":modelName,
            @"input":@{@"messages":@[@{@"role":@"user",@"content":@[
                @{@"type":@"input_audio",@"input_audio":@{@"data":uri}}
            ]}]},
            @"parameters":@{@"format":format,@"sample_rate":@"16000"}};
        req.HTTPBody=[NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [req setValue:@"disable" forHTTPHeaderField:@"X-DashScope-SSE"];
    } else if(openRouter){
        // OpenRouter's official transcription endpoint requires raw Base64 + format.
        // Do not send a data URI and do not use a chat-completion audio envelope.
        NSString *encoded=[audio base64EncodedStringWithOptions:0];
        NSString *format=[[[self.recorder.url pathExtension] lowercaseString] isEqualToString:@"wav"]?@"wav":@"m4a";
        NSDictionary *payload=@{@"model":modelName,
            @"input_audio":@{@"data":encoded,@"format":format},
            @"response_format":@"json"};
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        req.HTTPBody=[NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    } else {
        NSString *boundary=[[NSUUID UUID] UUIDString];
        [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary] forHTTPHeaderField:@"Content-Type"];
        NSMutableData *body=[NSMutableData data];
        [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n%@\r\n",boundary,p[@"model"]] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:audio];
        [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        req.HTTPBody=body;
    }
    NSString *safeEndpoint=XFASRSafeEndpoint(req.URL);
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
        id parsed=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSDictionary *json=[parsed isKindOfClass:[NSDictionary class]]?parsed:nil;
        NSString *text=XFASRExtractText(json);
        NSString *mime=[resp.MIMEType isKindOfClass:[NSString class]]?resp.MIMEType:nil;
        // Some OpenAI-compatible endpoints return a plain-text transcript.
        if(!text.length && code>=200 && code<300 &&
           [mime.lowercaseString hasPrefix:@"text/plain"] && data.length<24000){
            NSString *plain=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if(plain.length && ![plain.lowercaseString containsString:@"<html"])
                text=[plain stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if(code<200 || code>=300 || !text.length){
            NSDictionary *error=[json[@"error"] isKindOfClass:[NSDictionary class]]?json[@"error"]:nil;
            NSString *reason=[error[@"message"] isKindOfClass:[NSString class]]?error[@"message"]:nil;
            if(!reason.length && [json[@"message"] isKindOfClass:[NSString class]])reason=json[@"message"];
            if(!reason.length && [json[@"code"] isKindOfClass:[NSString class]])reason=json[@"code"];
            NSString *shape=XFASRShapeSummary(json,mime);
            BOOL wrongPath=(code==404);
            if(wrongPath) {
                if(qwen && XFIsAlibabaASRHost(req.URL.host)){
                    reason=@"阿里云接口返回404，请检查密钥地域和模型服务权限";
                }else if(qwen){
                    reason=@"当前服务商可能未提供千问 ASR 聊天接口，请检查 API Base URL";
                }else{
                    NSString *overridden=p[@"stt_override"];
                    if([overridden isKindOfClass:[NSString class]] && overridden.length)
                        reason=@"自定义 STT 地址返回404。请核对该服务的完整转写接口 URL 和所选模型";
                    else
                        reason=@"该服务返回404。请到模型库 > 服务 > 编辑 API > 高级设置，填写官方 STT 转写接口；也可换用支持语音转写的服务商";
                }
            }
            if(!reason.length && code>=200 && code<300)
                reason=[NSString stringWithFormat:@"无法提取识别文字。%@",shape];
            if(!reason.length)reason=[NSString stringWithFormat:@"STT 请求失败。%@",shape];
            if(reason.length>170)reason=[reason substringToIndex:170];
            NSString *detail=[NSString stringWithFormat:@"服务：%@；模型：%@；HTTP %ld；路径：%@；协议：%@",
                p[@"provider"]?:@"API",modelName,(long)code,safeEndpoint,qwen?@"千问 JSON":(dashAudio?@"DashScope Audio JSON":(openRouter?@"OpenRouter JSON":@"multipart STT"))];
            [XFDiagnostics record:@"STT 请求检查" code:code detail:detail];
            NSString *notice=[NSString stringWithFormat:@"STT HTTP %ld：%@",(long)code,reason];
            self.status.text=notice;
            NSString *instructions=wrongPath?@"请核对模型是否提供录音转写能力、API 服务 Base URL、转写接口完整路径和地域。":shape;
            NSString *explain=[NSString stringWithFormat:@"%@\n请求：%@\n模型：%@\n%@",
                notice,safeEndpoint,modelName,instructions];
            if(wasVoice && openRouter && (code==404 || code==400 || code==422) &&
                ![modelName isEqualToString:@"openai/whisper-1"]){
                [self voiceError:@"当前 OpenRouter STT 模型无法转写，建议切换到 Whisper 1。"];
                UIAlertController *fix=[UIAlertController alertControllerWithTitle:@"修复语音识别"
                   message:[NSString stringWithFormat:@"当前模型：%@\nHTTP %ld\n尝试改用 OpenRouter 官方支持的 Whisper 1。使用时会消耗 API 额度。",modelName,(long)code]
                   preferredStyle:UIAlertControllerStyleAlert];
                [fix addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                [fix addAction:[UIAlertAction actionWithTitle:@"切换 Whisper 1" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
                    if([XFModelsController activateOpenRouterWhisperForAccountID:p[@"account_id"]])
                        [self voiceUpdate:@"idle" message:@"已切换 Whisper 1。请重新点击开始说话。"];
                    else [self voiceError:@"切换失败，请检查 API Key"];
                }]];
                [self.jarvisNavigation presentViewController:fix animated:YES completion:nil];
            } else if(wasVoice)
                [self voiceError:[NSString stringWithFormat:@"%@；请求：%@",notice,safeEndpoint]];
            else [self showAlert:@"语音识别失败" detail:explain];
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
    UIBarButtonItem *save=[[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStylePlain
        target:self action:@selector(saveGeneratedImage)];
    UIBarButtonItem *share=[[UIBarButtonItem alloc] initWithTitle:@"分享" style:UIBarButtonItemStylePlain
        target:self action:@selector(shareGeneratedImage)];
    viewer.navigationItem.rightBarButtonItems=@[save,share];
    objc_setAssociatedObject(viewer,@"XFGeneratedImage",image,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)closeImageViewer {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)saveGeneratedImage {
    UINavigationController *nav=(UINavigationController *)self.presentedViewController;
    UIViewController *vc=nav.topViewController;
    UIImage *image=objc_getAssociatedObject(vc,@"XFGeneratedImage");
    if(image){UIImageWriteToSavedPhotosAlbum(image,nil,NULL,NULL);vc.title=@"已请求保存到相册";}
}
- (void)shareGeneratedImage {
    UINavigationController *nav=(UINavigationController *)self.presentedViewController;
    UIViewController *vc=nav.topViewController;
    UIImage *image=objc_getAssociatedObject(vc,@"XFGeneratedImage");
    if(!image)return;
    UIActivityViewController *activity=[[UIActivityViewController alloc] initWithActivityItems:@[image] applicationActivities:nil];
    [vc presentViewController:activity animated:YES completion:nil];
}
@end
