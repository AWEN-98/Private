#!/usr/bin/env python3
"""Regression contracts for the public-share-first native phone pipeline."""
from pathlib import Path
s=(Path(__file__).resolve().parents[1]/"main.m").read_text(encoding="utf-8")
start=s[s.index("- (void)inspectPublicShare:"):s.index("- (void)requestMobileVideoID:")]
mobile=s[s.index("- (void)requestMobileVideoID:"):s.index("- (void)requestPublicShare:")]
share=s[s.index("- (void)requestPublicShare:(NSURL *)url original:"):s.index("- (void)resolveShareWithBridge:")]
checks={
 "public SSR first for known video IDs": 'https://www.iesdouyin.com/share/video/%@/' in start,
 "short official links resolve on-device": "stage:-1 videoID:nil" in start,
 "mobile endpoints retained as fallback": "api5-normal-c-hl.amemv.com" in mobile and "aweme.snssdk.com" in mobile,
 "mobile retries cannot loop back to SSR": "requestPublicShare:" not in mobile,
 "video ID checked before ingest": "[identifier isEqualToString:videoID]" in mobile,
 "at most one ttwid retry": "retryWithCookie:(BOOL)retry" in share and "if(!retry && stage>=0" in share,
 "visitor retry requires HTTP 200": "http.statusCode==200" in share,
 "visitor retry requires a newly established cookie": "!hadVisitorCookie && acquiredVisitorCookie" in share,
 "public SSR uses real share page": "requestPublicShare:[NSURL URLWithString:shareURL]" in share,
 "public SSR and APIs finally error": "failImportedVideo:" in mobile,
 "public video URL parsed from real markup": "DLDirectSharePlaybackURL(html)" in s and 'play_addr' in s,
 "no client-side fabricated recommendations": "if(++inserted>=12)break;" in s,
}
for k,v in checks.items():print(("PASS" if v else "FAIL")+": "+k)
if not all(checks.values()):raise SystemExit(1)
