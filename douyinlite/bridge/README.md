# DouyinBridge

A deployable **experimental** companion for DouyinLite on iPhone 4S. It runs a modern, persistent Chromium browser on a Linux VPS and extracts accessible public video metadata from normal page responses.

**Important:** This service does not bypass CAPTCHA or access controls. A real browser session can still be restricted by Douyin, and available media URLs may expire or use unsupported codecs. Successful compilation alone does not establish a working recommendation feed.

## What is included

- Persistent Playwright Chromium profile and interactive browser desktop (local-only noVNC).
- Manual verification when the browser is redirected to a verification page.
- Authorized JSON API with status, refresh and paginated feed.
- H.264 rendition priority and video deduplication.
- Docker Compose with Caddy automatic HTTPS.
- iOS 8 native client integration using an HTTPS endpoint and API token.

## Deploy

On a Linux VPS, install Docker and the Compose plugin. Minimum recommended 2 vCPU, 4 GB RAM. You also need a domain that points to the VPS and accessible TCP ports 80/443.

```bash
cd douyinlite/bridge
cp .env.example .env
# Edit SITE_HOST to your actual domain.
# Generate BRIDGE_KEY with: openssl rand -hex 24
docker compose -f compose.yml up -d --build
docker compose -f compose.yml logs -f bridge
```

Your API endpoint is `https://YOUR_DOMAIN/api/feed`.

## iPhone 4S native remote Chrome (experimental)

The iPhone's iOS 8 WebKit engine cannot render many modern web applications. DouyinLite now has a native remote viewer that renders **JPEG screenshots of the server-side Chromium browser** instead of trying to run Douyin's JavaScript on the phone.

Once the VPS bridge is deployed and the app is configured with the HTTPS `/api/feed` address and `BRIDGE_KEY`, open DouyinLite's source menu → **云端 Chrome · 登录 / 浏览**. You can tap the screenshot to click browser elements, double-tap to zoom, and use the native 上滑 / 下滑 / 后退 / 首页 buttons. You can also open the cloud viewer from the account login screen after configuring the bridge.

The browser desktop is 1280 × 800; the screenshot is refreshed about every two seconds. It supports human QR-code login and some verification screens, but **this is a low-frame-rate remote-control view, not full video streaming**. To play actual Douyin videos smoothly, the separate original AVPlayer video feed still requires accessible H.264 media URLs. Some site challenges can be unsuitable for a remote viewer or require a physical browser.

The remote-screen and input endpoints are protected by the same private Bearer API key as the feed. Don't expose the key or a public unauthenticated browser endpoint: screenshots can contain account information. Server resources and a domain with trusted HTTPS are required. This does **not** run Chromium on the iPhone or remove Douyin's access-control restrictions.

## Log in with your Douyin account

**Login is optional but supported.** Use the remote Chromium window, open the normal Douyin login dialog, and scan its QR code with the Douyin app on a second device. If required, complete SMS or other human verification there. Do not send account passwords, SMS codes, or cookies to DouyinLite or this repository.

The Chrome profile saves the browser session under the persistent `./profile` directory. You can turn off the computer used for initial setup, but the VPS running DouyinBridge must remain online. A saved session may expire, and a login does **not** guarantee video access on a cloud-server IP.

To inspect session state from the phone, choose **检查 DouyinBridge 登录状态** in DouyinLite. The bridge detects whether login-related session cookies exist, but this is a hint rather than proof the account is currently authenticated.

## Complete any required verification normally

On your desktop, connect to the VPS using SSH local port forwarding:

```bash
ssh -L 6080:127.0.0.1:6080 USER@SERVER
```

Open `http://localhost:6080/vnc.html` in a desktop browser. This shows the server's actual Chromium window. If Douyin presents a login QR code or a CAPTCHA challenge, complete the official login or verification process manually in that browser. Do not expose the noVNC service on the public Internet. The persistent browser profile in `./profile` is sensitive; do not commit or share it.

If verification is unavailable or access remains blocked, the bridge reports that state; it cannot force anonymous recommendations to work.

## Confirm actual content first

```bash
curl -H "Authorization: Bearer YOUR_BRIDGE_KEY" https://YOUR_DOMAIN/api/status
curl -H "Authorization: Bearer YOUR_BRIDGE_KEY" https://YOUR_DOMAIN/api/feed
```

The protected `/api/status` response reports `session_cookie_present` (cookie presence only, never the secret value), `manual_verification`, and the video count. A working feed must include actual items in `data`. A status of `verification_required`, `waiting_for_videos`, or an empty `data` array means the source is not ready.

The response is compatible with DouyinLite:
```json
{"data":[{"id":"123","title":"Public video","url":"https://media.example/video.mp4","source":"douyin-bridge"}],"next":"https://YOUR_DOMAIN/api/feed?cursor=12","status":"ready","message":""}
```
This is a schema example, **not a claim that Douyin returned those videos**.

## Configure DouyinLite

On iPhone 4S: open the source menu, choose **连接 DouyinBridge**, enter `https://YOUR_DOMAIN/api/feed` and the `BRIDGE_KEY` from `.env`. The client connects directly over HTTPS, without leaving a home PC on. Ensure the server supports TLS 1.2 and has a trusted certificate.

## Run unit tests

```bash
pip install -r requirements.txt
python -m pytest -q test_app.py
```

The unit tests cover parsing, duplicate removal, HTTPS URL validation and codec preference; actual site access needs a deployed instance and a real browser session.


## Low-bandwidth video preview (experimental)

The remote viewer offers an **播放云端画面** button. DouyinBridge uses ffmpeg to capture the browser desktop and serve 640×400 12fps H.264 Baseline HLS to iOS 8 AVPlayer, keeping legacy WebKit out of the playback path. This preview currently **has no audio**, needs the separately deployed Docker bridge, and must never be interpreted as native Douyin media extraction. It may show verification screens and remote browser navigation. Video streaming consumes CPU/bandwidth and requires ffmpeg. Close the player to stop its encoder.

Stream playback uses a short-lived secret URL, so treat the HLS address as private. Only HTTPS endpoints should be configured on the phone. Test on a physical iPhone 4S before treating performance as verified.


## Remote HLS sound experiment

The server now offers an optional PulseAudio virtual sink named
douyin_capture. The browser's audio can be multiplexed into HLS as AAC,
alongside H.264 Baseline browser-screen video. If the sink is not available,
the server returns a video-only stream and reports audio=false. Actual browser
media access, audible playback, and iPhone 4S performance need real-world tests.

The 90-second idle limit stops an abandoned encoder. The remote browser's
login and access challenges still require normal human completion.
