DouyinLite + Surf iPhone 4S 兼容整合包 v0.10.8

适用：iPhone 4S，iOS 8.4.1，已越狱；Windows 10/11 x64 电脑。
目标：利用电脑上的现代 Chromium，解决 iOS 8 的旧浏览器无法加载现代抖音网页的问题。

重要：电脑需要持续开机并正常联网；手机和电脑建议连接同一 Wi-Fi。
这里使用的 Surf 是 seg6 的独立开源项目，MIT 授权。
Surf 的音视频传输支持已由原项目实现，但抖音本身是否允许播放需要登录、网络和真机验证。

首次安装（在手机上）
1. 将 iPhone4S 文件夹里的两个 DEB 文件传到手机，用 iFile 安装。
   先安装 Surf-iPhone4S-iOS8.deb，再安装 DouyinLite-v0.10.8.deb。
   注意：如果原本安装了 DouyinLite，直接安装新版覆盖即可。
2. 安装完若图标没有出现，执行 uicache 或重启 SpringBoard。

首次启动（在 Windows 电脑上）
1. 解压整个 ReadyKit 压缩包到一个固定文件夹，请勿直接在压缩包内部运行。
2. 双击 01-Start-Douyin-Host.cmd。Windows 防火墙询问时允许专用网络。
3. 双击 03-Pair-Phone.cmd，或者在 Surf 的托盘图标中选择 Paired Devices / Pair device。
4. 打开 iPhone 的 Surf 应用，用配对码或二维码完成配对。
5. 需要登录时，双击电脑上的 02-Open-Login-Browser.cmd，在桌面 Chrome 正常登录抖音。
   关闭电脑浏览器设置窗口后，继续手机浏览。
6. 回到 iPhone 的 DouyinLite，打开「视频来源」，点「Surf 模式 · 刷抖音（推荐）」。
   这会进入 Surf，并自动导航到 https://www.douyin.com/。

首次配对只需做一次，之后通常只需开启电脑 Surf 服务，手机点 Surf 模式。
手机通过网络与电脑连接，视频与声音传到手机，点击/滑动指令返回电脑。

排查
1. 手机上打开 Surf 提示未连接：检查主机同 Wi-Fi、防火墙 TCP 18080、电脑是否开机。
2. Surf 已连接，但抖音要求验证：用电脑的 Browser setup 正常登录。
3. 出现空白或视频无法播：先在电脑打开同一个 Surf 浏览器验证网页有无视频及声音。
4. iPhone 4S 播放不流畅：脚本默认采用 1800kbps 和自适应模式，可适当减小 STREAM_BITRATE。
5. Surf 未安装：DouyinLite 会显示安装说明；本包保留原 DouyinLite 本机解析模式。
6. 不要公开分享 %LOCALAPPDATA%\DouyinLiteSurfHost，里面存有账号会话和加密身份。

官方网站（本包不从其他来源重打包 Surf）：
https://github.com/seg6/surf
https://github.com/seg6/surf/releases/tag/v0.17.0

该整合包不包含解锁任何抖音验证或访问限制的功能。
没有第三方服务器费用，但电脑必须保持运行，无法实现离线独立刷抖音。
