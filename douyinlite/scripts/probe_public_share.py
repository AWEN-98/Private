#!/usr/bin/env python3
"""Probe a documented public Douyin share-video URL without logging cookies or media URLs.

The input video ID appears in a public English README example. Passing requires
an actual parsed playable URL in the response; HTTP 200 alone is insufficient.
Cloud IPs may be challenged and should be reported as unverified.
"""
import http.cookiejar
import json
import re
import time
import urllib.error
import urllib.request
from pathlib import Path

TEST_ID="6914948781100338440"
URL="https://www.iesdouyin.com/share/video/"+TEST_ID+"/"
AGENT="Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
cookies=http.cookiejar.CookieJar()
opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))
report={"utc":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),"source":"public README.en sample","tests":[],"verified_playable_address":False}
for attempt in range(2):
    result={"attempt":attempt+1,"http_status":None,"mime":"","body_bytes":0,"has_ttwid":False,"has_ssr_marker":False,"has_play_addr":False,"playable_url_found":False,"error":""}
    try:
        req=urllib.request.Request(URL,headers={"User-Agent":AGENT,"Accept":"text/html,application/xhtml+xml","Referer":"https://www.douyin.com/"})
        with opener.open(req,timeout=16) as response:
            body=response.read(2400000)
            result["http_status"]=response.status
            result["mime"]=response.headers.get("content-type","").split(";")[0]
        text=body.decode("utf-8","replace")
        result["body_bytes"]=len(body)
        result["has_ssr_marker"]=any(x in text for x in ("_ROUTER_DATA","RENDER_DATA","videoInfoRes"))
        result["has_play_addr"]='"play_addr"' in text
        chunks=re.findall(r'["\\\']play_addr["\\\']\\s*:\\s*\\{[^}]{0,6000}\\}',text,re.I)
        for chunk in chunks:
            candidates=re.findall(r'https?[^"\\\'\\s<>]{8,2200}',chunk,re.I)
            if any("play" in u and (".douyin" in u or ".byte" in u or ".snssdk" in u or ".amemv" in u) for u in candidates):
                result["playable_url_found"]=True
                report["verified_playable_address"]=True
                break
    except urllib.error.HTTPError as exc:
        result["http_status"]=exc.code
        result["error"]="HTTP error"
    except Exception as exc:
        result["error"]=type(exc).__name__
    result["has_ttwid"]=any(c.name=="ttwid" for c in cookies)
    report["tests"].append(result)
    if result["playable_url_found"]:break
Path("diagnostics").mkdir(exist_ok=True)
Path("diagnostics/douyin-public-share-probe.json").write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False))
raise SystemExit(0 if report["verified_playable_address"] else 2)
