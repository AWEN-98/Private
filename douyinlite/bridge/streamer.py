"""Low-bandwidth H.264 HLS view of an already authenticated, user-operated Chrome desktop.

The stream displays the server's normal browser viewport. It does not extract
restricted videos or defeat website verification. Start/stop is explicit to
avoid burning CPU while the user only needs a screenshot for login.
"""
from __future__ import annotations

import asyncio
import os
import re
import secrets
import shutil
import time
from pathlib import Path

VIEWPORT = "1280x800"
SEGMENT_PATTERN = re.compile(r"^chunk[0-9]{6}\.ts$")
PLAYLIST_PATTERN = re.compile(r"(?m)^(chunk[0-9]{6}\.ts)$")


def playlist_with_ticket(playlist: str, ticket: str) -> str:
    """Carry an ephemeral viewer token to iOS AVPlayer's segment requests."""
    return PLAYLIST_PATTERN.sub(lambda m: m.group(1) + "?ticket=" + ticket, playlist)


def valid_segment(filename: str) -> bool:
    return bool(SEGMENT_PATTERN.fullmatch(filename))


class CloudStream:
    def __init__(self, root: str = "/tmp/douyin-hls"):
        self.root = Path(root)
        self.process = None
        self.ticket = None
        self.last_access = 0.0
        self.lock = asyncio.Lock()

    def authorized(self, ticket: str) -> bool:
        return bool(
            self.ticket and isinstance(ticket, str)
            and secrets.compare_digest(self.ticket, ticket)
            and time.monotonic() - self.last_access < 90
            and self.process and self.process.returncode is None
        )

    def touch(self) -> None:
        self.last_access = time.monotonic()

    async def stop(self) -> None:
        async with self.lock:
            await self._stop_unlocked()

    async def _stop_unlocked(self) -> None:
        self.ticket = None
        process = self.process
        self.process = None
        if process and process.returncode is None:
            process.terminate()
            try:
                await asyncio.wait_for(process.wait(), timeout=4)
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()

    async def start(self) -> str:
        async with self.lock:
            if self.process and self.process.returncode is None and self.ticket:
                self.touch()
                return self.ticket
            await self._stop_unlocked()
            if os.environ.get("HEADLESS", "false").lower() == "true":
                raise RuntimeError("HLS requires the Xvfb browser desktop, HEADLESS=false")
            if not shutil.which("ffmpeg"):
                raise RuntimeError("ffmpeg is unavailable in this bridge container")
            self.root.mkdir(parents=True, exist_ok=True)
            for old in self.root.glob("*"):
                if old.is_file() and (old.name.endswith(".ts") or old.name == "index.m3u8"):
                    old.unlink()
            output = self.root / "index.m3u8"
            segments = self.root / "chunk%06d.ts"
            # 640x400, 12 fps H.264 Baseline / YUV420p is decoder-friendly for iPhone 4S.
            # X11 screen recording has NO audio until virtual-audio capture is implemented.
            args = [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
                "-f", "x11grab", "-framerate", "12", "-video_size", VIEWPORT,
                "-i", os.environ.get("DISPLAY", ":99") + "+0,0",
                "-an", "-vf", "scale=640:400:flags=fast_bilinear",
                "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency",
                "-profile:v", "baseline", "-level", "3.0", "-pix_fmt", "yuv420p",
                "-b:v", "480k", "-maxrate", "650k", "-bufsize", "1300k",
                "-g", "24", "-keyint_min", "24", "-sc_threshold", "0",
                "-f", "hls", "-hls_time", "2", "-hls_list_size", "5",
                "-hls_flags", "delete_segments+independent_segments+omit_endlist",
                "-hls_segment_filename", str(segments), str(output),
            ]
            self.process = await asyncio.create_subprocess_exec(
                *args, stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            self.ticket = secrets.token_urlsafe(32)
            self.touch()
            # Wait for the first playlist so the iOS player does not see a 404.
            for _ in range(36):
                if self.process.returncode is not None:
                    await self._stop_unlocked()
                    raise RuntimeError("ffmpeg exited before the first video segment")
                if output.exists() and "#EXTINF:" in output.read_text(errors="replace"):
                    return self.ticket
                await asyncio.sleep(0.25)
            await self._stop_unlocked()
            raise RuntimeError("Timed out preparing HLS; check Xvfb and ffmpeg")

    async def close(self) -> None:
        await self.stop()
