"""Authorized remote Chromium desktop as low-rate H264/AAC HLS for iOS 8.

This captures the actual visible browser screen and its optional dedicated
virtual sink, without trying to bypass Douyin account or challenge controls.
"""
from __future__ import annotations

import asyncio
import os
import re
import secrets
import shutil
import subprocess
import time
from pathlib import Path

VIEWPORT = "1280x800"
SEGMENT_PATTERN = re.compile(r"^chunk[0-9]{6}\.ts$")
PLAYLIST_PATTERN = re.compile(r"(?m)^(chunk[0-9]{6}\.ts)$")


def playlist_with_ticket(playlist: str, ticket: str) -> str:
    return PLAYLIST_PATTERN.sub(lambda m: m.group(1) + "?ticket=" + ticket, playlist)


def valid_segment(filename: str) -> bool:
    return bool(SEGMENT_PATTERN.fullmatch(filename))


def available_audio_source():
    """Never select an arbitrary microphone; use our named virtual monitor only."""
    source = os.environ.get("DOUYIN_AUDIO_SOURCE", "douyin_capture.monitor")
    if os.environ.get("DOUYIN_AUDIO_ENABLED", "1") == "0" or not shutil.which("pactl"):
        return None
    try:
        result = subprocess.run(["pactl", "list", "short", "sources"],
                                capture_output=True, text=True, timeout=3, check=True)
        names = [line.split()[1] for line in result.stdout.splitlines()
                 if len(line.split()) >= 2]
        return source if source in names else None
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


def encoder_args(output, segments, audio_source=None):
    args = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
        "-thread_queue_size", "512", "-f", "x11grab",
        "-framerate", "12", "-video_size", VIEWPORT,
        "-i", os.environ.get("DISPLAY", ":99") + "+0,0",
    ]
    if audio_source:
        args += ["-thread_queue_size", "512", "-f", "pulse", "-i", audio_source,
                 "-map", "0:v:0", "-map", "1:a:0"]
    else:
        args += ["-map", "0:v:0", "-an"]
    args += [
        "-vf", "scale=640:400:flags=fast_bilinear",
        "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency",
        "-profile:v", "baseline", "-level", "3.0", "-pix_fmt", "yuv420p",
        "-b:v", "480k", "-maxrate", "650k", "-bufsize", "1300k",
        "-g", "24", "-keyint_min", "24", "-sc_threshold", "0",
    ]
    if audio_source:
        args += ["-c:a", "aac", "-b:a", "64k", "-ac", "2", "-ar", "44100"]
    return args + [
        "-f", "hls", "-hls_time", "2", "-hls_list_size", "5",
        "-hls_flags", "delete_segments+independent_segments+omit_endlist",
        "-hls_segment_filename", segments, output,
    ]


class CloudStream:
    def __init__(self, root="/tmp/douyin-hls"):
        self.root = Path(root)
        self.process = None
        self.ticket = None
        self.audio_enabled = False
        self.last_access = 0.0
        self.lock = asyncio.Lock()
        self.reaper = None

    def authorized(self, ticket):
        return bool(self.ticket and isinstance(ticket, str)
                    and secrets.compare_digest(self.ticket, ticket)
                    and time.monotonic() - self.last_access < 90
                    and self.process and self.process.returncode is None)

    def touch(self):
        self.last_access = time.monotonic()

    async def _stop_unlocked(self):
        self.ticket = None
        self.audio_enabled = False
        process, self.process = self.process, None
        if process and process.returncode is None:
            process.terminate()
            try:
                await asyncio.wait_for(process.wait(), timeout=4)
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()

    async def stop(self):
        async with self.lock:
            await self._stop_unlocked()

    async def _launch(self, audio_source):
        playlist = self.root / "index.m3u8"
        for old in self.root.iterdir():
            if old.is_file() and (old.suffix == ".ts" or old.name == "index.m3u8"):
                old.unlink()
        self.process = await asyncio.create_subprocess_exec(
            *encoder_args(str(playlist), str(self.root / "chunk%06d.ts"), audio_source),
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        for _ in range(40):
            if self.process.returncode is not None:
                raise RuntimeError("ffmpeg exited before first HLS segment")
            if playlist.exists() and "#EXTINF:" in playlist.read_text(errors="replace"):
                return
            await asyncio.sleep(0.25)
        raise RuntimeError("HLS startup timeout: inspect Xvfb/PulseAudio/ffmpeg")

    async def _expire_when_idle(self):
        while self.process and self.process.returncode is None:
            await asyncio.sleep(10)
            if time.monotonic() - self.last_access >= 90:
                await self.stop()
                return

    async def start(self):
        async with self.lock:
            if self.authorized(self.ticket):
                self.touch()
                return self.ticket
            await self._stop_unlocked()
            if os.environ.get("HEADLESS", "false").lower() == "true":
                raise RuntimeError("HLS requires the desktop display")
            if not shutil.which("ffmpeg"):
                raise RuntimeError("ffmpeg unavailable")
            self.root.mkdir(parents=True, exist_ok=True)
            source = available_audio_source()
            attempts = [source, None] if source else [None]
            last_error = None
            for candidate in attempts:
                try:
                    await self._launch(candidate)
                    self.audio_enabled = bool(candidate)
                    self.ticket = secrets.token_urlsafe(32)
                    self.touch()
                    if not self.reaper or self.reaper.done():
                        self.reaper = asyncio.create_task(self._expire_when_idle())
                    return self.ticket
                except (OSError, RuntimeError) as exc:
                    last_error = exc
                    await self._stop_unlocked()
            raise RuntimeError(str(last_error or "Could not start HLS"))

    async def close(self):
        await self.stop()
        if self.reaper and not self.reaper.done():
            self.reaper.cancel()
