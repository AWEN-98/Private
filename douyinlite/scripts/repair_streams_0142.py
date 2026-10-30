#!/usr/bin/env python3
"""Apply bounded compatibility repairs to the iOS 8 source before build."""
from pathlib import Path

p=Path(__file__).resolve().parents[1]/"main.m"
s=p.read_text(encoding="utf-8")
def replace(old,new):
    global s
    if old not in s:
        raise SystemExit("Expected source block missing: "+old[:95])
    s=s.replace(old,new,1)

replace(
'    if(next<0 || next>=clips.count){\n        if(self.demoMode && clips.count){',
'    if(next<0 || next>=clips.count){\n'
'        if(next>=clips.count && self.onlineMode && !self.onlineLoading){\n'
'            self.douyinRetryAfter=nil;self.douyinEnd=NO;\n'
'            [self loadOnlineFeed:NO];\n'
'            self.message.text=@"正在加载下一页视频…";\n'
'            return;\n'
'        }\n'
'        if(self.demoMode && clips.count){'
)
replace(
'    self.message.text=@"正在获取直播间，连接失败会自动尝试其他接口…";\n'
'    [self loadLiveListAtStage:0 generation:generation];',
'    self.message.text=@"正在获取直播间，连接失败会自动尝试其他接口…";\n'
'    [self performSelector:@selector(checkLiveLoadingTimeout:) withObject:@(generation) afterDelay:24];\n'
'    [self loadLiveListAtStage:0 generation:generation];'
)
replace(
'- (void)loadLiveListAtStage:(NSInteger)stage generation:(NSUInteger)generation {',
'- (void)checkLiveLoadingTimeout:(NSNumber *)generation {\n'
'    if(generation.unsignedIntegerValue!=self.liveGeneration || !self.liveMode || self.liveVideos.count)return;\n'
'    self.liveLoading=NO;\n'
'    self.message.text=@"直播连接超时。请重试或输入直播间地址。";\n'
'}\n'
'- (void)loadLiveListAtStage:(NSInteger)stage generation:(NSUInteger)generation {'
)
replace(
'cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];\n'
'    [req setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];\n'
'    [req setValue:@"https://live.douyin.com/"',
'cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:6];\n'
'    [req setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];\n'
'    [req setValue:@"https://live.douyin.com/"'
)
p.write_text(s,encoding="utf-8")
print("Build-time video pagination and live timeout fixes applied.")
