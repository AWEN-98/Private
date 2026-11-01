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
from urllib.parse import urlparse
from pathlib import Path

TEST_ID="6914948781100338440"
URL="https://www.iesdouyin.com/share/video/"+TEST_ID+"/"
AGENT="Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
cookies=http.cookiejar.CookieJar()
opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))
report={"utc":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),"source":"public README.en sample","tests":[],"verified_playable_address":False,"verified_media_response":False}
for attempt in range(2):
    result={"attempt":attempt+1,"http_status":None,"mime":"","body_bytes":0,"has_ttwid":False,"has_ssr_marker":False,"has_play_addr":False,"playable_url_found":False,"media_range_status":None,"media_mime":"","media_header_ok":False,"error":""}
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
        chunks=re.findall(r"""["']play_addr["']\s*:\s*\{[^}]{0,6000}\}""",text,re.I)
        for chunk in chunks:
            candidates=re.findall(r"""https?[^"'\s<>]{8,2200}""",chunk,re.I)
            result["candidate_count"]=len(candidates)
            for original in candidates:
                candidate=original
                for _ in range(3):
                    candidate=candidate.replace(chr(92)+"/","/").replace(chr(92)+"u002F","/").replace(chr(92)+"u0026","&")
                # Do not expose signed URLs or query tokens in diagnostics.
                parsed=urlparse(candidate)
                if "sample_host" not in result:
                    result["sample_host"]=(parsed.hostname or "")[:100]
                    result["sample_path_type"]="play" if "/play" in parsed.path else "other"
                host=(parsed.hostname or "").lower()
                trusted=any(host==domain or host.endswith("."+domain) for domain in
                            ("douyinvod.com","douyin.com","ibytedtos.com","bytecdn.cn","amemv.com","snssdk.com"))
                if parsed.scheme!="https" or not trusted or "/play" not in parsed.path:
                    continue
                result["playable_url_found"]=True
                report["verified_playable_address"]=True
                try:
                    media_request=urllib.request.Request(candidate,headers={
                        "User-Agent":AGENT,"Range":"bytes=0-4095","Referer":"https://www.iesdouyin.com/"})
                    with opener.open(media_request,timeout=16) as media:
                        result["media_range_status"]=media.status
                        result["media_mime"]=media.headers.get("content-type","").split(";")[0]
                        first=media.read(4096)
                    result["media_header_ok"]=(
                        b"ftyp" in first[:64] or first.startswith(b"#EXTM3U") or
                        result["media_mime"] in ("video/mp4","video/quicktime","application/vnd.apple.mpegurl"))
                except urllib.error.HTTPError as media_error:
                    result["media_range_status"]=media_error.code
                except Exception as media_error:
                    result["media_error"]=type(media_error).__name__
                break
            if result["playable_url_found"]:break
    except urllib.error.HTTPError as exc:
        result["http_status"]=exc.code
        result["error"]="HTTP error"
    except Exception as exc:
        result["error"]=type(exc).__name__
    result["has_ttwid"]=any(c.name=="ttwid" for c in cookies)
    if result["media_header_ok"]:report["verified_media_response"]=True
    report["tests"].append(result)
    if result["playable_url_found"]:break
Path("diagnostics").mkdir(exist_ok=True)
Path("diagnostics/douyin-public-share-probe.json").write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False))
raise SystemExit(0 if report["verified_playable_address"] else 2)
