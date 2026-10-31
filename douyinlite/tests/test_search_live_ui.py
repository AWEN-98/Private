#!/usr/bin/env python3
"""Static regression checks for native iOS8 Douyin navigation, live, and search."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
s=(root/"main.m").read_text(encoding="utf-8")
session=(root/"DLAccountSession.m").read_text(encoding="utf-8")
header=(root/"DLAccountSession.h").read_text(encoding="utf-8")
checks={
 "Four Chinese native tabs": 'NSArray *names=@[@"首页",@"直播",@"收藏",@"我的"]' in s,
 "Compact bottom height": "const CGFloat barHeight=38;" in s,
 "Automatic bottom hiding": "hideBottomAfterDelay" in s and "self.bottomHidden=YES" in s,
 "Tap restores navigation": "if(self.bottomHidden){[self showBottomTemporarily];return;}" in s,
 "Fullscreen is truly immersive": "prefersStatusBarHidden" in s and "AVLayerVideoGravityResizeAspectFill" in s,
 "Tap exits fullscreen": "if(self.fullscreenMode){[self toggleFullscreen];return;}" in s,
 "Native linear search icon": 'DLStyleIcon(self.searchButton,@"search"' in s,
 "Category row has five genuine filters": 'NSArray *categories=@[@"推荐",@"热门",@"游戏",@"音乐",@"生活"]' in s,
 "Category uses real search endpoint": "[self searchVideos:categories[idx] reset:YES]" in s,
 "Search is official query": "/aweme/v1/web/general/search/single/" in session,
 "Search uses current browser query contract": "from_group_id=7378810571505847586" in session and "search_id=%@" in session and "count=15" in session,
 "Search keeps URL encoded keywords": "DLFormEncode(word)" in session,
 "Search does not append obsolete a_bogus": "&a_bogus=" not in session[session.index("- (NSMutableURLRequest *)searchRequestForKeyword:"):session.index("- (void)requestJSON:")],
 "Web requests include Argus marker": 'forHTTPHeaderField:@"x-tt-argus"' in session,
 "Web requests forward UIFID": 'forHTTPHeaderField:@"uifid"' in session,
 "Anonymous requests bootstrap UIFID cookie": 'NSHTTPCookieName:@"UIFID"' in session and 'NSHTTPCookieStorage.sharedHTTPCookieStorage setCookie:cookie' in session,
 "Search continuation token is declared": "searchID:(NSString *)searchID" in header,
 "Search API declared": "searchRequestForKeyword:" in header,
 "Only real video URLs in results": "NSString *link=DLPublicPlaybackURL(entry);" in s,
 "Bounded results": "if(results.count>=80)break;" in s,
 "Stop search pagination after empty": "if(!items.count||results.count==previousCount)self.searchEnd=YES;" in s,
 "Live ranking contains official route": "https://webcast.amemv.com/webcast/ranklist/hot/" in s,
 "Live room official scene endpoint": "https://live.douyin.com/webcast/room/info_by_scene/" in s,
 "Live room reflow endpoint": "https://webcast.amemv.com/webcast/room/reflow/info/" in s,
 "Live stream must have HLS address": 'rangeOfString:@".m3u8"' in s,
 "Live room parser reads HLS from HTML responses": "DLLiveHLSFromData(data)" in s and "hls_pull_url" in s[s.index("static NSString *DLLiveHLSFromData"):s.index("static NSString *DLLiveID")],
 "Live room entered with user link": 'alertControllerWithTitle:@"进入直播间"' in s and "DLLiveID" in s,
 "Playback remains on device": "AVPlayerItem playerItemWithAsset" in s,
 "Favorited web video persists": '[self.videos insertObject:clip atIndex:0]' in s,
 "No fake comments control": "action:@selector(openComments)" not in s,
 "Old remote Surf not in visible UI": "action:@selector(openSurfDouyin)" not in s,
}
for label,valid in checks.items():print(("PASS" if valid else "FAIL")+": "+label)
if not all(checks.values()):raise SystemExit(1)
