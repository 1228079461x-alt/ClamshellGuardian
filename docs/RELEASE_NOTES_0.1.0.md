# 合盖守护 0.1.0 Beta

首个可审计公开测试版，面向 macOS 14+ 的 Apple Silicon Mac。

主要功能：

- 固定 60 分钟整机闭盖守护，适用于任意应用与后台进程。
- 15 秒失联恢复、15% 电量截止和系统严重热压力截止。
- 可选的连续离线 10 分钟截止；默认开启，可在开始前关闭。
- 不要求 Codex、ChatGPT、iPhone、Reminders 或 Macs Fan Control。
- 缺失 `/Library/LaunchDaemons` 时，首次安装会重建标准目录。

本机构建与自动策略测试已在 M1 MacBook Pro、macOS 27.0 上通过。代码和二进制均面向 `arm64`，但其他 M 系列尚未逐款进行真实闭盖验证。

重要：此附件为 ad-hoc 签名、未经 Apple 公证的 Beta。首次打开可能被 Gatekeeper 阻止；请只从本 Release 下载并核对 `SHA256SUMS.txt`。正式 Developer ID 签名、公证和 `SMAppService` 迁移仍需要 Apple Developer 证书与完整 Xcode。

闭盖运行时只能把 Mac 放在坚硬、通风的桌面上，绝对不要放入包或其他封闭空间。
