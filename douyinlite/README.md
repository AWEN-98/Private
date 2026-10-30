# DouyinLite 0.10.8

Native ARMv7 application for jailbroken iPhone 4S, iOS 8.0 and later.

This release adds a native QR account screen, local session persistence and authenticated, locally signed Douyin feed requests. It does not require a computer or a separate server for ongoing native requests and playback. QR login requires another device running the official Douyin app to scan and confirm. Login, access to recommendations and playback still require real-device verification. A successful build or offline signature test does not demonstrate that Douyin accepted a live request.

## Use

Install downloads/DouyinLite-iOS8-v0.10.0.deb, open the account entry in the Me menu, scan the QR with Douyin on another device and confirm. The client follows the official callback, checks the account-info endpoint and saves the session. Close the account screen to refresh the feed.

The app distinguishes waiting, scanned, confirmed, expired, additional verification, network errors, empty responses and non-JSON challenge pages. An account is reported as verified only when the account-info endpoint returns success with a user identifier. Cookie presence alone does not demonstrate a valid account.

Sessions use the device keychain. When old jailbreak keychains reject writes, the client tries an owner-only file with iOS data protection. If neither works, the screen reports that the session was not saved. Logout removes both stores and clears Douyin cookies.

## Requests and playback

A-Bogus and SM3 run locally in ES5 JavaScriptCore. The signed query and POST body use identical bytes in the signer and request. Visitor cookies are reused, including UIFID when present. Login callbacks and redirects only follow HTTPS official domains. Feed responses use generation checks, video-ID deduplication, bounded memory and a cooldown after empty responses.

A single AVPlayer handles swipe playback, tap pause and hold for 2x. Lower bitrate H.264 variants are preferred; known HEVC-only variants are skipped. The optional UIWebView account page shares NSHTTPCookieStorage with native requests on iOS 8. Its old JavaScript engine remains a compatibility limit.

## Verification and limitations

Run node douyinlite/tests/test_signer.js for standard SM3 vectors, complete cross-language signature vectors, request binding and invalid-clock handling. CI builds with Theos and iPhoneOS10.3 SDK, target iOS 8.0, armv7. It checks DEB gzip members, bundle identity, executable architecture and signer resources.

Official QR endpoints can return a challenge page. A valid login does not guarantee recommendation access. The app reports those states and cannot solve platform challenges automatically. iOS 8 TLS, certificates and decoding remain device-dependent. Optional bridge, PeerTube and imported/local playback tools remain explicit alternatives.

The ES5 signer derives from Apache-2.0 upstream code. See bundled ThirdPartyNotices.txt and Apache-2.0.txt.

## 0.10.6 public Douyin video viewing

Paste an official public Douyin share link using the Add Video button.
The native client tries the official mobile share page with the ID from
the supplied link or its redirect. A compatible H.264 video is opened in
the iOS 8 video player when public metadata is available.

When DouyinBridge has been configured explicitly, failed local extraction
can fall back to the bridge /api/resolve endpoint. The bridge provides
temporary CDN-compatible media URLs with byte-range support. Browser
verification, expired video links, iOS TLS errors, and unsupported codecs
can still prevent playback. CI success does not prove real-device playback.

## 0.10.7 additional feed fallback

DouyinBridge tries the normal browser JSON responses first. When the Chrome
site is accessible but its JSON feed is empty, it also reads actual public
video links already displayed in the page, then checks their official
public share pages. It never invents recommendations or assumes a login
challenge is solved. Only returned accessible media URLs are sent to iOS.


## 0.10.8 Surf handoff

The video-source menu has a **Surf 模式 · 刷抖音（推荐）** option.
When the official Surf native client v0.17.0 is installed, this opens
`surf-https://www.douyin.com/` through its URL handler and uses a paired
modern desktop Chromium browser to load Douyin.

Surf is a separate MIT-licensed program from https://github.com/seg6/surf.
It requires a Windows, macOS, or Linux host for video and audio; this app
does not bundle Chromium or claim standalone modern web compatibility.
For an iPhone 4S on iOS 8.4.1, use the companion setup kit from the
repository's downloads directory, start Surf on a Windows computer, and
pair the phone before pressing the new option.

Actual Douyin browser access, account verification and video autoplay depend
on the website and network; a build test alone does not verify those.
