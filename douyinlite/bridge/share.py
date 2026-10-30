"""Public Douyin share page parser, used only for user-submitted links.

All network I/O is performed by the official-site browser context in app.py.
This module only interprets publicly returned page content.
"""
import json
import re
from urllib.parse import parse_qs, urlparse

MOBILE_UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
             "AppleWebKit/605.1.15 (KHTML, like Gecko) "
             "Version/17.5 Mobile/15E148 Safari/604.1")
MAX_HTML_SIZE = 2_500_000


def official_link(url):
    if not isinstance(url, str) or len(url) > 2048:
        return False
    try:
        p = urlparse(url)
        host = (p.hostname or "").lower()
        return p.scheme == "https" and (
            host == "douyin.com" or host.endswith(".douyin.com") or
            host == "iesdouyin.com" or host.endswith(".iesdouyin.com")
        ) and not p.username and not p.password and p.port in (None, 443)
    except ValueError:
        return False


def video_id(url):
    if not official_link(url):
        return None
    parsed = urlparse(url)
    m = re.search(r"/(?:share/)?video/([0-9]{6,25})(?:/|$)", parsed.path, re.I)
    if m:
        return m.group(1)
    qs = parse_qs(parsed.query)
    for key in ("modal_id", "aweme_id", "item_ids"):
        value = (qs.get(key) or [""])[0]
        if re.fullmatch(r"[0-9]{6,25}", value):
            return value
    return None


def mobile_share_url(id_string):
    if not isinstance(id_string, str) or not re.fullmatch(r"[0-9]{6,25}", id_string):
        raise ValueError("Invalid video ID")
    return "https://www.iesdouyin.com/share/video/" + id_string + "/"


def json_after_marker(html, marker):
    index = html.find(marker)
    if index == -1:
        return None
    index = html.find("{", index + len(marker))
    if index == -1:
        return None
    depth = 0
    quoted = escaped = False
    for position in range(index, min(len(html), index + 1_800_000)):
        ch = html[position]
        if quoted:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                quoted = False
        else:
            if ch == '"':
                quoted = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(html[index:position+1])
                    except (json.JSONDecodeError, ValueError):
                        return None
    return None


def public_item(value, depth=0):
    if depth > 18:
        return None
    if isinstance(value, list):
        for obj in value[:100]:
            found = public_item(obj, depth + 1)
            if found:
                return found
    elif isinstance(value, dict):
        result = value.get("videoInfoRes")
        if isinstance(result, dict):
            items = result.get("item_list")
            if isinstance(items, list) and items and isinstance(items[0], dict):
                return items[0]
        detail = value.get("aweme_detail")
        if isinstance(detail, dict):
            return detail
        if isinstance(value.get("video"), dict):
            return value
        for obj in value.values():
            if isinstance(obj, (dict, list)):
                found = public_item(obj, depth + 1)
                if found:
                    return found
    return None


def media_from_item(item):
    if not isinstance(item, dict):
        return None
    video = item.get("video")
    if not isinstance(video, dict):
        return None

    def first_address(value):
        if isinstance(value, dict):
            candidates = value.get("url_list") or value.get("urlList") or []
            for link in candidates:
                if isinstance(link, dict):
                    link = link.get("src")
                if isinstance(link, str) and link.startswith("https://") and urlparse(link).hostname:
                    return link.replace("&amp;", "&")
        return None

    rates = video.get("bit_rate") or []
    if not isinstance(rates, list):
        rates = []
    rates = sorted((r for r in rates if isinstance(r, dict)),
                   key=lambda r: r.get("bit_rate") if isinstance(r.get("bit_rate"), int) else 1e12)
    for rate in rates:
        codec = str(rate.get("codec_type") or "").lower()
        if codec and "h264" not in codec and "avc" not in codec and "264" not in codec:
            continue
        if rate.get("is_h265"):
            continue
        found = first_address(rate.get("play_addr") or rate.get("playAddr"))
        if found:
            return found
    for key in ("play_addr_h264", "playAddrH264", "play_addr_lowbr"):
        found = first_address(video.get(key))
        if found:
            return found
    if not video.get("is_h265"):
        return first_address(video.get("play_addr") or video.get("playAddr"))
    return None


def parse_public_html(html):
    if not isinstance(html, str) or len(html) > MAX_HTML_SIZE:
        return None
    for marker in ("window._ROUTER_DATA", "window.__UNIVERSAL_DATA_FOR_REHYDRATION__"):
        item = public_item(json_after_marker(html, marker))
        if not item:
            continue
        media = media_from_item(item)
        if media:
            author = item.get("author") if isinstance(item.get("author"), dict) else {}
            name = str(item.get("desc") or author.get("nickname") or "抖音公开视频")[:160]
            return {"url": media, "title": name, "source": "douyin-public-share"}
    return None
