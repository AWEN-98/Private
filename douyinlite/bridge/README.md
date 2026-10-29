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
