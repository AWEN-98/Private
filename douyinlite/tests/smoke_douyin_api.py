#!/usr/bin/env python3
"""Low-volume, read-only probes of the public Douyin feed/search/live endpoints.

This is diagnostic only: GitHub-hosted runner IPs may be challenged independently
of an iPhone session. Results are printed for review and never block packaging.
"""
import base64
import hashlib
import http.cookiejar
import json
import os
import random
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
MOBILE_UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) "
             "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 "
             "Mobile/15E148 Safari/604.1")
COOKIE_JAR = http.cookiejar.CookieJar()
OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(COOKIE_JAR))


def qencode(params):
    return urllib.parse.urlencode(params, quote_via=urllib.parse.quote, safe="*-._")


def request(url, headers=None, body=None, timeout=18):
    h = {"User-Agent": UA, "Accept": "application/json, text/plain, */*"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, data=body, headers=h)
    try:
        with OPENER.open(req, timeout=timeout) as res:
            return res.status, res.headers.get("Content-Type", ""), res.read(4_000_000)
    except urllib.error.HTTPError as exc:
        return exc.code, exc.headers.get("Content-Type", ""), exc.read(4000)
    except Exception as exc:
        return 0, type(exc).__name__, str(exc).encode("utf-8", "replace")[:1000]


def parse_json(data):
    try:
        return json.loads(data.decode("utf-8", "replace"))
    except Exception:
        return None


def find_video_count(node):
    if isinstance(node, list):
        return sum(find_video_count(x) for x in node)
    if not isinstance(node, dict):
        return 0
    if isinstance(node.get("aweme_info"), dict):
        return 1
    mix = node.get("aweme_mix_info")
    if isinstance(mix, dict) and isinstance(mix.get("mix_items"), list):
        return len(mix["mix_items"])
    total = 0
    for key in ("aweme_list", "item_list", "list", "search_result", "data"):
        value = node.get(key)
        if isinstance(value, (dict, list)):
            total += find_video_count(value)
    return total


def cookies():
    return {c.name: c.value for c in COOKIE_JAR}


def smoke_search():
    c = cookies()
    webid = c.get("webid") or c.get("webid_v2") or str(random.randint(1_000_000_000_000_000_000, 9_000_000_000_000_000_000))
    params = [
        ("search_channel", "aweme_general"), ("enable_history", "1"),
        ("keyword", "游戏"), ("search_source", "tab_search"),
        ("query_correct_type", "1"), ("is_filter_search", "0"),
        ("from_group_id", "7378810571505847586"), ("offset", "0"),
        ("count", "15"), ("need_filter_settings", "1"), ("list_type", "multi"),
        ("search_id", ""), ("device_platform", "webapp"), ("aid", "6383"),
        ("channel", "channel_pc_web"), ("version_code", "190600"),
        ("version_name", "19.6.0"), ("update_version_code", "170400"),
        ("pc_client_type", "1"), ("cookie_enabled", "true"),
        ("browser_language", "zh-CN"), ("browser_platform", "Win32"),
        ("browser_name", "Chrome"), ("browser_version", "131.0.0.0"),
        ("browser_online", "true"), ("engine_name", "Blink"),
        ("engine_version", "131.0.0.0"), ("os_name", "Windows"),
        ("os_version", "10"), ("cpu_core_num", "8"), ("device_memory", "8"),
        ("platform", "PC"), ("screen_width", "1920"), ("screen_height", "1080"),
        ("effective_type", "4g"), ("round_trip_time", "50"), ("webid", webid),
    ]
    if c.get("msToken"):
        params.append(("msToken", c["msToken"]))
    headers = {"Referer": "https://www.douyin.com/search/%E6%B8%B8%E6%88%8F",
               "x-tt-argus": "1"}
    if c.get("UIFID") or c.get("UIFID_TEMP"):
        headers["uifid"] = c.get("UIFID") or c.get("UIFID_TEMP")
    status, mime, data = request(
        "https://www.douyin.com/aweme/v1/web/general/search/single/?" + qencode(params),
        headers=headers)
    root = parse_json(data)
    count = find_video_count(root.get("data", root)) if isinstance(root, dict) else 0
    print("SEARCH status=%s mime=%s bytes=%s video_objects=%s" % (status, mime, len(data), count))


def smoke_feed():
    c = cookies()
    webid = c.get("webid") or c.get("webid_v2") or str(random.randint(1_000_000_000_000_000_000, 9_000_000_000_000_000_000))
    params = [
        ("device_platform", "webapp"), ("aid", "6383"),
        ("channel", "channel_pc_web"), ("module_id", "3003101"),
        ("count", "20"), ("refresh_index", "1"), ("refer_type", "10"),
        ("pull_type", "0"), ("use_lite_type", "2"),
        ("version_code", "190600"), ("version_name", "19.6.0"),
        ("update_version_code", "170400"), ("pc_client_type", "1"),
        ("cookie_enabled", "true"), ("screen_width", "1920"),
        ("screen_height", "1080"), ("browser_language", "zh-CN"),
        ("browser_platform", "Win32"), ("browser_name", "Chrome"),
        ("browser_version", "131.0.0.0"), ("browser_online", "true"),
        ("engine_name", "Blink"), ("engine_version", "131.0.0.0"),
        ("os_name", "Windows"), ("os_version", "10"),
        ("cpu_core_num", "8"), ("device_memory", "8"), ("platform", "PC"),
        ("downlink", "10"), ("effective_type", "4g"), ("round_trip_time", "50"),
        ("webid", webid),
    ]
    if c.get("msToken"):
        params.append(("msToken", c["msToken"]))
    if c.get("s_v_web_id"):
        params.extend([("verifyFp", c["s_v_web_id"]), ("fp", c["s_v_web_id"])])
    body = "encoded_pre_item_ids="
    query = qencode(params)
    now = int(time.time() * 1000)
    js = ("const fs=require('fs'),vm=require('vm');const c=vm.createContext({});"
          "vm.runInContext(fs.readFileSync(process.argv[1],'utf8'),c);"
          "process.stdout.write(c.DLSigner.sign(process.argv[2],process.argv[3],process.argv[4],Number(process.argv[5])));")
    try:
        signature = subprocess.check_output(
            ["node", "-e", js, str(ROOT / "Resources" / "DLSigner.js"), query, body, UA, str(now)],
            text=True, timeout=15).strip()
    except Exception as exc:
        print("FEED signer_error=%s" % type(exc).__name__)
        return
    query += "&a_bogus=" + urllib.parse.quote(signature, safe="*-._")
    headers = {"Referer": "https://www.douyin.com/", "Origin": "https://www.douyin.com",
               "Content-Type": "application/x-www-form-urlencoded", "x-tt-argus": "1"}
    uifid = c.get("UIFID") or c.get("UIFID_TEMP")
    if uifid:
        headers["uifid"] = uifid
        stamp = str(int(time.time()))
        query += "&uifid=" + urllib.parse.quote(uifid, safe="*-._") + "&timestamp=" + stamp
        digest = hashlib.md5(("%s_%s_A96D855A08C0A9707F8BEF0D9A527E4E_%s" %
                              (uifid, stamp, query)).encode()).hexdigest()
        query += "&x-secsdk-web-signature=" + digest
        headers["x-secsdk-web-signature"] = digest
        headers["x-secsdk-web-expire"] = stamp
    status, mime, data = request("https://www.douyin.com/aweme/v2/web/module/feed/?" + query,
                                 headers=headers, body=body.encode())
    root = parse_json(data)
    count = find_video_count(root.get("data", root)) if isinstance(root, dict) else 0
    print("FEED status=%s mime=%s bytes=%s video_objects=%s" % (status, mime, len(data), count))


def find_live_rooms(node):
    found = []
    if isinstance(node, list):
        for x in node:
            found.extend(find_live_rooms(x))
    elif isinstance(node, dict):
        room = node.get("room") if isinstance(node.get("room"), dict) else node
        rid = room.get("id_str") or room.get("id") or room.get("room_id")
        status = str(room.get("status", "2"))
        if rid and status == "2":
            found.append(str(rid))
        for value in node.values():
            if isinstance(value, (dict, list)):
                found.extend(find_live_rooms(value))
    return list(dict.fromkeys(found))


def smoke_live():
    url = ("https://webcast.amemv.com/webcast/ranklist/hot/"
           "?aid=1128&device_platform=android&version_name=13.2.0&version_code=130200")
    status, mime, data = request(url, headers={"User-Agent": "okhttp3",
                                               "Referer": "https://live.douyin.com/"})
    root = parse_json(data)
    rooms = find_live_rooms(root)[:3] if root else []
    playable = False
    last = None
    for rid in rooms:
        last = request("https://webcast.amemv.com/webcast/reflow/" + rid,
                       headers={"User-Agent": MOBILE_UA,
                                "Referer": "https://live.douyin.com/"}, timeout=12)
        text = last[2].decode("utf-8", "replace")
        text = text.replace(r"\/", "/").replace(r"\u0026", "&").replace("&amp;", "&")
        match = re.search(r'"hls_pull_url"\s*:\s*"([^"]+\.m3u8[^"]*)"', text)
        if match:
            playable = True
            break
    print("LIVE_LIST status=%s mime=%s bytes=%s active_rooms=%s" %
          (status, mime, len(data), len(rooms)))
    if rooms:
        print("LIVE_ROOM status=%s mime=%s bytes=%s hls=%s" %
              (last[0], last[1], len(last[2]), playable))
    else:
        print("LIVE_ROOM skipped=no_active_room_or_list_blocked")


def main():
    status, mime, data = request("https://www.douyin.com/",
                                 headers={"Accept": "text/html,application/xhtml+xml"})
    print("HOME status=%s mime=%s bytes=%s" % (status, mime, len(data)))
    smoke_search()
    smoke_feed()
    smoke_live()
    print("SMOKE_COMPLETE (diagnostic only; runner IP may be challenged)")


if __name__ == "__main__":
    main()
