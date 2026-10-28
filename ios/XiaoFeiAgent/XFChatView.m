#import "XFChatView.h"
#import <QuartzCore/QuartzCore.h>
@interface XFChatBubble : UIView
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,assign) BOOL user;
@property(nonatomic,assign) BOOL notice;
@end
@implementation XFChatBubble
@end

@interface XFChatView ()
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) NSMutableArray *bubbles;
@property(nonatomic,strong) UILabel *welcomeTitle;
@property(nonatomic,strong) UILabel *welcomeSubtitle;
@property(nonatomic,strong) XFChatBubble *streamBubble;
@end

@implementation XFChatView

static UIColor *XFInk(void) {return [UIColor colorWithRed:0.15 green:0.20 blue:0.31 alpha:1];}
static UIColor *XFIndigo(void) {return [UIColor colorWithRed:0.32 green:0.38 blue:0.79 alpha:1];}
static UIColor *XFGray(void) {return [UIColor colorWithRed:0.45 green:0.49 blue:0.58 alpha:1];}

- (id)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        self.backgroundColor=[UIColor colorWithRed:0.966 green:0.973 blue:0.987 alpha:1];
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
}
- (void)showWelcome {
    [self clearBubbles];
    if(!self.welcomeTitle){
        UILabel *title=[[UILabel alloc] init];
        title.font=[UIFont boldSystemFontOfSize:24];
        title.textColor=XFInk();
        title.text=@"你好，我是小斐";
        title.textAlignment=NSTextAlignmentCenter;
        [self addSubview:title];self.welcomeTitle=title;
        UILabel *subtitle=[[UILabel alloc] init];
        subtitle.font=[UIFont systemFontOfSize:13];
        subtitle.textColor=XFGray();
        subtitle.numberOfLines=0;subtitle.textAlignment=NSTextAlignmentCenter;
        subtitle.text=@"让每个模型，都成为你的灵感助手\n选择模型，然后开始对话";
        [self addSubview:subtitle];self.welcomeSubtitle=subtitle;
    }
    self.welcomeTitle.hidden=NO;self.welcomeSubtitle.hidden=NO;
    [self layoutWelcome];
    self.scroll.contentSize=CGSizeMake(self.bounds.size.width,self.bounds.size.height+1);
    self.scroll.contentOffset=CGPointZero;
}
- (void)layoutWelcome {
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    CGFloat center=MAX(110,h*0.40);
    self.welcomeTitle.frame=CGRectMake(12,center-45,w-24,35);
    self.welcomeSubtitle.frame=CGRectMake(20,center+4,w-40,45);
}
- (XFChatBubble *)makeBubble:(NSString *)text user:(BOOL)user notice:(BOOL)notice {
    XFChatBubble *bubble=[[XFChatBubble alloc] initWithFrame:CGRectZero];
    bubble.user=user;bubble.notice=notice;
    bubble.backgroundColor=notice?[UIColor colorWithRed:0.91 green:0.93 blue:0.98 alpha:1]:
        (user?XFIndigo():[UIColor whiteColor]);
    bubble.layer.cornerRadius=13;
    if(!user && !notice){
        bubble.layer.borderWidth=0.5;
        bubble.layer.borderColor=[UIColor colorWithRed:0.88 green:0.90 blue:0.95 alpha:1].CGColor;
    }
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectZero];
    label.font=[UIFont systemFontOfSize:15.0];
    label.textColor=user?[UIColor whiteColor]:XFInk();
    if(notice){label.textColor=XFGray();label.font=[UIFont systemFontOfSize:12];}
    label.numberOfLines=0;label.lineBreakMode=NSLineBreakByWordWrapping;
    label.text=text?:@"";
    [bubble addSubview:label];
    bubble.label=label;
    [self.scroll addSubview:bubble];
    [self.bubbles addObject:bubble];
    if(self.bubbles.count>24){
        XFChatBubble *old=self.bubbles[0];[old removeFromSuperview];[self.bubbles removeObjectAtIndex:0];
    }
    return bubble;
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
        [self makeBubble:text user:user notice:NO];
    }
    [self layoutBubbles:YES];
}
- (void)addMessage:(NSString *)text fromUser:(BOOL)user {
    [self hideWelcome];
    self.streamBubble=nil;
    [self makeBubble:text user:user notice:NO];
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
        CGFloat bubbleWidth=MIN(width-52,300);
        CGFloat labelWidth=bubbleWidth-26;
        CGSize max=CGSizeMake(labelWidth,CGFLOAT_MAX);
        CGSize measured=[bubble.label sizeThatFits:max];
        CGFloat actualWidth=MIN(labelWidth,MAX(65,ceil(measured.width)));
        CGFloat h=MAX(37,ceil(measured.height)+21);
        CGFloat w=actualWidth+26;
        CGFloat x=bubble.user?width-13-w:13;
        if(bubble.notice){x=(width-w)/2;}
        bubble.frame=CGRectMake(floor(x),y,ceil(w),h);
        bubble.label.frame=CGRectMake(13,10,actualWidth,ceil(measured.height)+2);
        y+=h+12;
    }
    self.scroll.contentSize=CGSizeMake(width,MAX(self.scroll.bounds.size.height+1,y+9));
    if(scrollToBottom){
        CGFloat maxY=MAX(0,self.scroll.contentSize.height-self.scroll.bounds.size.height);
        [self.scroll setContentOffset:CGPointMake(0,maxY) animated:NO];
    }
}
@end
