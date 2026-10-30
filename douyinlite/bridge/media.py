"""Private expiring media URLs and safe byte-range forwarding for iOS 8.

Only URLs already surfaced by the official public/authenticated browser session
may be registered. Redirects and destinations must remain on known media/CDN
hostnames. This is an HTTP compatibility adapter, not a rights bypass.
"""
from __future__ import annotations

import re
import secrets
import time
from urllib.parse import urlparse

ALLOWED_HOSTS = (
    "douyin.com", "iesdouyin.com", "douyinvod.com", "snssdk.com",
    "zjcdn.com", "byteimg.com", "bytecdn.cn", "bytedance.net",
)
MAX_MEDIA_URL = 8192
MAX_ITEMS = 400
TTL_SECONDS = 1800
RANGE_RE = re.compile(r"^bytes=(?:[0-9]+-[0-9]*|-[0-9]+)$")


def allowed_media_url(value):
    if not isinstance(value, str) or len(value) > MAX_MEDIA_URL:
        return False
    try:
        parsed = urlparse(value)
        hostname = (parsed.hostname or "").lower()
        return (parsed.scheme == "https" and bool(hostname) and
                not parsed.username and not parsed.password and
                parsed.port in (None, 443) and
                any(hostname == domain or hostname.endswith("." + domain)
                    for domain in ALLOWED_HOSTS))
    except ValueError:
        return False


def valid_byte_range(value):
    return value is None or (len(value) < 128 and RANGE_RE.fullmatch(value) is not None)


class MediaRegistry:
    def __init__(self):
        self.items = {}

    def add(self, url):
        if not allowed_media_url(url):
            return None
        now = time.monotonic()
        self.items = {key: pair for key, pair in self.items.items() if pair[1] > now}
        if len(self.items) >= MAX_ITEMS:
            oldest = min(self.items, key=lambda key: self.items[key][1])
            del self.items[oldest]
        token = secrets.token_urlsafe(24)
        self.items[token] = (url, now + TTL_SECONDS)
        return token

    def get(self, token):
        if not isinstance(token, str) or len(token) > 128:
            return None
        pair = self.items.get(token)
        if not pair:
            return None
        if pair[1] <= time.monotonic():
            del self.items[token]
            return None
        return pair[0]
