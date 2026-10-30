#!/bin/sh
set -eu
mkdir -p /data/profile
if [ "${HEADLESS:-false}" != "true" ]; then
  Xvfb :99 -screen 0 1440x900x24 -nolisten tcp &
  sleep 1
  x11vnc -display :99 -localhost -nopw -forever -shared -rfbport 5900 >/tmp/douyin-vnc.log 2>&1 &
  websockify --web=/usr/share/novnc 6080 127.0.0.1:5900 >/tmp/douyin-novnc.log 2>&1 &
  export XDG_RUNTIME_DIR=/tmp/douyin-pulse-runtime
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
  export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"
  export DOUYIN_AUDIO_SOURCE=douyin_capture.monitor
  pulseaudio --daemonize=no --exit-idle-time=-1 --disallow-exit --log-target=stderr >/tmp/douyin-pulse.log 2>&1 &
  for step in 1 2 3 4 5 6 7 8 9 10; do
    if pactl info >/dev/null 2>&1; then
      pactl load-module module-null-sink sink_name=douyin_capture sink_properties=device.description=DouyinCapture >/dev/null 2>&1 || true
      pactl set-default-sink douyin_capture >/dev/null 2>&1 || true
      break
    fi
    sleep 1
  done
fi
exec uvicorn app:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*'
