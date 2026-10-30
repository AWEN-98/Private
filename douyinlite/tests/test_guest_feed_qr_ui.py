#!/usr/bin/env python3
"""Check anonymous feed, QR sign-in and minimalist old-iOS UI contracts."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
s=(root/"main.m").read_text(encoding="utf-8")
qr=(root/"DLLoginController.m").read_text(encoding="utf-8")
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
 "Official QR endpoint": "passport/web/get_qrcode/" in qr,
 "QR polling endpoint": "passport/web/check_qrconnect/" in qr,
 "QR code actually rendered": "CIQRCodeGenerator" in qr,
 "Authenticated session verified": "verifyAccount" in qr and "account/info" in session,
 "Login cookies saved": "[self saveSession]" in session,
 "Visitor and signed-in feed refreshes": "DLAccountDidChangeNotification" in s and "self.guestPrimed=NO" in s,
 "No fake doubletap likes": "doubleTapVideo:" not in s,
 "No unsupported comments control": "action:@selector(openComments)" not in view,
 "Local favorites use bookmark": 'DLStyleIcon(self.likeButton,@"bookmark"' in s,
 "No obsolete corner controls": "top.tag=100;" in view and "action:@selector(addVideo)" not in view and "action:@selector(openMenu)" not in s,
 "Compact four tabs": 'NSArray *names=@[@"首页",@"直播",@"收藏",@"我的"]' in view,
 "Stale saved session automatically requests QR": "if(ok){self.token=nil;self.qr.image=nil;}else [self startLogin];" in qr,
 "Logout starts fresh QR request": "已退出账号，正在重新申请二维码" in qr and "[self startLogin]" in qr,
 "No cloud login shortcut": 'action:@selector(openWebsite)' not in qr,
}
for k,v in checks.items():print(("PASS" if v else "FAIL")+": "+k)
if not all(checks.values()):raise SystemExit(1)
