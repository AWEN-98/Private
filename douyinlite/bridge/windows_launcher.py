#!/usr/bin/env python3
"""Run the existing DouyinBridge with a real Chromium login on a Windows PC.

This uses official Douyin pages in a user-visible browser. No password,
verification code, or session cookie is copied from the computer to the iPhone.
The mobile app connects to this particular desktop browser over an authenticated,
temporary HTTPS tunnel. The computer must stay running.
"""
from __future__ import annotations

import os
import pathlib
import queue
import re
import secrets
import subprocess
import sys
import threading
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
PORT = 18765
HEALTH = "http://127.0.0.1:%d/health" % PORT
CF_URL = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
TUNNEL_URL_RE = re.compile(r"(?<![a-z0-9.])https://[a-z0-9-]+\.trycloudflare\.com(?=$|[\s/\"'<>)])", re.I)
MAX_BINARY = 150 * 1024 * 1024
MIN_BINARY = 8 * 1024 * 1024


def load_secret(path: pathlib.Path) -> str:
    if path.exists():
        secret = path.read_text(encoding="ascii").strip()
        if not re.fullmatch(r"[a-f0-9]{48}", secret):
            raise ValueError("Stored bridge key is invalid; inspect .bridge-key before retrying.")
        return secret
    secret = secrets.token_hex(24)
    with path.open("x", encoding="ascii") as handle:
        handle.write(secret + "\n")
    return secret


def cloudflared_path(root: pathlib.Path) -> pathlib.Path:
    local = root / "cloudflared.exe"
    if local.exists():
        return local
    print("正在从 Cloudflare 官方 GitHub 下载 cloudflared 客户端…", flush=True)
    tmp = local.with_suffix(".download")
    try:
        with urllib.request.urlopen(CF_URL, timeout=60) as response, tmp.open("wb") as output:
            if not response.geturl().startswith("https://"):
                raise RuntimeError("Cloudflared download was redirected outside HTTPS")
            total = 0
            magic = response.read(2)
            if magic != b"MZ":
                raise RuntimeError("Download was not a Windows executable")
            output.write(magic)
            total += len(magic)
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > MAX_BINARY:
                    raise RuntimeError("Cloudflared download exceeded maximum allowed size")
                output.write(chunk)
        if total < MIN_BINARY:
            raise RuntimeError("Cloudflared download was incomplete")
        tmp.replace(local)
        return local
    finally:
        tmp.unlink(missing_ok=True)


def tunnel_address(lines: list[str]) -> str | None:
    for line in lines:
        match = TUNNEL_URL_RE.search(line)
        if match:
            return match.group(0).lower()
    return None


def read_lines(stream, messages: queue.Queue, name: str):
    for line in iter(stream.readline, ""):
        messages.put((name, line.rstrip("\r\n")))


def wait_health(proc: subprocess.Popen, seconds: int = 40):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if proc.poll() is not None:
            raise RuntimeError("DouyinBridge exited before becoming ready")
        try:
            with urllib.request.urlopen(HEALTH, timeout=2) as response:
                if response.status == 200:
                    return
        except Exception:
            pass
        time.sleep(0.5)
    raise RuntimeError("DouyinBridge did not start on localhost")


def main():
    if os.name != "nt":
        raise RuntimeError("This companion launcher is for Windows 10/11 (64-bit)")
    os.chdir(ROOT)
    key = load_secret(ROOT / ".bridge-key")
    tunnel_executable = cloudflared_path(ROOT)
    env = dict(os.environ)
    env["BRIDGE_KEY"] = key
    env["HEADLESS"] = "false"
    env["BROWSER_PROFILE"] = str(ROOT / "profile")
    bridge = None
    tunnel = None
    try:
        # A genuine visible Chromium window handles login, QR, SMS, and platform verification.
        bridge = subprocess.Popen(
            [sys.executable, "-m", "uvicorn", "app:app",
             "--host", "127.0.0.1", "--port", str(PORT),
             "--proxy-headers", "--forwarded-allow-ips", "127.0.0.1"],
            cwd=str(ROOT), env=env, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        wait_health(bridge)
        tunnel = subprocess.Popen(
            [str(tunnel_executable), "tunnel", "--no-autoupdate",
             "--url", "http://127.0.0.1:%d" % PORT],
            cwd=str(ROOT), stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace", bufsize=1)
        messages = queue.Queue()
        for name, stream in (("stdout", tunnel.stdout), ("stderr", tunnel.stderr)):
            threading.Thread(target=read_lines, args=(stream, messages, name), daemon=True).start()
        entries = []
        expiry = time.monotonic() + 60
        url = None
        while time.monotonic() < expiry:
            if tunnel.poll() is not None:
                raise RuntimeError("Cloudflare tunnel exited before providing an HTTPS URL")
            try:
                name, line = messages.get(timeout=0.5)
            except queue.Empty:
                continue
            entries.append(line)
            url = tunnel_address([line])
            if url:
                break
        if not url:
            raise RuntimeError("Cloudflare tunnel did not provide an HTTPS address")
        print("\n========== DouyinLite 电脑扫码登录 ==========", flush=True)
        print("1. 请在电脑打开的 Chromium 窗口内访问抖音官方登录页面并扫码确认。")
        print("2. 在 iPhone 的 DouyinLite 登录页选择「电脑浏览器扫码登录」。")
        print("3. 输入下面两项，或在手机视频来源菜单中设置 DouyinBridge：")
        print("   HTTPS 地址: %s/api/feed" % url)
        print("   私有密钥: %s" % key)
        print("4. 在 iPhone 打开云端 Chrome，查看登录状态或使用云端视频源。")
        print("重要：这台电脑须保持开机，切勿向他人泄露私有密钥。")
        print("请勿将登录 Cookie、密码或短信验证码发给任何人。")
        print("此方法使用官方登录页面，不保证平台一定允许登录或提供视频流。")
        print("==========================================\n", flush=True)
        while True:
            if bridge.poll() is not None or tunnel.poll() is not None:
                raise RuntimeError("Companion process exited. Check firewall/network and restart.")
            time.sleep(2)
    except KeyboardInterrupt:
        print("\n电脑登录服务已停止。", flush=True)
    finally:
        for proc in (tunnel, bridge):
            if proc and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError) as exc:
        print("启动失败: %s" % exc, file=sys.stderr)
        sys.exit(1)
