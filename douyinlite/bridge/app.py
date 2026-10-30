"""DouyinBridge: persistent, user-verifiable public browser session for DouyinLite.

This service does not circumvent CAPTCHA or platform access controls.
It only exposes videos visible in a normally accessible browser session.
"""
from __future__ import annotations

import asyncio
import hmac
import os
import time
from contextlib import asynccontextmanager
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, Field
from playwright.async_api import async_playwright

KEY = os.environ.get("BRIDGE_KEY", "")
PROFILE_DIR = os.environ.get("BROWSER_PROFILE", "/data/profile")
HEADLESS = os.environ.get("HEADLESS", "false").lower() == "true"
FEED_URL = "https://www.douyin.com/"
MAX_CACHE = 300
VIEWPORT_WIDTH = 1280
VIEWPORT_HEIGHT = 800

def _urls(address):
    if not isinstance(address, dict):
        return []
    candidates = address.get("url_list")
    return candidates if isinstance(candidates, list) else []

def playable_url(video):
    """Prefer AVC/H.264; never deliberately select a known HEVC-only rendition."""
    if not isinstance(video, dict):
        return None
    for rate in video.get("bit_rate", []) or []:
        if not isinstance(rate, dict):
            continue
        codec = str(rate.get("codec_type", "")).lower()
        if codec and not any(k in codec for k in ("h264", "avc", "264")):
            continue
        for candidate in _urls(rate.get("play_addr")):
            if is_https_video(candidate):
                return candidate
    for candidate in _urls(video.get("play_addr")):
        if is_https_video(candidate):
            return candidate
    return None

def is_https_video(value):
    if not isinstance(value, str) or len(value) > 8192:
        return False
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.hostname)

def extract_items(payload):
    """Extract public video metadata from nested feed/SSR JSON responses."""
    results = []
    seen = set()
    def walk(node, depth=0):
        if depth > 14 or len(results) >= 80:
            return
        if isinstance(node, list):
            for item in node[:120]:
                walk(item, depth + 1)
        elif isinstance(node, dict):
            video = node.get("video")
            link = playable_url(video)
            if link:
                item_id = str(node.get("aweme_id") or node.get("id") or link)
                if item_id not in seen:
                    seen.add(item_id)
                    title = node.get("desc") or node.get("title") or ""
                    author = node.get("author")
                    if not title and isinstance(author, dict):
                        title = author.get("nickname", "")
                    results.append({
                        "id": item_id[:100],
                        "url": link,
                        "title": str(title or "抖音公开视频")[:180],
                        "source": "douyin-bridge",
                    })
            for value in node.values():
                if isinstance(value, (list, dict)):
                    walk(value, depth + 1)
    walk(payload)
    return results


class BrowserFeed:
    def __init__(self):
        self.playwright = None
        self.context = None
        self.page = None
        self.items = []
        self.ids = set()
        self.status = "starting"
        self.error = None
        self.last_seen = 0.0
        self.lock = asyncio.Lock()
        self.navigation_lock = asyncio.Lock()

    async def start(self):
        self.playwright = await async_playwright().start()
        try:
            self.context = await self.playwright.chromium.launch_persistent_context(
                PROFILE_DIR, headless=HEADLESS, viewport={"width": VIEWPORT_WIDTH, "height": VIEWPORT_HEIGHT},
                locale="zh-CN", accept_downloads=False,
            )
            self.page = self.context.pages[0] if self.context.pages else await self.context.new_page()
            self.page.on("response", self.on_response)
            await self.navigate()
        except Exception as exc:
            self.status = "browser_error"
            self.error = str(exc)[:300]

    async def navigate(self):
        if self.page is None:
            return
        async with self.navigation_lock:
            self.status = "loading"
            try:
                await self.page.goto(FEED_URL, wait_until="domcontentloaded", timeout=35000)
                await self.page.wait_for_timeout(2500)
                await self.check_status()
            except Exception as exc:
                self.status = "browser_error"
                self.error = str(exc)[:250]

    async def check_status(self):
        if self.page is None:
            return
        try:
            title = (await self.page.title()).lower()
            url = self.page.url.lower()
            challenge = ("验证码", "验证中", "captcha", "challenge", "verify")
            if any(word in title or word in url for word in challenge):
                self.status = "verification_required"
            elif self.items:
                self.status = "ready"
            else:
                self.status = "waiting_for_videos"
        except Exception as exc:
            self.status = "browser_error"
            self.error = str(exc)[:250]

    async def on_response(self, response):
        parsed = urlparse(response.url)
        hostname = parsed.hostname or ""
        if not (hostname == "douyin.com" or hostname.endswith(".douyin.com")):
            return
        if not any(part in parsed.path for part in ("/aweme/", "/feed/", "/video/")):
            return
        if "json" not in response.headers.get("content-type", "").lower():
            return
        try:
            if int(response.headers.get("content-length", "0")) > 4_000_000:
                return
            value = await response.json()
            new_items = extract_items(value)
            if not new_items:
                return
            async with self.lock:
                for item in new_items:
                    if item["id"] not in self.ids and len(self.items) < MAX_CACHE:
                        self.ids.add(item["id"])
                        self.items.append(item)
                self.last_seen = time.time()
                self.status = "ready"
                self.error = None
        except Exception:
            pass

    async def ensure_items(self, minimum):
        if not self.page or self.status == "browser_error":
            return
        await self.check_status()
        if self.status == "verification_required":
            return
        if len(self.items) >= minimum:
            return
        async with self.navigation_lock:
            for _ in range(4):
                if len(self.items) >= minimum or len(self.items) >= MAX_CACHE:
                    break
                try:
                    await self.page.mouse.wheel(0, 850)
                    await self.page.keyboard.press("ArrowDown")
                    await self.page.wait_for_timeout(1200)
                    await self.check_status()
                    if self.status == "verification_required":
                        break
                except Exception as exc:
                    self.error = str(exc)[:250]
                    break

    async def session_info(self):
        """Report cookie presence without disclosing credentials or claiming login validity."""
        cookie_names = {"sessionid", "sessionid_ss", "sid_tt", "sid_guard"}
        result = {"session_cookie_present": False, "login_verified": False}
        if not self.context:
            return result
        try:
            cookies = await self.context.cookies(FEED_URL)
            result["session_cookie_present"] = any(
                item.get("name", "").lower() in cookie_names and bool(item.get("value"))
                for item in cookies
            )
        except Exception:
            pass
        return result

    async def close(self):
        if self.context:
            await self.context.close()
        if self.playwright:
            await self.playwright.stop()


engine = BrowserFeed()

@asynccontextmanager
async def lifespan(app):
    if not KEY or len(KEY) < 16:
        raise RuntimeError("Set BRIDGE_KEY to a random secret of at least 16 characters")
    await engine.start()
    yield
    await engine.close()

app = FastAPI(title="DouyinBridge", lifespan=lifespan, docs_url=None, redoc_url=None)

def authorize(request: Request):
    supplied = request.headers.get("authorization", "")
    expected = "Bearer " + KEY
    if not KEY or not hmac.compare_digest(supplied, expected):
        raise HTTPException(status_code=401, detail="Invalid bridge token")

@app.get("/health")
async def health():
    return {"ok": True}

@app.get("/api/status")
async def status(request: Request):
    authorize(request)
    await engine.check_status()
    session = await engine.session_info()
    return {
        "status": engine.status, "items": len(engine.items),
        "last_seen": int(engine.last_seen), "error": engine.error,
        "manual_verification": engine.status == "verification_required",
        **session,
        "login_help": "Use the private noVNC browser desktop to log in or complete verification manually. A cookie does not guarantee a valid account session.",
    }

@app.get("/api/feed")
async def feed(request: Request, cursor: int = 0):
    authorize(request)
    if cursor < 0 or cursor >= MAX_CACHE:
        raise HTTPException(status_code=400, detail="Invalid cursor")
    await engine.ensure_items(cursor + 12)
    items = engine.items[cursor:cursor + 12]
    next_cursor = cursor + len(items)
    next_url = (str(request.url_for("feed")) + "?cursor=" + str(next_cursor)) if items and next_cursor < MAX_CACHE else None
    return {
        "data": items, "next": next_url,
        "status": engine.status, "message": engine.error or (
            "请在云端浏览器正常完成人工验证" if engine.status == "verification_required"
            else "暂无可访问的视频，请检查浏览器页面" if not items else ""
        ),
    }

@app.post("/api/refresh")
async def refresh(request: Request):
    authorize(request)
    engine.items.clear()
    engine.ids.clear()
    await engine.navigate()
    return {"status": engine.status, "items": len(engine.items)}

class BrowserTap(BaseModel):
    x: float = Field(ge=0, le=VIEWPORT_WIDTH)
    y: float = Field(ge=0, le=VIEWPORT_HEIGHT)

class BrowserScroll(BaseModel):
    dy: int = Field(ge=-1200, le=1200)

async def browser_page():
    if engine.page is None:
        raise HTTPException(status_code=503, detail="Cloud browser is not running")
    return engine.page

@app.get("/api/browser/frame")
async def browser_frame(request: Request):
    """A JPEG of the REAL remote Chromium viewport; iOS 8 needs no JS/WebKit."""
    authorize(request)
    page = await browser_page()
    try:
        async with engine.navigation_lock:
            pixels = await page.screenshot(type="jpeg", quality=45, scale="css", timeout=10000)
        return Response(
            content=pixels, media_type="image/jpeg",
            headers={"Cache-Control": "private, no-store, max-age=0",
                     "X-Viewport-Width": str(VIEWPORT_WIDTH),
                     "X-Viewport-Height": str(VIEWPORT_HEIGHT)},
        )
    except Exception:
        raise HTTPException(status_code=503, detail="Screenshot temporarily unavailable")

@app.post("/api/browser/tap")
async def browser_tap(request: Request, point: BrowserTap):
    authorize(request)
    page = await browser_page()
    async with engine.navigation_lock:
        try:
            await page.mouse.click(point.x, point.y, delay=80)
        except Exception:
            raise HTTPException(status_code=503, detail="Browser could not process the tap")
    return {"ok": True}

@app.post("/api/browser/scroll")
async def browser_scroll(request: Request, scroll: BrowserScroll):
    authorize(request)
    page = await browser_page()
    async with engine.navigation_lock:
        try:
            await page.mouse.wheel(0, scroll.dy)
        except Exception:
            raise HTTPException(status_code=503, detail="Browser could not scroll")
    return {"ok": True}

@app.post("/api/browser/home")
async def browser_home(request: Request):
    authorize(request)
    await browser_page()
    await engine.navigate()
    return {"ok": True, "status": engine.status}

@app.post("/api/browser/back")
async def browser_back(request: Request):
    authorize(request)
    page = await browser_page()
    async with engine.navigation_lock:
        try:
            await page.go_back(wait_until="domcontentloaded", timeout=12000)
        except Exception:
            raise HTTPException(status_code=503, detail="Browser could not navigate back")
    return {"ok": True}
