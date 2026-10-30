#import <UIKit/UIKit.h>

// XiaoFei Design System 2.0. UIKit only; iOS 8.0+ and armv7 safe.
static inline UIColor *XFCanvas(void) {return [UIColor colorWithRed:0.960784 green:0.972549 blue:1.0 alpha:1];}
static inline UIColor *XFPaper(void) {return [UIColor whiteColor];}
static inline UIColor *XFAccent(void) {return [UIColor colorWithRed:0.290196 green:0.486275 blue:1.0 alpha:1];}
static inline UIColor *XFAccentPale(void) {return [UIColor colorWithRed:0.917647 green:0.945098 blue:1.0 alpha:1];}
static inline UIColor *XFInk(void) {return [UIColor colorWithRed:0.121569 green:0.164706 blue:0.266667 alpha:1];}
static inline UIColor *XFSecondary(void) {return [UIColor colorWithRed:0.431373 green:0.478431 blue:0.588235 alpha:1];}
static inline UIColor *XFLine(void) {return [UIColor colorWithRed:0.862745 green:0.898039 blue:0.960784 alpha:1];}
static inline UIColor *XFDanger(void) {return [UIColor colorWithRed:1.0 green:0.352941 blue:0.372549 alpha:1];}
static inline void XFApplyNavigation(UINavigationController *nav) {
    if(!nav)return;
    nav.navigationBar.translucent=NO;
    nav.navigationBar.barTintColor=XFPaper();
    nav.navigationBar.tintColor=XFAccent();
    nav.navigationBar.titleTextAttributes=@{NSForegroundColorAttributeName:XFInk(),
        NSFontAttributeName:[UIFont boldSystemFontOfSize:17]};
}
static inline void XFCard(UIView *v, CGFloat radius) {
    v.backgroundColor=XFPaper();
    v.layer.cornerRadius=radius;
    v.layer.borderWidth=0.65;
    v.layer.borderColor=XFLine().CGColor;
}
@interface XFLineButton : UIButton
@property(nonatomic,copy) NSString *symbol;
@property(nonatomic,strong) UIColor *symbolColor;
- (instancetype)initWithSymbol:(NSString *)symbol;
@end
