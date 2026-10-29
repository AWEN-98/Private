#!/bin/sh
set -eu
mkdir -p /data/profile
if [ "${HEADLESS:-false}" != "true" ]; then
  Xvfb :99 -screen 0 1440x900x24 -nolisten tcp &
  sleep 1
  x11vnc -display :99 -localhost -nopw -forever -shared -rfbport 5900 >/tmp/douyin-vnc.log 2>&1 &
  websockify --web=/usr/share/novnc 6080 127.0.0.1:5900 >/tmp/douyin-novnc.log 2>&1 &
fi
exec uvicorn app:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*'
