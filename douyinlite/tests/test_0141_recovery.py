#!/usr/bin/env python3
"""Regression contracts for V0.14.1 guest content recovery, live and QR."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
main=(root/"main.m").read_text(encoding="utf-8")
qr=(root/"DLLoginController.m").read_text(encoding="utf-8")
checks={
 "Hot category uses real video search first": '[self searchVideos:@"热门" reset:YES]' in main,
 "Other categories still search": '[self searchVideos:categories[idx] reset:YES]' in main,
 "Category retries other real search phrases": 'self.categorySearchAttempt++' in main and 'self searchVideos:term reset:YES' in main,
 "Category no longer redirects to homepage when empty": 'self.searchMode=NO;self.searchEnd=YES;self.onlineMode=YES' not in main[main.index("- (void)fallbackForFailedSearch:"):main.index("- (void)searchVideos:")],
 "Category failures state actual error": 'self.message.text=[NSString stringWithFormat:@"%@：%@。可以稍后重试或先在「我的」登录。"' in main,
 "Category search parses nested response": 'NSDictionary *inner=nested;' in main,
 "Search no-result invokes fallback": '[self fallbackForFailedSearch:keyword reason:problem];' in main,
 "Search signing failure invokes fallback": '[self fallbackForFailedSearch:keyword reason:issue];' in main,
 "Live list tests multiple endpoints": 'https://live.douyin.com/webcast/feed/' in main and 'https://webcast.amemv.com/webcast/ranklist/hot/' in main,
 "Live list parses nested rooms": 'for(NSString *key in @[@"ranks",@"data",@"room_list",@"rooms",@"feed",@"list"])' in main,
 "Live room source must provide playable HLS": 'NSString *hls=DLLiveHLS(decoded,0);' in main,
 "Live list accepts direct HLS streams": 'NSString *hls=DLLiveHLS(room,0);' in main,
 "Live stream retries alternate sources": 'stage>=3' in main and 'checkLiveStageFallback:' in main,
 "Live fallback allows direct input": 'alertControllerWithTitle:@"进入直播间"' in main and 'DLLiveID' in main,
 "QR primary is captured official login": 'https://login.douyin.com/passport/web/get_qrcode/' in qr,
 "QR has bounded parameter variants": 'if(self.provider==0){self.provider=1;' in qr and 'account_sdk_source=web' in qr,
 "QR never generates fake code": 'if(!token.length||(!qrImage' in qr,
 "QR accepts genuine image payload": 'initWithBase64EncodedString:encoded' in qr and 'if(qrImage){self.qr.image=qrImage;}' in qr,
 "QR returns server error details": 'error_code' in qr and 'qrFailureReason' in qr,
 "QR avoids HTML SSO fallback": 'sso.douyin.com/get_qrcode/' not in qr,
 "QR failed request does not affect guest mode": '游客视频不受影响' in qr
}
for key,ok in checks.items():
    print(("PASS" if ok else "FAIL")+": "+key)
if not all(checks.values()):raise SystemExit(1)
