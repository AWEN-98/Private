DouyinLite + Surf 真机兼容版 R2

适用设备：越狱 iPhone 4S，iOS 8.4.1，Windows 10 / 11 64 位电脑。

【手机安装】
1. 将 iPhone4S 下的 Surf-iPhone4S-iOS8-installfix2.deb 传到手机。
   优先用 iFile 打开 DEB 并点击安装。
2. 再安装 DouyinLite-v0.10.8.deb，已有旧版可以覆盖。
3. 如果图标没显示，先注销桌面或重启 SpringBoard。
4. 如 iFile 依旧无法安装，用 Cydia 官方 Surf 源 https://seg6.space/surf/ 尝试。
   旧系统可能因为证书和源兼容性而无法添加；此时采用上面的 gzip DEB。

【启动电脑端】
1. 完整解压 ZIP，电脑需要安装或能自动获取 Chrome/Edge/Chromium。
2. 双击 01-Start-Douyin-Host.cmd。允许 Windows 专用网络防火墙访问。
3. 双击 05-Diagnose-Connection.cmd，确认 18080 端口正在监听。
4. 双击 03-Pair-Phone.cmd，在手机 Surf 内完成首次安全配对，确认六个词一致。
5. 双击 02-Open-Login-Browser.cmd，先测试 example.com，再测试 douyin.com。
   抖音如要求验证码或登录，请正常操作。关闭电脑设置浏览器窗口后手机恢复流。
6. 打开 DouyinLite，进入「视频来源」，点击「Surf 模式 · 刷抖音」。

【如果安装又失败】
A. iFile 提示 return 256/exit code 256：请在 iFile 安装记录中找到第一条明确的错误。
B. 如果 Cydia 或其他 DEB 都不能安装，先修复设备本身的 dpkg/Cydia。
C. 兼容版 gzip 数据包已经保留 iOS 6+ 的 armv7 原版程序，且安装后处理失败不阻断 dpkg 配置。
D. 备用文件 Surf-iPhone4S-iOS8-manual-fix2.zip 提供纯 App 备份。
   只有在 DEB 安装失败且熟悉越狱目录权限时使用，解压 Payload/Surf.app 到
   /Applications/Surf.app，保持目录 755、二进制 755，然后注销桌面。
   手动备份包不含 updater/安装脚本，推荐优先安装 DEB。

【哪些内容已经校验】
DEB 包架构 iphoneos-arm、gzip control/data、root 权限、更新助手 setuid 模式、
原始 Surf 主程序逐字节一致、官方 SHA256、版本与最小 iOS 6.0 设置、脚本语法均通过检查。

【尚需真机验证】
此机器 iOS 8.4.1 上能否正常安装与启动，连通 Surf 后 Douyin 是否允许正常播放。
Surf 主要硬件测试在初代 iPad mini（iOS 6.1.3）；iPhone 4S 官方标注 Legacy candidate。
该方案要求电脑开机并且联网。网页访问、账号验证或地区限制无法保证。

官方项目与来源：https://github.com/seg6/surf
安装修复包仅对发行封装及安装后脚本进行兼容修改。Surf 本体保留官方代码。
