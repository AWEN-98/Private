#import "XFTheme.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
@interface XFLineButton ()
@end
@implementation XFLineButton
- (instancetype)initWithSymbol:(NSString *)symbol {
    if((self=[super initWithFrame:CGRectZero])){
        self.symbol=symbol;
        self.symbolColor=XFInk();
        self.backgroundColor=[UIColor clearColor];
        self.adjustsImageWhenHighlighted=NO;
        self.accessibilityTraits=UIAccessibilityTraitButton;
    }
    return self;
}
- (void)setSymbol:(NSString *)symbol{_symbol=[symbol copy];[self setNeedsDisplay];}
- (void)setBackgroundColor:(UIColor *)color {
    // No tinted backgrounds behind any icon-only controls.
    [super setBackgroundColor:[UIColor clearColor]];
}
- (void)setSymbolColor:(UIColor *)symbolColor{_symbolColor=symbolColor;[self setNeedsDisplay];}
- (void)drawRect:(CGRect)r{
    [super drawRect:r];
    NSString *n=self.symbol;
    if(!n.length)return;
    CGContextRef c=UIGraphicsGetCurrentContext();
    CGContextSaveGState(c);
    UIColor *tint=self.symbolColor?:XFInk();
    CGContextSetStrokeColorWithColor(c,tint.CGColor);
    CGContextSetFillColorWithColor(c,tint.CGColor);
    CGContextSetLineWidth(c,1.85);
    CGContextSetLineCap(c,kCGLineCapRound);
    CGContextSetLineJoin(c,kCGLineJoinRound);
    // Large tap targets, compact 24-point line glyphs.
    CGFloat scale=MIN(1.0,MIN(r.size.width/24.0,r.size.height/24.0));
    CGContextTranslateCTM(c,(r.size.width-24*scale)/2.0,(r.size.height-24*scale)/2.0);
    CGContextScaleCTM(c,scale,scale);
    if([n isEqualToString:@"plus"]){
        CGContextMoveToPoint(c,12,5);CGContextAddLineToPoint(c,12,19);
        CGContextMoveToPoint(c,5,12);CGContextAddLineToPoint(c,19,12);
    }else if([n isEqualToString:@"wave"]){
        CGContextMoveToPoint(c,2,12);CGContextAddLineToPoint(c,6,12);
        CGContextAddCurveToPoint(c,7,12,7,5,9,5);
        CGContextAddCurveToPoint(c,11,5,10,19,12,19);
        CGContextAddCurveToPoint(c,14,19,13,8,15,8);
        CGContextAddCurveToPoint(c,17,8,16,12,19,12);
        CGContextAddLineToPoint(c,22,12);
    }else if([n isEqualToString:@"send"]){
        CGContextMoveToPoint(c,4,12);CGContextAddLineToPoint(c,20,4);
        CGContextAddLineToPoint(c,14,20);CGContextAddLineToPoint(c,11,13);
        CGContextAddLineToPoint(c,4,12);
        CGContextMoveToPoint(c,11,13);CGContextAddLineToPoint(c,20,4);
    }else if([n isEqualToString:@"history"]){
        CGContextAddArc(c,12,12,8,0.35,2*M_PI-0.45,0);
        CGContextMoveToPoint(c,3,5);CGContextAddLineToPoint(c,3,11);
        CGContextAddLineToPoint(c,9,11);
        CGContextMoveToPoint(c,12,7);CGContextAddLineToPoint(c,12,12);
        CGContextAddLineToPoint(c,16,14);
    }else if([n isEqualToString:@"models"]){
        CGContextAddPath(c,[UIBezierPath bezierPathWithRoundedRect:CGRectMake(4,4,16,16) cornerRadius:3].CGPath);
        CGContextMoveToPoint(c,9,4);CGContextAddLineToPoint(c,9,20);
        CGContextMoveToPoint(c,14,4);CGContextAddLineToPoint(c,14,20);
        CGContextMoveToPoint(c,4,10);CGContextAddLineToPoint(c,20,10);
    }else if([n isEqualToString:@"image"]){
        CGContextAddPath(c,[UIBezierPath bezierPathWithRoundedRect:CGRectMake(3,4,18,16) cornerRadius:3].CGPath);
        CGContextAddEllipseInRect(c,CGRectMake(14,7,3,3));
        CGContextMoveToPoint(c,4,17);CGContextAddLineToPoint(c,9,12);
        CGContextAddLineToPoint(c,12,15);CGContextAddLineToPoint(c,15,12);
        CGContextAddLineToPoint(c,20,18);
    }else if([n isEqualToString:@"mic"]){
        CGContextAddPath(c,[UIBezierPath bezierPathWithRoundedRect:CGRectMake(9,4,6,11) cornerRadius:3].CGPath);
        CGContextMoveToPoint(c,6,11);CGContextAddArc(c,12,11,6,M_PI,0,1);
        CGContextMoveToPoint(c,12,17);CGContextAddLineToPoint(c,12,21);
        CGContextMoveToPoint(c,8,21);CGContextAddLineToPoint(c,16,21);
    }else if([n isEqualToString:@"stop"]){
        CGContextAddPath(c,[UIBezierPath bezierPathWithRoundedRect:CGRectMake(5,5,14,14) cornerRadius:2.5].CGPath);
    }else if([n isEqualToString:@"search"]){
        CGContextAddEllipseInRect(c,CGRectMake(4,3,13,13));
        CGContextMoveToPoint(c,15,15);CGContextAddLineToPoint(c,21,21);
    }else if([n isEqualToString:@"spark"]){
        CGContextMoveToPoint(c,12,2);CGContextAddLineToPoint(c,15,9);
        CGContextAddLineToPoint(c,22,12);CGContextAddLineToPoint(c,15,15);
        CGContextAddLineToPoint(c,12,22);CGContextAddLineToPoint(c,9,15);
        CGContextAddLineToPoint(c,2,12);CGContextAddLineToPoint(c,9,9);
        CGContextClosePath(c);
    }else if([n isEqualToString:@"more"]){
        for(NSInteger k=0;k<3;k++)CGContextAddEllipseInRect(c,CGRectMake(4+k*7.0,10,3.1,3.1));
        CGContextFillPath(c);CGContextRestoreGState(c);return;
    }else if([n isEqualToString:@"back"]){
        CGContextMoveToPoint(c,14,4);CGContextAddLineToPoint(c,6,12);
        CGContextAddLineToPoint(c,14,20);
    }else if([n isEqualToString:@"check"]){
        CGContextMoveToPoint(c,4,12);CGContextAddLineToPoint(c,10,18);
        CGContextAddLineToPoint(c,21,5);
    }else{
        CGContextAddEllipseInRect(c,CGRectMake(4,4,16,16));
    }
    CGContextStrokePath(c);
    CGContextRestoreGState(c);
}
@end
