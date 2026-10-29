# DouyinLite V0.1.0

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

Use `downloads/DouyinLite-iOS8-v0.1.0.deb` with iFile / compatible jailbreak package manager.

## Limitations

Some links require authentication, DRM, private API authorization or newer codecs; there is no guarantee a Douyin share URL becomes a playable video. This release is build-tested in GitHub Actions but not device-tested on an actual iPhone 4S.
