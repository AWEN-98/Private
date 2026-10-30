#import <UIKit/UIKit.h>

// XiaoFei Design System 2.0. UIKit only; iOS 8.0+ and armv7 safe.
static inline UIColor *XFCanvas(void) {return [UIColor colorWithRed:0.966 green:0.974 blue:0.971 alpha:1];}
static inline UIColor *XFPaper(void) {return [UIColor whiteColor];}
static inline UIColor *XFAccent(void) {return [UIColor colorWithRed:0.075 green:0.525 blue:0.443 alpha:1];}
static inline UIColor *XFAccentPale(void) {return [UIColor colorWithRed:0.892 green:0.958 blue:0.932 alpha:1];}
static inline UIColor *XFInk(void) {return [UIColor colorWithRed:0.087 green:0.165 blue:0.149 alpha:1];}
static inline UIColor *XFSecondary(void) {return [UIColor colorWithRed:0.410 green:0.494 blue:0.465 alpha:1];}
static inline UIColor *XFLine(void) {return [UIColor colorWithRed:0.859 green:0.905 blue:0.885 alpha:1];}
static inline UIColor *XFDanger(void) {return [UIColor colorWithRed:0.775 green:0.275 blue:0.260 alpha:1];}
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
