#!/usr/bin/env python3
"""Regression checks for refresh-driven, deduplicated Douyin-style feed."""
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
move=block("- (void)moveFeedBy:(NSInteger)delta {", "- (void)verticalPan:(UIPanGestureRecognizer *)gesture {")
hot=block("- (void)loadAnonymousHotVideos:", "- (void)loadDouyinAccountFeedWeb:")

checks={
    "mobile feed uses server max_cursor": "max_cursor=%lld" in mobile,
    "mobile feed uses server min_cursor": "min_cursor=%lld" in mobile,
    "response max_cursor is retained": 'body[@"max_cursor"]?:json[@"max_cursor"]' in mobile,
    "response min_cursor is retained": 'body[@"min_cursor"]?:json[@"min_cursor"]' in mobile,
    "has_more controls mobile end state": "self.mobileFeedEnd=YES" in mobile,
    "small mobile batches continue to next endpoint": "endpointIndex+1<(NSInteger)hosts.count" in mobile,
    "small mobile batches fall through to signed web feed": "[self loadDouyinAccountFeedWeb:YES]" in mobile,
    "mobile and web sources deduplicate IDs": "[seen containsObject:identity]" in mobile and "[known containsObject:identity]" in web,
    "recently viewed IDs persist across refresh": '"dl_recent_online_ids_v1"' in s,
    "mobile feed excludes recently viewed IDs": "for(NSString *identity in self.recentOnlineIDs)" in mobile,
    "web feed receives recent IDs for fresh recommendations": "self.recentOnlineIDs reverseObjectEnumerator" in web,
    "hot fallback excludes recent IDs": "for(NSString *identity in self.recentOnlineIDs)" in hot,
    "home tab always requests a fresh feed": "[self loadOnlineFeed:YES]" in tabs and "self.index=0;" in tabs,
    "pull down at first item refreshes feed": "[self loadOnlineFeed:YES]" in move,
    "refresh clears mobile cursor for a new recommendation request": "self.mobileFeedMaxCursor=0;self.mobileFeedMinCursor=-1;" in loader,
    "refresh no longer restores an old feed index": "restoreOnlinePositionAfterRefresh" not in s and "onlineIndex" not in s,
}
for name,ok in checks.items():
    print(("PASS" if ok else "FAIL")+": "+name)
if not all(checks.values()):
    raise SystemExit(1)
