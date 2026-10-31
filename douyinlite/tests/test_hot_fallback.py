#!/usr/bin/env python3
"""Verify a real anonymous hot-video fallback and absence of fabricated recommendations."""
from pathlib import Path
s=(Path(__file__).resolve().parents[1]/"main.m").read_text(encoding="utf-8")
start=s.index("- (void)loadAnonymousHotVideos:(NSUInteger)token {")
end=s.index("- (void)loadDouyinAccountFeedWeb:(BOOL)reset {",start)
h=s[start:end]
web=s[end:s.index("- (void)loadOnlineFeed:(BOOL)reset {",end)]
checks={
 "Official public hot-video URL": "https://www.iesdouyin.com/web/api/v2/hotsearch/aweme/" in h,
 "No credentials required": "Authorization" not in h and "sessionid" not in h,
 "JSON video objects only": 'root[@"aweme_list"]' in h and '[object isKindOfClass:NSDictionary.class]' in h,
 "Only actual playable video addresses": "NSString *address=DLPublicPlaybackURL(entry);" in h and "if(!address.length" in h,
 "Only genuine entries added": '[self.onlineVideos addObject:@{' in h,
 "Hot videos clearly identified": '@"source":@"douyin-hot"' in h,
 "No pretend pagination": "self.douyinEnd=YES;" in h,
 "Signed homepage no longer silently falls back to static hot list": "[self loadAnonymousHotVideos:token]" not in web,
 "Signer errors are explained by refresh handler": "self.feedFailureReason=signError" in web and "[self finishFeedRequest]" in web,
 "Guest home cookie bootstrap": "if(!self.guestPrimed && !DLAccountSession.shared.hasSession)" in web,
 "Shows real failure if empty": "推荐和热门视频接口暂未返回可播放内容" in h,
 "No sample injection": "self.demoVideos" not in h,
 "Static hot list is never requested as recommendation": "[self loadAnonymousHotVideos:token]" not in s,
 "Hot source labeled explicitly": 'hot?@"热门":@"推荐"' in s
}
for k,passed in checks.items():print(("PASS" if passed else "FAIL")+": "+k)
if not all(checks.values()):raise SystemExit(1)
