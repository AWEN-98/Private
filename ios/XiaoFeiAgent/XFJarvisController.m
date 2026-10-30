#import "XFJarvisController.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

// Lightweight native CRT.  The iPhone 4S renders at 320x480 points;
// no UIWebView, WebGL, video loop, or external assets are required.
@interface XFKarenScope : UIView
@property(nonatomic,copy) NSString *mode;
@property(nonatomic,assign) CGFloat microphoneLevel;
@property(nonatomic,assign) CGFloat speechEnergy;
@property(nonatomic,assign) CGFloat phase;
@property(nonatomic,assign) NSInteger expression;
- (void)advance;
@end

@implementation XFKarenScope
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.opaque=YES;
        self.backgroundColor=[UIColor blackColor];
        self.contentMode=UIViewContentModeRedraw;
        self.mode=@"idle";
    }
    return self;
}
- (void)advance {
    self.phase+=0.145;
    if(self.phase>10000)self.phase=0;
    self.speechEnergy*=0.88;
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx=UIGraphicsGetCurrentContext();
    if(!ctx)return;
    CGFloat w=self.bounds.size.width, h=self.bounds.size.height;
    CGContextSetFillColorWithColor(ctx,[UIColor colorWithRed:0.009 green:0.025 blue:0.015 alpha:1].CGColor);
    CGContextFillRect(ctx,self.bounds);
    // Faint phosphor grid and scan lines drawn in one pass.
    CGContextSetLineWidth(ctx,0.5);
    CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:0.12 green:0.35 blue:0.19 alpha:0.17].CGColor);
    for(CGFloat y=4;y<h;y+=6) {CGContextMoveToPoint(ctx,0,y);CGContextAddLineToPoint(ctx,w,y);}
    for(CGFloat x=15;x<w;x+=28) {CGContextMoveToPoint(ctx,x,0);CGContextAddLineToPoint(ctx,x,h);}
    CGContextStrokePath(ctx);
    CGContextSetFillColorWithColor(ctx,[UIColor colorWithRed:0 green:0 blue:0 alpha:0.20].CGColor);
    for(CGFloat y=1;y<h;y+=4) CGContextFillRect(ctx,CGRectMake(0,y,w,1));
    CGFloat center=h*0.54;
    NSString *m=self.mode?:@"idle";
    BOOL listen=[m isEqualToString:@"listening"];
    BOOL think=[m isEqualToString:@"thinking"] || [m isEqualToString:@"transcribing"];
    BOOL speak=[m isEqualToString:@"speaking"];
    if(self.expression==3 && !listen && !think && !speak) {
        CGContextSetFillColorWithColor(ctx,[UIColor colorWithRed:0.95 green:0.22 blue:0.17 alpha:1].CGColor);
        CGFloat x=w/2;
        CGContextFillRect(ctx,CGRectMake(x-3,center-29,6,37));
        CGContextFillEllipseInRect(ctx,CGRectMake(x-3,center+15,6,6));
        return;
    }
    if(self.expression==2 && !listen && !think && !speak) {
        // Minimal eye-roll expression in idle mode.
        CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:.18 green:.96 blue:.43 alpha:.88].CGColor);
        CGContextSetLineWidth(ctx,2);
        for(NSInteger i=0;i<2;i++){
            CGFloat x=w*(i?0.65:0.35);
            CGContextStrokeEllipseInRect(ctx,CGRectMake(x-20,center-12,40,25));
            CGContextFillEllipseInRect(ctx,CGRectMake(x-3,center-11,7,7));
        }
        return;
    }
    // Draw twice for inexpensive phosphor glow (no animated drop shadows).
    for(NSInteger pass=0;pass<2;pass++){
        CGContextBeginPath(ctx);
        CGFloat width=pass==0?5.0:1.8;
        CGContextSetLineWidth(ctx,width);
        CGFloat alpha=pass==0?.18:1.0;
        CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:.20 green:1 blue:.46 alpha:alpha].CGColor);
        CGFloat margin=8;
        for(CGFloat x=margin;x<=w-margin;x+=2){
            CGFloat edge=sin((x-margin)/(w-2*margin)*M_PI);
            CGFloat y=center;
            if(listen){
                CGFloat power=MAX(.05,MIN(1,self.microphoneLevel));
                y+=sinf(x*.11+self.phase*2.6)*(3+power*36)*edge;
                y+=sinf(x*.31-self.phase*3)*power*7*edge;
            }else if(think){
                y+=(sinf(x*.22+self.phase*4)*13+sinf(x*.37-self.phase*2.7)*7)*edge;
            }else if(speak){
                CGFloat power=.32+MIN(1,self.speechEnergy)*.68;
                y+=(sinf(x*.12+self.phase*2.4)*25+sinf(x*.23-self.phase*1.5)*7)*power*edge;
            }else if(self.expression==1){
                y+=0; // Karen's deadpan flat line.
            }else{
                y+=sinf(x*.045+self.phase)*2.2+sinf(x*.020-self.phase*.35)*1.5;
            }
            if(x==margin)CGContextMoveToPoint(ctx,x,y);
            else CGContextAddLineToPoint(ctx,x,y);
        }
        CGContextStrokePath(ctx);
    }
    // Static bezel strokes; kept translucent and inside the content bounds.
    CGContextSetLineWidth(ctx,1);
    CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:.12 green:.55 blue:.29 alpha:.44].CGColor);
    CGContextStrokeRect(ctx,CGRectInset(self.bounds,3,3));
}
@end

@interface XFJarvisController ()
@property(nonatomic,strong) XFKarenScope *scope;
@property(nonatomic,strong) UILabel *hintLabel;
@property(nonatomic,strong) UILabel *stateLabel;
@property(nonatomic,strong) UILabel *subtitle;
@property(nonatomic,strong) UILabel *timeLabel;
@property(nonatomic,strong) UIButton *primary;
@property(nonatomic,strong) UIButton *stopButton;
@property(nonatomic,strong) UIButton *teaseButton;
@property(nonatomic,strong) UIButton *autoButton;
@property(nonatomic,strong) UIButton *continuousButton;
@property(nonatomic,strong) UIButton *voiceStyleButton;
@property(nonatomic,strong) NSTimer *waveTimer;
@property(nonatomic,copy) NSString *mode;
@end

@implementation XFJarvisController
- (UIColor *)accent {return [UIColor colorWithRed:.23 green:.95 blue:.47 alpha:1];}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor colorWithRed:.015 green:.026 blue:.020 alpha:1];
    self.title=@"小斐 · KAREN";
    self.navigationController.navigationBar.translucent=NO;
    self.navigationController.navigationBar.barTintColor=[UIColor colorWithRed:.035 green:.09 blue:.055 alpha:1];
    self.navigationController.navigationBar.tintColor=[self accent];
    self.navigationController.navigationBar.titleTextAttributes=@{NSForegroundColorAttributeName:[self accent]};
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(closePressed)];
    self.hintLabel=[[UILabel alloc] init];
    self.hintLabel.text=@"XIAOFEI  /  RETRO TERMINAL";
    self.hintLabel.font=[UIFont fontWithName:@"Courier-Bold" size:11]?:[UIFont boldSystemFontOfSize:11];
    self.hintLabel.textColor=[UIColor colorWithRed:.36 green:.77 blue:.48 alpha:1];
    self.hintLabel.textAlignment=NSTextAlignmentCenter;
    [self.view addSubview:self.hintLabel];
    self.scope=[[XFKarenScope alloc] initWithFrame:CGRectZero];
    self.scope.layer.borderWidth=1;
    self.scope.layer.borderColor=[UIColor colorWithRed:.11 green:.38 blue:.20 alpha:1].CGColor;
    [self.view addSubview:self.scope];
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(scopeTapped)];
    [self.scope addGestureRecognizer:tap];
    self.stateLabel=[[UILabel alloc] init];
    self.stateLabel.textAlignment=NSTextAlignmentCenter;
    self.stateLabel.font=[UIFont boldSystemFontOfSize:21];
    self.stateLabel.textColor=[self accent];
    [self.view addSubview:self.stateLabel];
    self.subtitle=[[UILabel alloc] init];
    self.subtitle.numberOfLines=3;
    self.subtitle.font=[UIFont systemFontOfSize:13];
    self.subtitle.textAlignment=NSTextAlignmentCenter;
    self.subtitle.textColor=[UIColor colorWithRed:.60 green:.78 blue:.64 alpha:1];
    [self.view addSubview:self.subtitle];
    self.timeLabel=[[UILabel alloc] init];
    self.timeLabel.font=[UIFont fontWithName:@"Courier" size:13]?:[UIFont systemFontOfSize:13];
    self.timeLabel.textAlignment=NSTextAlignmentCenter;
    self.timeLabel.textColor=[self accent];
    [self.view addSubview:self.timeLabel];
    self.primary=[UIButton buttonWithType:UIButtonTypeCustom];
    self.primary.backgroundColor=[UIColor colorWithRed:.11 green:.43 blue:.23 alpha:1];
    self.primary.layer.cornerRadius=7;
    self.primary.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    [self.primary setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.primary addTarget:self action:@selector(primaryPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.primary];
    self.stopButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.stopButton.layer.cornerRadius=7;
    self.stopButton.backgroundColor=[UIColor colorWithRed:.16 green:.22 blue:.17 alpha:1];
    self.stopButton.titleLabel.font=[UIFont systemFontOfSize:13];
    [self.stopButton setTitle:@"停止" forState:UIControlStateNormal];
    [self.stopButton setTitleColor:[self accent] forState:UIControlStateNormal];
    [self.stopButton addTarget:self action:@selector(stopPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stopButton];
    self.teaseButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.teaseButton.titleLabel.font=[UIFont boldSystemFontOfSize:12];
    [self.teaseButton setTitle:@"逗我一下" forState:UIControlStateNormal];
    [self.teaseButton setTitleColor:[self accent] forState:UIControlStateNormal];
    [self.teaseButton addTarget:self action:@selector(teasePressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.teaseButton];
    self.autoButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.autoButton.titleLabel.font=[UIFont systemFontOfSize:12];
    [self.autoButton setTitleColor:[UIColor colorWithRed:.60 green:.79 blue:.64 alpha:1] forState:UIControlStateNormal];
    [self.autoButton addTarget:self action:@selector(toggleAuto) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.autoButton];
    self.continuousButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.continuousButton.titleLabel.font=[UIFont systemFontOfSize:11];
    [self.continuousButton setTitleColor:[self accent] forState:UIControlStateNormal];
    [self.continuousButton addTarget:self action:@selector(toggleContinuous) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.continuousButton];
    self.voiceStyleButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.voiceStyleButton.titleLabel.font=[UIFont systemFontOfSize:11];
    [self.voiceStyleButton setTitleColor:[self accent] forState:UIControlStateNormal];
    [self.voiceStyleButton addTarget:self action:@selector(toggleVoiceStyle) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.voiceStyleButton];
    [self updateAutoTitle];
    [self updateContinuousTitle];
    [self updateVoiceStyleTitle];
    [self updateMode:@"idle" description:@"我在线。点击说话，或者戳戳屏幕。"];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.waveTimer invalidate];
    self.waveTimer=[NSTimer timerWithTimeInterval:1.0/12.0 target:self.scope selector:@selector(advance) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.waveTimer forMode:NSRunLoopCommonModes];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.waveTimer invalidate];self.waveTimer=nil;
}
- (void)dealloc {[self.waveTimer invalidate];}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w=self.view.bounds.size.width, h=self.view.bounds.size.height;
    CGFloat scopeH=MIN(184,MAX(115,h*.43));
    self.hintLabel.frame=CGRectMake(8,8,w-16,22);
    self.scope.frame=CGRectMake(12,36,w-24,scopeH);
    CGFloat below=36+scopeH;
    self.stateLabel.frame=CGRectMake(10,below+5,w-20,30);
    self.subtitle.frame=CGRectMake(15,below+34,w-30,49);
    self.timeLabel.frame=CGRectMake(15,below+81,w-30,17);
    CGFloat buttonsY=MIN(h-87,below+108);
    self.primary.frame=CGRectMake(12,buttonsY,w-104,42);
    self.stopButton.frame=CGRectMake(w-85,buttonsY,73,42);
    CGFloat g=4, side=9, bw=(w-side*2-g*3)/4;
    CGFloat y=h-43;
    self.teaseButton.frame=CGRectMake(side,y,bw,35);
    self.continuousButton.frame=CGRectMake(side+(bw+g),y,bw,35);
    self.voiceStyleButton.frame=CGRectMake(side+2*(bw+g),y,bw,35);
    self.autoButton.frame=CGRectMake(side+3*(bw+g),y,bw,35);
}
- (void)updateAutoTitle {
    self.autoButton.titleLabel.font=[UIFont systemFontOfSize:11];
    [self.autoButton setTitle:self.autoSpeak?@"朗读开":@"朗读关" forState:UIControlStateNormal];
}
- (void)updateContinuousTitle {
    [self.continuousButton setTitle:self.continuousTalk?@"连聊开":@"连聊关" forState:UIControlStateNormal];
    self.stopButton.enabled=![self.mode isEqualToString:@"idle"]||self.continuousTalk;
    self.stopButton.alpha=self.stopButton.enabled?1:.45;
}
- (void)updateVoiceStyleTitle {
    [self.voiceStyleButton setTitle:self.mechanicalVoice?@"机械声":@"柔和声" forState:UIControlStateNormal];
}
- (void)setAutoSpeak:(BOOL)autoSpeak {
    _autoSpeak=autoSpeak;
    if(self.autoButton)[self updateAutoTitle];
}
- (void)setContinuousTalk:(BOOL)continuousTalk {
    _continuousTalk=continuousTalk;
    if(self.continuousButton)[self updateContinuousTitle];
}
- (void)setMechanicalVoice:(BOOL)mechanicalVoice {
    _mechanicalVoice=mechanicalVoice;
    if(self.voiceStyleButton)[self updateVoiceStyleTitle];
}
- (void)updateMode:(NSString *)mode description:(NSString *)detail {
    self.mode=mode?:@"idle";
    self.scope.mode=self.mode;
    self.scope.expression=0;
    BOOL listening=[self.mode isEqualToString:@"listening"];
    BOOL thinking=[self.mode isEqualToString:@"thinking"] || [self.mode isEqualToString:@"transcribing"];
    BOOL speaking=[self.mode isEqualToString:@"speaking"];
    self.stateLabel.text=listening?@"正在聆听":(thinking?@"正在思考":(speaking?@"正在回答":@"随时待命"));
    self.subtitle.text=detail.length?detail:@"我在。";
    [self.primary setTitle:listening?@"结束并提问":@"开始说话" forState:UIControlStateNormal];
    self.primary.enabled=!thinking;
    self.primary.alpha=self.primary.enabled?1:.45;
    [self updateContinuousTitle];
    self.teaseButton.enabled=![self.mode isEqualToString:@"idle"];
    self.teaseButton.alpha=self.teaseButton.enabled?1:.40;
    self.timeLabel.text=listening?@"00:00":@"";
    if(!listening)self.scope.microphoneLevel=0;
    if(!speaking)self.scope.speechEnergy=0;
    [self.scope setNeedsDisplay];
}
- (void)updateMeter:(float)level seconds:(NSInteger)seconds {
    if(![self.mode isEqualToString:@"listening"])return;
    self.scope.microphoneLevel=MAX(0,MIN(1,level));
    self.timeLabel.text=[NSString stringWithFormat:@"%02ld:%02ld",(long)(seconds/60),(long)(seconds%60)];
}
- (void)updateSpeechPulse {
    if([self.mode isEqualToString:@"speaking"])self.scope.speechEnergy=1.0;
}
- (void)updateSpeechText:(NSString *)spokenText {
    if(![self.mode isEqualToString:@"speaking"] || !spokenText.length)return;
    self.subtitle.text=spokenText;
}
- (void)scopeTapped {
    if(![self.mode isEqualToString:@"idle"])return;
    self.scope.expression=(self.scope.expression+1)%4;
    NSArray *lines=@[@"又戳？我的屏幕有使用寿命。",@"……", @"看上面也改变不了现实。",@"警告：检测到无聊的人类。"];
    self.subtitle.text=lines[(NSUInteger)self.scope.expression];
    [self.scope setNeedsDisplay];
}
- (void)primaryPressed {if(self.onPrimary)self.onPrimary();}
- (void)stopPressed {if(self.onStop)self.onStop();}
- (void)closePressed {if(self.onClose)self.onClose();}
- (void)teasePressed {if(self.onTease)self.onTease();}
- (void)toggleAuto {
    self.autoSpeak=!self.autoSpeak;
    if(!self.autoSpeak && self.continuousTalk){
        self.continuousTalk=NO;
        if(self.onContinuousTalk)self.onContinuousTalk(NO);
    }
    if(self.onAutoSpeak)self.onAutoSpeak(self.autoSpeak);
}
- (void)toggleContinuous {
    self.continuousTalk=!self.continuousTalk;
    if(self.continuousTalk && !self.autoSpeak){
        self.autoSpeak=YES;
        if(self.onAutoSpeak)self.onAutoSpeak(YES);
    }
    if(self.onContinuousTalk)self.onContinuousTalk(self.continuousTalk);
}
- (void)toggleVoiceStyle {
    self.mechanicalVoice=!self.mechanicalVoice;
    if(self.onMechanicalVoice)self.onMechanicalVoice(self.mechanicalVoice);
}
@end
