# 小斐 Agent · iPhone 4S / iOS 8.4.1

目标：将简体中文 AI 客户端编译为适用于 **iPhone 4S、iOS 8.4.1、armv7、rootful 越狱** 的 `.deb` 安装包。

## 自动编译

在 **Actions → Build iOS 8 rootful DEB** 查看构建结果。成功后进入运行记录的 **Artifacts** 下载 `xiaofei-agent-rootful-deb`，解压后取得 `.deb`。

**状态说明：** 源代码处于实验阶段，生成包后仍需要 iPhone 4S 实机验证。AI 运算由局域网 Windows 服务端完成。请勿在仓库中提交任何 API Key 或手机密码。

源代码与 Windows 服务端来自之前对话的 V0.2 实验工程，构建使用 Theos + iPhoneOS9.3 SDK，目标 armv7，最低 iOS 8.0。

⚠️ 注意：此仓库虽然命名为 Private，GitHub 实际标识为 **Public（公开仓库）**。