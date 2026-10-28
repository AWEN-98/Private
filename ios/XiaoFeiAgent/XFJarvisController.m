#import "XFJarvisController.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface XFJarvisController ()
@property(nonatomic,strong) UIView *ringOuter;
@property(nonatomic,strong) UIView *ringInner;
@property(nonatomic,strong) UIButton *primary;
@property(nonatomic,strong) UIButton *stopButton;
@property(nonatomic,strong) UILabel *stateLabel;
@property(nonatomic,strong) UILabel *subtitle;
@property(nonatomic,strong) UILabel *timeLabel;
@property(nonatomic,strong) UILabel *hintLabel;
@property(nonatomic,strong) UIButton *autoButton;
@property(nonatomic,strong) NSMutableArray *meterBars;
@property(nonatomic,copy) NSString *mode;
@property(nonatomic,copy) NSString *modeDetail;
@end

@implementation XFJarvisController
- (UIColor *)accent {return [UIColor colorWithRed:.29 green:.78 blue:.93 alpha:1];}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor colorWithRed:.035 green:.065 blue:.115 alpha:1];
    self.title=@"JARVIS · 小斐";
    self.navigationController.navigationBar.translucent=NO;
    self.navigationController.navigationBar.barTintColor=[UIColor colorWithRed:.06 green:.10 blue:.16 alpha:1];
    self.navigationController.navigationBar.tintColor=[UIColor whiteColor];
    self.navigationController.navigationBar.titleTextAttributes=@{NSForegroundColorAttributeName:[UIColor whiteColor]};
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(closePressed)];
    self.hintLabel=[[UILabel alloc] init];
    self.hintLabel.text=@"XIAOFEI / VOICE ASSISTANT";
    self.hintLabel.textAlignment=NSTextAlignmentCenter;
    self.hintLabel.textColor=[UIColor colorWithRed:.40 green:.64 blue:.75 alpha:1];
    self.hintLabel.font=[UIFont systemFontOfSize:11];
    [self.view addSubview:self.hintLabel];

    self.ringOuter=[[UIView alloc] init];
    self.ringOuter.backgroundColor=[UIColor clearColor];
    self.ringOuter.layer.borderWidth=1.6;
    self.ringOuter.layer.borderColor=[UIColor colorWithRed:.12 green:.39 blue:.55 alpha:1].CGColor;
    self.ringOuter.layer.cornerRadius=79;
    [self.view addSubview:self.ringOuter];
    self.ringInner=[[UIView alloc] init];
    self.ringInner.layer.cornerRadius=63;
    self.ringInner.layer.borderWidth=2.4;
    self.ringInner.layer.borderColor=[self accent].CGColor;
    self.ringInner.backgroundColor=[UIColor colorWithRed:.065 green:.17 blue:.27 alpha:1];
    [self.view addSubview:self.ringInner];

    self.meterBars=[NSMutableArray array];
    for(NSInteger i=0;i<17;i++){
        UIView *bar=[[UIView alloc] init];
        bar.layer.cornerRadius=1;
        bar.backgroundColor=[UIColor colorWithRed:.56 green:.91 blue:1 alpha:1];
        [self.ringInner addSubview:bar];
        [self.meterBars addObject:bar];
    }
    self.stateLabel=[[UILabel alloc] init];
    self.stateLabel.textAlignment=NSTextAlignmentCenter;
    self.stateLabel.textColor=[UIColor whiteColor];
    self.stateLabel.font=[UIFont boldSystemFontOfSize:23];
    [self.view addSubview:self.stateLabel];
    self.subtitle=[[UILabel alloc] init];
    self.subtitle.numberOfLines=3;
    self.subtitle.textAlignment=NSTextAlignmentCenter;
    self.subtitle.textColor=[UIColor colorWithRed:.68 green:.79 blue:.85 alpha:1];
    self.subtitle.font=[UIFont systemFontOfSize:13];
    [self.view addSubview:self.subtitle];

    self.timeLabel=[[UILabel alloc] init];
    self.timeLabel.font=[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    self.timeLabel.textAlignment=NSTextAlignmentCenter;
    self.timeLabel.textColor=[self accent];
    self.timeLabel.text=@"00:00";
    [self.view addSubview:self.timeLabel];

    self.primary=[UIButton buttonWithType:UIButtonTypeCustom];
    self.primary.backgroundColor=[UIColor colorWithRed:.10 green:.48 blue:.67 alpha:1];
    self.primary.layer.cornerRadius=22;
    [self.primary setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.primary.titleLabel.font=[UIFont boldSystemFontOfSize:16];
    [self.primary addTarget:self action:@selector(primaryPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.primary];

    self.stopButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.stopButton.backgroundColor=[UIColor colorWithRed:.12 green:.20 blue:.29 alpha:1];
    self.stopButton.layer.cornerRadius=18;
    [self.stopButton setTitle:@"停止" forState:UIControlStateNormal];
    [self.stopButton setTitleColor:[UIColor colorWithRed:.85 green:.92 blue:.96 alpha:1] forState:UIControlStateNormal];
    [self.stopButton addTarget:self action:@selector(stopPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stopButton];
    self.autoButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.autoButton.titleLabel.font=[UIFont systemFontOfSize:12.5];
    [self.autoButton setTitleColor:[UIColor colorWithRed:.60 green:.86 blue:.95 alpha:1] forState:UIControlStateNormal];
    [self.autoButton addTarget:self action:@selector(toggleAuto) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.autoButton];
    [self updateAutoTitle];
    [self updateMode:@"idle" description:@"点击开始说话；再次点击结束并自动提问"];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w=self.view.bounds.size.width, h=self.view.bounds.size.height;
    self.hintLabel.frame=CGRectMake(8,16,w-16,22);
    CGFloat centerY=MIN(MAX(130,h*.35),h-197);
    self.ringOuter.frame=CGRectMake(floor((w-158)/2),floor(centerY-79),158,158);
    self.ringInner.frame=CGRectMake(floor((w-126)/2),floor(centerY-63),126,126);
    for(NSInteger i=0;i<self.meterBars.count;i++){
        UIView *bar=self.meterBars[(NSUInteger)i];
        CGFloat height=bar.bounds.size.height>1?bar.bounds.size.height:6;
        bar.frame=CGRectMake(23+i*4.8,63-height/2,2.2,height);
    }
    CGFloat stateY=centerY+87;
    self.stateLabel.frame=CGRectMake(12,stateY,w-24,29);
    self.subtitle.frame=CGRectMake(18,stateY+34,w-36,52);
    self.timeLabel.frame=CGRectMake(15,stateY+85,w-30,18);
    CGFloat buttonsY=MAX(stateY+113,h-91);
    if(buttonsY+45>h-36)buttonsY=h-82;
    self.primary.frame=CGRectMake(13,buttonsY,w-100,44);
    self.stopButton.frame=CGRectMake(w-78,buttonsY,65,44);
    self.autoButton.frame=CGRectMake(10,h-38,w-20,30);
}
- (void)updateAutoTitle {
    [self.autoButton setTitle:self.autoSpeak?@"自动朗读：已开启（点击关闭）":@"自动朗读：已关闭（点击开启）"
                  forState:UIControlStateNormal];
}
- (void)setAutoSpeak:(BOOL)autoSpeak {
    _autoSpeak=autoSpeak;
    if(self.autoButton)[self updateAutoTitle];
}
- (void)updateMode:(NSString *)mode description:(NSString *)detail {
    self.mode=mode?:@"idle";
    self.modeDetail=detail?:@"";
    BOOL listening=[mode isEqualToString:@"listening"];
    BOOL thinking=[mode isEqualToString:@"thinking"];
    BOOL speaking=[mode isEqualToString:@"speaking"];
    BOOL transcribing=[mode isEqualToString:@"transcribing"];
    self.stateLabel.text=listening?@"正在聆听":(thinking?@"正在思考":(speaking?@"正在回答":(transcribing?@"正在识别":@"随时待命")));
    self.subtitle.text=detail.length?detail:@"点击开始说话";
    [self.primary setTitle:listening?@"■ 结束并提问":@"● 开始说话" forState:UIControlStateNormal];
    self.primary.enabled=!(thinking||transcribing);
    self.primary.alpha=self.primary.enabled?1:.42;
    self.ringInner.layer.borderColor=(listening?[UIColor colorWithRed:.94 green:.30 blue:.34 alpha:1]:
      (speaking?[UIColor colorWithRed:.37 green:.93 blue:.68 alpha:1]:[self accent])).CGColor;
    self.stopButton.enabled=!( [mode isEqualToString:@"idle"] );
    self.stopButton.alpha=self.stopButton.enabled?1:.45;
    if(!listening)[self updateMeter:0 seconds:0];
}
- (void)updateMeter:(float)level seconds:(NSInteger)seconds {
    if([self.mode isEqualToString:@"listening"]){
        self.timeLabel.text=[NSString stringWithFormat:@"%02ld:%02ld",(long)(seconds/60),(long)(seconds%60)];
    }else self.timeLabel.text=@"";
    CGFloat strength=MAX(0,MIN(1,level));
    for(NSInteger i=0;i<self.meterBars.count;i++){
        UIView *bar=self.meterBars[(NSUInteger)i];
        CGFloat ridge=1-fabs(i-8)/10.0;
        CGFloat height=4+strength*MAX(6,27*ridge)*(0.65+(i%4)*.12);
        CGRect f=bar.frame;f.origin.y=63-height/2;f.size.height=height;bar.frame=f;
    }
}
- (void)primaryPressed {if(self.onPrimary)self.onPrimary();}
- (void)stopPressed {if(self.onStop)self.onStop();}
- (void)closePressed {if(self.onClose)self.onClose();}
- (void)toggleAuto {
    self.autoSpeak=!self.autoSpeak;
    if(self.onAutoSpeak)self.onAutoSpeak(self.autoSpeak);
}
@end
