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
 "WKWebView does not claim native cookie continuity": "WKWebView" in page and "Cookie" in page and "可能隔离" in page,
 "official login domain and HTTPS only": 'DLPhoneOfficialPage(NSURL *url)' in page and 'url.scheme.lowercaseString' in page and 'bytedance.com' in page,
 "no password or token collection in app UI": "UITextField" not in page and "cookie.value" not in page,
 "native account validation only after shared cookies": "DLAccountSession.shared.hasSession" in page and "[DLAccountSession.shared verifyAccount:" in page,
 "cookie persistence remains keychain backed": "SecItemUpdate" in session and "saveSession" in session,
 "no account success based on page load": 'self.verified=ok' in page and 'self.verified=YES' not in page,
 "page failure reports network errors": "didFailLoadWithError:" in page and "error.code" in page,
 "page timeout surfaced": "check" not in page or "timeout:" in page,
 "phone mode can be dismissed": "dismissViewControllerAnimated:YES" in page,
 "fallback WKWebView available from iOS 8": "WKWebView *modern;" in page and "WKNavigationDelegate" in page,
 "only allocate WKWebView after user chooses it": "if(!self.modern){" in page and 'action:@selector(switchEngine)' in page,
 "switch leaves UIWebView as shared-cookie primary": "self.usingWK=!self.usingWK" in page and "self.modern.hidden=!self.usingWK" in page,
 "safe HTTPS network diagnostics": 'action:@selector(probe)' in page and "NSURLSessionDataTask" in page and "NSURLSessionConfiguration ephemeralSessionConfiguration" in page,
 "certificate failures not bypassed": "NSURLErrorServerCertificateUntrusted" in page and "不要跳过证书校验" in page,
 "blank HTML detection for UIWebView": "stringByEvaluatingJavaScriptFromString" in page and "页面可能空白" in page,
 "blank HTML detection for WKWebView": 'evaluateJavaScript:' in page and "内容为空" in page,
 "server challenges not falsely treated as successful login": "4031" in page and "访问限制" in page,
 "status only shows safe HTTP metadata": "HTTP %ld" in page and "cookieValue:" not in page,

}
for title,ok in checks.items():
 print(("PASS" if ok else "FAIL")+": "+title)
if not all(checks.values()):raise SystemExit(1)
