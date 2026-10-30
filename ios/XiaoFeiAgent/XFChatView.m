#import "XFChatView.h"
#import "XFChatStore.h"
#import "XFTheme.h"
#import <QuartzCore/QuartzCore.h>
@interface XFChatBubble : UIView
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) UILabel *roleLabel;
@property(nonatomic,strong) UIImageView *imagePreview;
@property(nonatomic,copy) NSString *imageName;
@property(nonatomic,assign) BOOL user;
@property(nonatomic,assign) BOOL notice;
@end
@implementation XFChatBubble
@end

@interface XFChatView ()
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) NSMutableArray *bubbles;
@property(nonatomic,strong) UILabel *welcomeTitle;
@property(nonatomic,strong) XFLineButton *welcomeMark;
@property(nonatomic,strong) UIButton *ideaButton;
@property(nonatomic,strong) UIButton *helpButton;
@property(nonatomic,strong) UILabel *welcomeSubtitle;
@property(nonatomic,strong) XFChatBubble *streamBubble;
@property(nonatomic,strong) XFChatBubble *selectedBubble;
@end

@implementation XFChatView


- (id)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        self.backgroundColor=XFCanvas();
        self.scroll=[[UIScrollView alloc] initWithFrame:self.bounds];
        self.scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        self.scroll.backgroundColor=[UIColor clearColor];
        self.scroll.showsVerticalScrollIndicator=YES;
        self.scroll.alwaysBounceVertical=YES;
        [self addSubview:self.scroll];
        self.bubbles=[NSMutableArray array];
        [self showWelcome];
    }
    return self;
}
- (void)clearBubbles {
    for(UIView *view in self.bubbles)[view removeFromSuperview];
    [self.bubbles removeAllObjects];
    self.streamBubble=nil;
}
- (void)hideWelcome {
    self.welcomeTitle.hidden=YES;
    self.welcomeSubtitle.hidden=YES;
    self.welcomeMark.hidden=YES;
    self.ideaButton.hidden=YES;
    self.helpButton.hidden=YES;
}
- (void)showWelcome {
    [self clearBubbles];
    if(!self.welcomeTitle){
        XFLineButton *mark=[[XFLineButton alloc] initWithSymbol:@"wave"];
        mark.symbolColor=XFAccent();
        mark.backgroundColor=[UIColor clearColor];
        mark.userInteractionEnabled=NO;
        [self addSubview:mark];
        self.welcomeMark=mark;
        UILabel *title=[[UILabel alloc] init];
        title.font=[UIFont boldSystemFontOfSize:23];
        title.textColor=XFInk();
        title.text=@"F-01 · 异常在线";
        title.textAlignment=NSTextAlignmentCenter;
        [self addSubview:title];self.welcomeTitle=title;
        UILabel *subtitle=[[UILabel alloc] init];
        subtitle.font=[UIFont systemFontOfSize:13];
        subtitle.textColor=XFSecondary();
        subtitle.numberOfLines=0;subtitle.textAlignment=NSTextAlignmentCenter;
        subtitle.text=@"本机有点老，脑子还行。\n交给我一件支线任务。";
        [self addSubview:subtitle];self.welcomeSubtitle=subtitle;
        self.ideaButton=[self quickButton:@"规划今天的任务" target:@selector(quickIdea)];
        self.helpButton=[self quickButton:@"让我认识 F-01" target:@selector(quickHelp)];
    }
    self.welcomeTitle.hidden=NO;self.welcomeSubtitle.hidden=NO;
    self.welcomeMark.hidden=NO;self.ideaButton.hidden=NO;self.helpButton.hidden=NO;
    [self layoutWelcome];
    self.scroll.contentSize=CGSizeMake(self.bounds.size.width,self.bounds.size.height+1);
    self.scroll.contentOffset=CGPointZero;
}
- (UIButton *)quickButton:(NSString *)text target:(SEL)target {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:text forState:UIControlStateNormal];
    [button setTitleColor:XFInk() forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont systemFontOfSize:13];
    XFCard(button,12);
    [button addTarget:self action:target forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:button];
    return button;
}
- (void)quickIdea {if(self.onQuickPrompt)self.onQuickPrompt(@"帮我制定今天的三件核心任务，分解为可以执行的小步骤，并保存为待办。");}
- (void)quickHelp {if(self.onQuickPrompt)self.onQuickPrompt(@"F-01，介绍一下你自己，以及你在这部旧手机上真正能帮我做什么。");}
- (void)layoutWelcome {
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    CGFloat center=MAX(104,h*0.36);
    self.welcomeMark.frame=CGRectMake((w-52)/2,center-81,52,52);
    self.welcomeTitle.frame=CGRectMake(12,center-14,w-24,35);
    self.welcomeSubtitle.frame=CGRectMake(20,center+21,w-40,38);
    CGFloat buttonW=MIN(244,w-42);
    self.ideaButton.frame=CGRectMake((w-buttonW)/2,center+79,buttonW,43);
    self.helpButton.frame=CGRectMake((w-buttonW)/2,center+130,buttonW,43);
}
- (XFChatBubble *)makeBubble:(NSString *)text user:(BOOL)user notice:(BOOL)notice imageName:(NSString *)imageName {
    XFChatBubble *bubble=[[XFChatBubble alloc] initWithFrame:CGRectZero];
    bubble.user=user;bubble.notice=notice;
    bubble.backgroundColor=notice?XFAccentPale():(user?XFAccent():XFPaper());
    bubble.layer.cornerRadius=15;
    bubble.layer.borderWidth=notice?0:0.7;
    bubble.layer.borderColor=XFLine().CGColor;
    if(!user && !notice){
        UILabel *role=[[UILabel alloc] initWithFrame:CGRectZero];
        role.text=@"小斐";
        role.font=[UIFont boldSystemFontOfSize:10];
        role.textColor=XFAccent();
        [bubble addSubview:role];
        bubble.roleLabel=role;
    }
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectZero];
    label.font=[UIFont systemFontOfSize:15.0];
    label.textColor=user?XFPaper():XFInk();
    if(notice){label.textColor=XFAccent();label.font=[UIFont systemFontOfSize:12];}
    label.numberOfLines=0;label.lineBreakMode=NSLineBreakByWordWrapping;
    label.text=text?:@"";
    [bubble addSubview:label];
    bubble.label=label;
    if(imageName.length){
        UIImage *thumb=[XFChatStore thumbnailForName:imageName];
        if(thumb){
            UIImageView *picture=[[UIImageView alloc] initWithImage:thumb];
            picture.contentMode=UIViewContentModeScaleAspectFill;
            picture.clipsToBounds=YES;
            picture.layer.cornerRadius=8;
            picture.userInteractionEnabled=YES;
            picture.accessibilityIdentifier=imageName;
            UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageTapped:)];
            [picture addGestureRecognizer:tap];
            [bubble addSubview:picture];
            bubble.imagePreview=picture;
            bubble.imageName=imageName;
        }
    }
    bubble.userInteractionEnabled=YES;
    UILongPressGestureRecognizer *longPress=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(bubbleLongPressed:)];
    longPress.minimumPressDuration=0.45;
    [bubble addGestureRecognizer:longPress];
    [self.scroll addSubview:bubble];
    [self.bubbles addObject:bubble];
    if(self.bubbles.count>24){
        XFChatBubble *old=self.bubbles[0];[old removeFromSuperview];[self.bubbles removeObjectAtIndex:0];
    }
    return bubble;
}
- (XFChatBubble *)makeBubble:(NSString *)text user:(BOOL)user notice:(BOOL)notice {
    return [self makeBubble:text user:user notice:notice imageName:nil];
}
- (void)imageTapped:(UITapGestureRecognizer *)gesture {
    NSString *filename=gesture.view.accessibilityIdentifier;
    UIImage *image=[XFChatStore imageForName:filename];
    if(image && self.onImageTap)self.onImageTap(image);
}
- (BOOL)canBecomeFirstResponder {return YES;}
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    return action==@selector(copy:) && self.selectedBubble.label.text.length>0;
}
- (void)copy:(id)sender {
    NSString *text=self.selectedBubble.label.text;
    if(text.length)[UIPasteboard generalPasteboard].string=text;
    self.selectedBubble=nil;
}
- (void)bubbleLongPressed:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan)return;
    XFChatBubble *bubble=(XFChatBubble *)gesture.view;
    if(!bubble.label.text.length)return;
    self.selectedBubble=bubble;
    [self becomeFirstResponder];
    UIMenuController *menu=[UIMenuController sharedMenuController];
    [menu setTargetRect:bubble.bounds inView:bubble];
    [menu setMenuVisible:YES animated:YES];
}
- (void)showConversation:(NSArray *)messages {
    [self clearBubbles];
    if(!messages.count){[self showWelcome];return;}
    [self hideWelcome];
    NSUInteger begin=messages.count>24?messages.count-24:0;
    for(NSUInteger i=begin;i<messages.count;i++){
        NSDictionary *message=messages[i];
        NSString *text=message[@"content"];
        if(![text isKindOfClass:[NSString class]])continue;
        BOOL user=[message[@"role"] isEqualToString:@"user"];
        NSString *filename=[message[@"image_file"] isKindOfClass:[NSString class]]?message[@"image_file"]:nil;
        [self makeBubble:text user:user notice:NO imageName:filename];
    }
    [self layoutBubbles:YES];
}
- (void)addMessage:(NSString *)text fromUser:(BOOL)user {
    [self hideWelcome];
    self.streamBubble=nil;
    [self makeBubble:text user:user notice:NO];
    [self layoutBubbles:YES];
}
- (void)addImageMessage:(NSString *)text imageName:(NSString *)filename {
    [self hideWelcome];
    self.streamBubble=nil;
    [self makeBubble:text user:YES notice:NO imageName:filename];
    [self layoutBubbles:YES];
}
- (void)addGeneratedImageMessage:(NSString *)text imageName:(NSString *)filename {
    [self hideWelcome];
    self.streamBubble=nil;
    [self makeBubble:text user:NO notice:NO imageName:filename];
    [self layoutBubbles:YES];
}
- (void)updateStreaming:(NSString *)text {
    [self hideWelcome];
    if(!self.streamBubble){
        self.streamBubble=[self makeBubble:@"正在思考…" user:NO notice:NO];
    }
    self.streamBubble.label.text=text.length?text:@"正在思考…";
    [self layoutBubbles:YES];
}
- (void)finishStreaming:(NSString *)text {
    if(self.streamBubble){
        self.streamBubble.label.text=text?:@"";
        self.streamBubble=nil;
        [self layoutBubbles:YES];
    } else if(text.length) {
        [self addMessage:text fromUser:NO];
    }
}
- (void)showNotice:(NSString *)text {
    if(!text.length)return;
    [self hideWelcome];
    [self makeBubble:text user:NO notice:YES];
    [self layoutBubbles:YES];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutWelcome];
    [self layoutBubbles:NO];
}
- (void)layoutBubbles:(BOOL)scrollToBottom {
    CGFloat width=self.bounds.size.width;
    if(width<100)return;
    CGFloat y=15;
    for(XFChatBubble *bubble in self.bubbles){
        CGFloat bubbleWidth=MIN(width-42,300);
        CGFloat labelWidth=bubbleWidth-28;
        CGSize max=CGSizeMake(labelWidth,CGFLOAT_MAX);
        CGSize measured=[bubble.label sizeThatFits:max];
        CGFloat actualWidth=MIN(labelWidth,MAX(65,ceil(measured.width)));
        BOOL hasImage=bubble.imagePreview!=nil;
        if(hasImage)actualWidth=MAX(actualWidth,165);
        CGFloat imageHeight=hasImage?118:0;
        CGFloat labelTop=bubble.roleLabel?29:12;
        CGFloat h=MAX(39,ceil(measured.height)+labelTop+13)+(hasImage?imageHeight+10:0);
        CGFloat w=actualWidth+28;
        CGFloat x=bubble.user?width-12-w:12;
        if(bubble.notice){x=(width-w)/2;}
        bubble.frame=CGRectMake(floor(x),y,ceil(w),h);
        bubble.roleLabel.frame=CGRectMake(14,9,actualWidth,13);
        bubble.label.frame=CGRectMake(14,labelTop,actualWidth,ceil(measured.height)+2);
        if(hasImage)bubble.imagePreview.frame=CGRectMake(14,labelTop+ceil(measured.height)+7,actualWidth,imageHeight);
        y+=h+10;
    }
    self.scroll.contentSize=CGSizeMake(width,MAX(self.scroll.bounds.size.height+1,y+9));
    if(scrollToBottom){
        CGFloat maxY=MAX(0,self.scroll.contentSize.height-self.scroll.bounds.size.height);
        [self.scroll setContentOffset:CGPointMake(0,maxY) animated:NO];
    }
}
@end
