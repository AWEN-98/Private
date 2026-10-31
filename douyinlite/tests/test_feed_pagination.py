#!/usr/bin/env python3
"""Regression checks for unique, cursor-paginated home feed and resume position."""
from pathlib import Path
s=(Path(__file__).resolve().parents[1]/"main.m").read_text(encoding="utf-8")

def block(start, end):
    a=s.index(start)
    b=s.index(end,a)
    return s[a:b]

mobile=block("- (void)requestMobileFeed:(NSInteger)endpointIndex", "// Best-effort public trending-video fallback")
loader=block("- (void)loadDouyinAccountFeed:(BOOL)reset {", "- (void)requestMobileFeed:(NSInteger)endpointIndex")
web=block("- (void)loadDouyinAccountFeedWeb:(BOOL)reset {", "- (void)loadOnlineFeed:(BOOL)reset {")
tabs=block("- (void)tabPressed:(UIButton *)button {", "- (BOOL)gestureRecognizer:")
save=block("- (void)savePlaybackIndex {", "- (void)setLoading:")

checks={
    "mobile feed uses server max_cursor": "max_cursor=%lld" in mobile,
    "mobile feed uses server min_cursor": "min_cursor=%lld" in mobile,
    "response max_cursor is retained": 'body[@"max_cursor"]?:json[@"max_cursor"]' in mobile,
    "response min_cursor is retained": 'body[@"min_cursor"]?:json[@"min_cursor"]' in mobile,
    "has_more controls mobile end state": "self.mobileFeedEnd=YES" in mobile,
    "small first batch continues to second endpoint": "endpointIndex+1<(NSInteger)hosts.count" in mobile,
    "small mobile batches fall through to signed web feed": "[self loadDouyinAccountFeedWeb:YES]" in mobile,
    "mobile pagination does not fake-increment web page": "self.onlineOffset++" not in mobile,
    "IDs deduplicate merged source batches": "[seen containsObject:identity]" in mobile,
    "web fallback preserves already collected mobile items": "if(!self.onlineVideos.count){self.index=0;self.onlineError=nil;}" in web,
    "home last video ID persists": '"dl_online_last_id_v1"' in s,
    "home index persists": '"dl_online_index_v1"' in save,
    "home tab restores saved index": "MIN(MAX(0,self.onlineIndex)" in tabs,
    "home tab no longer resets to zero": 'self.category=@"推荐";self.favoritesOnly=NO;self.historyOnly=NO;self.index=0;' not in tabs,
    "startup resume searches last played identity": "restoreOnlinePositionAfterRefresh" in s and "isEqualToString:last" in s,
}
for name,ok in checks.items():
    print(("PASS" if ok else "FAIL")+": "+name)
if not all(checks.values()):
    raise SystemExit(1)
