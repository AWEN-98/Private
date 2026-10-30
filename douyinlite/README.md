# DouyinLite 0.13.0

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


## V0.11.0 手机独立版

无需电脑、远程浏览器或自己部署的服务器。右上角加号粘贴官方抖音公开视频链接，软件依次尝试两个官方移动视频接口以及两条官方分享页路径，成功获取的 H.264 视频交给 iOS 原生播放器。

此版本保留本机账号推荐试验功能，并从菜单隐藏需要外部设备或云端服务的操作。没有可靠的匿名首页推荐接口；真实抖音播放是否成功取决于平台对当前网络的访问控制、旧版系统证书及媒体编码，仍需真机测试。


## 0.12.0 纯手机连续观看改进

这一版沿用用户已在 iPhone 4S 验证可以播放的官方公开视频获取路径。

1. 右上角加号可粘贴一条或多条抖音分享文案。包含多条链接时，会先确认，再按顺序逐条导入，最多12条。
2. 左上角视频来源菜单可以直接选择「从剪贴板连续导入」。导入成功的内容进入播放列表，上下滑动连续观看；个别链接失败不会中断其余链接。
3. 保存每个导入作品的原始分享链接和作品编号。视频播放失败时最多自动重新获取一次，避免因为视频媒体地址过期导致永久失效；菜单可以手动重新获取当前视频。
4. 保留 iOS 8 原生播放器的自动播放、收藏、历史、自动切换及下一条预加载，手机无须任何电脑或服务器支持。

限制：批量导入需要用户提供真实的公开抖音链接。平台是否返回匿名推荐列表尚未通过真机验证，本版本不能保证打开首页直接无限刷抖音推荐。网络、平台访问控制、证书、编码和视频失效均可能影响播放。


## 0.13.0 游客直接刷与可选扫码登录

- 首页启动后立即请求抖音公开的视频列表，即使尚未登录账号。先尝试两条移动端公开视频列表路径，如果未取得视频则使用现有的本机签名网页版推荐接口。
- 网页版游客请求之前先请求一次官方首页以接收访客 Cookie，复用同一个 iOS HTTP Cookie 存储；无需扫码。
- 首页自动翻页，下一条预加载、H.264 原生播放继续沿用此前的成熟代码。
- 底栏只显示「首页」「收藏」「我的」；顶部不再显示导入和菜单按钮。视频右侧只显示本地收藏书签、系统分享，未实现平台真实操作的点赞和评论按钮已移除。
- 在「我的」里选择「扫码登录抖音」，由另一台有抖音应用的设备扫码、确认，软件保存登录会话并刷新账号推荐；登录可选。
- 保留已有公开分享视频的解析代码和本机播放列表，避免覆盖安装后丢失用户已保存的数据，但不在主界面展示导入入口。

重要：用户在 iPhone 4S 真机上确认过单条分享链接可播放。新加的匿名推荐列表和扫码登录，需要同机实际连接抖音服务器测试。网页未登录能浏览不意味着未经现代浏览器交互的 API 请求必然返回视频。如果平台返回空列表或验证页，应用会显示真实错误，不使用假推荐视频填充。


0.13.0 追加：当手机端公开视频列表与网页版签名推荐都没有取得有效视频时，会自动尝试抖音官方公开热门视频接口 https://www.iesdouyin.com/web/api/v2/hotsearch/aweme/ 。仅显示官方真实返回且带有兼容播放地址的视频，热榜以「热门」标识，不能视为个性化推荐。部分地区或网络也可能限制该接口访问。
