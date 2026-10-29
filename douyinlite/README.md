# DouyinLite V0.4.0

## Mobile-first UX update
- Fullscreen vertical playback with native pan-to-next / pan-to-previous.
- Real bottom navigation: Home (explicit public demo feed), Search (local/imported clips and demo titles), Favorites, Me (library/history/settings).
- All toolbar and tab icons use crisp CoreGraphics vector line art, with active favorite state outlined in pink. No icon font or third-party dependency.
- Central tap to pause/resume, double tap to favorite with outlined heart effect, press and hold for temporary 2x, native share sheet.
- Controls are reorganized to avoid overlap with bottom navigation on the iPhone 4S 320x480 screen.
- Streaming/preload/animation preferences and history remain stored locally.
- This is NOT an official Douyin client. There is NO authenticated personalized recommendations feed or platform-wide search. The Home feed is visibly labeled as public demo videos.



### iOS 8 performance update

- 0.11s exit + 0.19s entry transitions on text/controls only (video layer stays fixed)
- Double-tap heart flash and small like-button pulse; respects Reduce Motion and in-app toggle
- Loading indicator while buffering; single video decoder only
- Metadata-only `AVURLAsset` prefetch for one upcoming item; can disable on the iPhone 4S
- Resumable position per video URL and last-seen feed position
- Added settings menu switches: animations, next-metadata-preload, autoplay next
- Demo clips can now be favorited and found in watch history



Native lightweight swipe-video player for jailbroken iPhone 4S (iOS 8.4.1 / ARMv7).

**Not an official Douyin client**. This version does not have Douyin login or the official "For You" video recommendation feed. Platform share-page links might not provide public playable URLs; where no public video metadata exists, the app explains the limitation and does not bypass access restrictions.

## Features

- Dark vertical full-screen video UI, swipe up/down to switch items
- Tap to play/pause, long press while playing for temporary 2x, double tap to favorite
- Playlist, local favorites, watch history, copy link, mute
- Import a user-accessible MP4/HLS link, or try public video metadata from a Douyin share URL
- Local file scan: `/var/mobile/Documents/DouyinLite` and `/var/mobile/Documents/PocketDrop` for MP4/MOV/M4V/M3U8
- One AVPlayer item at a time for the 512 MB iPhone 4S

## Installation

Use `downloads/DouyinLite-iOS8-v0.4.0.deb` with iFile / compatible jailbreak package manager.

## Limitations

Some links require authentication, DRM, private API authorization or newer codecs; there is no guarantee a Douyin share URL becomes a playable video. This release is build-tested in GitHub Actions but not device-tested on an actual iPhone 4S.

## V0.4.0
启动空列表时自动进入明确标注的 MIT/CC0 等公开样片测试流，支持上下滑动及播放结束自动下一条；尝试解析公开分享页中的结构化数据。演示流不是抖音推荐流，普通分享页仍可能受权限限制。
