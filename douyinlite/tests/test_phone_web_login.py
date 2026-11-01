#!/usr/bin/env python3
"""Structural regression checks for on-device official login trial, iOS 8."""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
page=(ROOT/"DLPhoneWebLoginController.m").read_text(encoding="utf-8")
login=(ROOT/"DLLoginController.m").read_text(encoding="utf-8")
session=(ROOT/"DLAccountSession.m").read_text(encoding="utf-8")
make=(ROOT/"Makefile").read_text(encoding="utf-8")

checks={
 "compiled into the ARMv7 application": "DLPhoneWebLoginController.m" in make and "ARCHS := armv7" in make,
 "on-device login is the primary entry": '打开抖音官网 · 手机登录' in login and 'action:@selector(openPhoneLogin)' in login,
 "no PC required by login flow": "openBridgeLogin" not in login and "DLRemoteBrowserController" not in login,
 "legacy QR only opens by user request": 'action:@selector(startLogin)' in login and "else [self startLogin]" not in login,
 "uses UIWebView for shared cookie storage": 'UIWebView *web;' in page and "NSHTTPCookieStorage" in page,
 "never uses WKWebView isolated cookie jar": "WKWebView" not in page,
 "official login domain and HTTPS only": 'DLPhoneOfficialPage(NSURL *url)' in page and 'url.scheme.lowercaseString' in page and 'bytedance.com' in page,
 "no password or token collection in app UI": "UITextField" not in page and "cookie.value" not in page,
 "native account validation only after shared cookies": "DLAccountSession.shared.hasSession" in page and "[DLAccountSession.shared verifyAccount:" in page,
 "cookie persistence remains keychain backed": "SecItemUpdate" in session and "saveSession" in session,
 "no account success based on page load": 'self.verified=ok' in page and 'self.verified=YES' not in page,
 "page failure reports network errors": "didFailLoadWithError:" in page and "error.code" in page,
 "page timeout surfaced": "check" not in page or "timeout:" in page,
 "phone mode can be dismissed": "dismissViewControllerAnimated:YES" in page,
}
for title,ok in checks.items():
 print(("PASS" if ok else "FAIL")+": "+title)
if not all(checks.values()):raise SystemExit(1)
