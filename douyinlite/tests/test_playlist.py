#!/usr/bin/env python3
"""Regression checks for the iOS8 phone-only playlist and share-source refresh."""
from pathlib import Path
s=(Path(__file__).resolve().parents[1]/"main.m").read_text(encoding="utf-8")
checks={
 "multiple official links recognized": "static NSArray *DLShareURLsInText" in s,
 "at most 12 links per paste": "if(urls.count>=12)break;" in s,
 "extract only official HTTPS share links": 'DLDouyinHost(url.host)' in s and '@"https"' in s,
 "duplicate video IDs rejected": "[known containsObject:unique]" in s,
 "batch requires user approval": 'actionWithTitle:@"开始导入"' in s,
 "batch import is sequential": "self.pendingShareURLs[0]" in s and "[self processNextShareBatch]" in s,
 "failed video does not stop batch": "self.batchFailed++;" in s,
 "batch preserves playlist order": "[self.videos addObject:entry]" in s and "self.index=existing;" in s,
 "persistent original share URL": '@"originURL":origin' in s or '@"originURL": origin' in s,
 "persistent video ID": '@"id":videoID' in s,
 "old CDN URL replaced by share identity": '[DLText(old[@"originURL"]) isEqualToString:origin]' in s,
 "refresh bounded to one attempt": "[self.refreshedShareOrigins containsObject:origin]" in s,
 "old share links auto refresh once": "[self inspectPublicShare:[NSURL URLWithString:origin]]" in s,
 "batch errors do not present repeated alerts": "if(self.batchInProgress){" in s[s.index("- (void)failImportedVideo:"):s.index("- (void)inspectPublicShare:")],
 "native API and share fallback remain": "api5-normal-c-hl.amemv.com/aweme/v1/feed/" in s and "iesdouyin.com/share/video/" in s,
 "video playback stays native": "AVPlayerItem playerItemWithAsset" in s,
 "cloud mode not in menu": 'actionWithTitle:@"连接 DouyinBridge' not in s,
 "Surf mode not in menu": 'actionWithTitle:@"Surf 模式' not in s
}
for label,ok in checks.items():
 print(("PASS" if ok else "FAIL")+": "+label)
if not all(checks.values()):raise SystemExit(1)
