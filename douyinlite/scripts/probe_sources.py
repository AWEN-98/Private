#!/usr/bin/env python3
"""Non-fatal connectivity check for DouyinLite's public PeerTube feed."""
import json
import ssl
import urllib.request

hosts = ("https://diode.zone", "https://tilvids.com", "https://peertube.tv")
for host in hosts:
    endpoint = f"{host}/api/v1/videos?start=0&count=35&sort=-publishedAt&nsfw=false&isLocal=true"
    try:
        req = urllib.request.Request(endpoint, headers={"Accept": "application/json", "User-Agent": "DouyinLite/0.5 source-check"})
        with urllib.request.urlopen(req, timeout=12) as response:
            listing = json.load(response)
        videos = [v for v in listing.get("data", []) if 3 <= v.get("duration", 0) <= 900 and not v.get("isLive")]
        print(f"HOST {host}: total={len(listing.get('data', []))}, short_candidates={len(videos)}")
        count = 0
        for v in videos[:8]:
            uid = v.get("uuid") or v.get("id")
            with urllib.request.urlopen(f"{host}/api/v1/videos/{uid}", timeout=10) as resp:
                detail = json.load(resp)
            files = detail.get("files") or []
            mp4 = [f.get("fileUrl", "") for f in files if f.get("fileUrl", "").split("?")[0].lower().endswith(".mp4")]
            hls = [p.get("playlistUrl", "") for p in detail.get("streamingPlaylists", []) if p.get("playlistUrl")]
            if mp4 or hls:
                count += 1
                print(f"  PLAYABLE {uid} {detail.get('name', '')[:45]} mp4={len(mp4)} hls={len(hls)}")
        print(f"PLAYABLE_RESULTS {host} {count}")
    except Exception as exc:
        print(f"HOST {host}: ERROR {type(exc).__name__} {exc}")
