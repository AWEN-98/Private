#!/usr/bin/env python3
"""Check anonymous feed, QR sign-in and minimalist old-iOS UI contracts."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
s=(root/"main.m").read_text(encoding="utf-8")
qr=(root/"DLLoginController.m").read_text(encoding="utf-8")
phone=(root/"DLPhoneWebLoginController.m").read_text(encoding="utf-8")
session=(root/"DLAccountSession.m").read_text(encoding="utf-8")
view=s[s.index("- (void)viewDidLoad {"):s.index("- (void)viewDidLayoutSubviews")]
tabs=s[s.index("- (void)tabPressed:"):s.index("- (BOOL)gestureRecognizer:")]
checks={
 "Guest home loads without session check": "self.onlineMode=YES;self.demoMode=NO;self.index=0;" in view and "[self loadOnlineFeed:YES]" in view,
 "Public mobile feed attempted first": "[self requestMobileFeed:0 token:token reset:reset];" in s,
 "Second official mobile host": "aweme.snssdk.com/aweme/v1/feed/" in s,
 "Native video URLs only": "DLPublicPlaybackURL(item)" in s,
 "No fabricated placeholders in response": "if(++inserted>=12)break;" in s,
 "Native web feed fallback": "[self loadDouyinAccountFeedWeb:reset];" in s,
 "Preflight anonymous visitor cookies": "if(!self.guestPrimed && !DLAccountSession.shared.hasSession)" in s,
 "Uses browser-equivalent signed feed": "/aweme/v2/web/module/feed/" in session and "a_bogus" in session,
 "Anonymous attempt does not require QR login": "[DLAccountSession.shared prepareLogin:" in s and "if(!self.guestPrimed" in s,
 "My tab opens QR login directly": "else if(tab==3)[self openAccount];" in tabs,
 "Official SSO QR endpoint": 'https://sso.douyin.com/get_qrcode/?' in qr,
 "QR primary app id and service match SSO flow": 'aid=10006&service=https%%3A%%2F%%2Fwww.douyin.com%%2Fpay' in qr,
 "Fallback QR endpoint remains available": 'https://login.douyin.com/passport/web/get_qrcode/?' in qr,
 "Primary QR polling uses GET": 'https://sso.douyin.com/check_qrconnect/?' in qr and 'aid=10006&token=%@' in qr,
 "Fallback QR polling endpoint": 'https://login.douyin.com/passport/web/check_qrconnect/?' in qr,
 "Status 1 waits, status 2 means scanned": '@[@"1",@"wait",@"waiting"]' in qr and '@[@"2",@"scanned",@"scanning"]' in qr,
 "Status 3 waits for redirect callback": '@[@"3",@"confirmed",@"success"]' in qr and '正在等待抖音返回登录回调' in qr,
 "Status 5 expires QR": '@[@"5",@"4",@"expired"' in qr,
 "QR code actually rendered": "CIQRCodeGenerator" in qr,
 "QR polling 4031 is diagnosed rather than ignored": "if([serverCode isEqualToString:@\"4031\"])" in qr,
 "Account screen defaults to on-device web login": '打开抖音官网 · 手机登录' in qr and 'action:@selector(openPhoneLogin)' in qr,
 "Phone browser receives official webpage": 'https://www.douyin.com/' in phone and 'https://www.douyin.com/user/self' in phone,
 "Phone browser uses shared system cookie jar": 'UIWebView' in phone and 'NSHTTPCookieStorage' in phone,
 "Phone browser validates official HTTPS hosts": 'DLPhoneOfficialPage(url)' in phone and 'url.scheme.lowercaseString' in phone,
 "Phone browser reads session without exposing it": 'DLAccountSession.shared.hasSession' in phone and 'print' not in phone,
 "Phone browser verifies account and persists session": '[DLAccountSession.shared verifyAccount:' in phone and '[self saveSession]' in session,
 "Phone browser does not ask user for passwords": 'UITextField' not in phone,
 "Old QR remains explicit opt-in": 'action:@selector(startLogin)' in qr and 'else [self startLogin]' not in qr,
 "Account screen no longer requires PC bridge": 'openBridgeLogin' not in qr and 'DLRemoteBrowserController' not in qr,
 "QR requests use isolated login headers": "loginRequest:" in session and "x-tt-argus" not in session[session.index("- (NSMutableURLRequest *)loginRequest:"):session.index("- (void)prepareLogin:")],
 "Login redirects retain official SSO domain": "DLIsOfficialLoginURL(request.URL)?request:nil" in session,
 "Login callback fetches redirect before account verification": "loginRequest:url.absoluteString" in session and "verifyAccount:completion" in session,
 "Authenticated session verified": "verifyAccount" in qr and "account/info" in session,
 "Login cookies saved": "[self saveSession]" in session,
 "Visitor and signed-in feed refreshes": "DLAccountDidChangeNotification" in s and "self.guestPrimed=NO" in s,
 "No fake doubletap likes": "doubleTapVideo:" not in s,
 "No unsupported comments control": "action:@selector(openComments)" not in view,
 "Local favorites use bookmark": 'DLStyleIcon(self.likeButton,@"bookmark"' in s,
 "No obsolete corner controls": "top.tag=100;" in view and "action:@selector(addVideo)" not in view and "action:@selector(openMenu)" not in s,
 "Compact four tabs": 'NSArray *names=@[@"首页",@"直播",@"收藏",@"我的"]' in view,
 "Invalid session suggests phone official login": "请在上方尝试官方网页登录" in qr and "else [self startLogin]" not in qr,
 "Logout leaves user to choose official web login": "已清除本机账号" in qr and "正在重新申请二维码" not in qr,
 "No cloud login shortcut": 'action:@selector(openWebsite)' not in qr,
}
for k,v in checks.items():print(("PASS" if v else "FAIL")+": "+k)
if not all(checks.values()):raise SystemExit(1)
