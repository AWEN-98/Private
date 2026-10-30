#!/usr/bin/env python3
"""Static safety/compatibility checks for the standalone iOS8 Douyin client."""
from pathlib import Path
src=(Path(__file__).resolve().parents[1]/"main.m").read_text(encoding="utf-8")
entry=src[src.index("- (void)inspectPublicShare:"):src.index("- (void)resolveShareWithBridge:")]
menu=src[src.index("- (void)openMenu {"):src.index("    [menu addAction:[UIAlertAction actionWithTitle:@\"公开样片（上下滑动测试）\"")]
checks={
    "official video input validated": "DLDouyinHost(url.host)" in entry,
    "only user-supplied ID for mobile lookup": "DLShareVideoID(url)" in entry,
    "two official mobile API hosts": all(v in entry for v in (
        "api5-normal-c-hl.amemv.com/aweme/v1/feed/",
        "aweme.snssdk.com/aweme/v1/feed/")),
    "mobile result ID must match": "[identifier isEqualToString:videoID]" in entry,
    "H264 selection reused": "DLPublicPlaybackURL(matched)" in entry,
    "www mobile share fallback": "https://www.douyin.com/share/video/" in entry,
    "iesdouyin share fallback": "https://www.iesdouyin.com/share/video/" in entry,
    "bounded response buffers": "data.length<2500000" in entry and "data.length<3000000" in entry,
    "no automatic server fallback for share": "resolveShareWithBridge" not in entry,
    "no Surf from native menu": "Surf 模式" not in menu,
    "no cloud setup from native menu": "连接 DouyinBridge" not in menu,
    "Chinese phone-only menu item": "纯手机 · 粘贴抖音视频链接" in menu,
    "online feed stays native only": "[self loadDouyinAccountFeed:reset];" in src[src.index("- (void)loadOnlineFeed:(BOOL)reset {"):src.index("- (void)loadOnlineFeed:(BOOL)reset preserveHost:")],
}
for label,ok in checks.items():
    print(("PASS" if ok else "FAIL")+": "+label)
if not all(checks.values()):
    raise SystemExit(1)
