# 签名、公证与正式发行

## 0.1.0 Beta 的状态

当前构建环境没有 Developer ID 证书与完整 Xcode，因此 0.1.0 使用 ad-hoc 签名，未提交 Apple 公证。它适合源码审计和 Beta 测试，但 Gatekeeper 会提示开发者身份无法验证。

## 正式发行要求

1. 安装完整 Xcode，并加入 Apple Developer Program。
2. 为主应用和 Helper 配置唯一 App ID、Developer ID Application 证书及 hardened runtime。
3. 把 LaunchDaemon 放入应用的 `Contents/Library/LaunchDaemons`，使用 `SMAppService.daemon(plistName:)` 注册，而不是 Beta 的 AppleScript 安装流程。
4. 使用 XPC/audit token 或等价的受限接口识别授权用户，并保留 3600 秒硬上限、15 秒看门狗与状态所有权规则。
5. 归档、Developer ID 签名、运行 `notarytool`、staple 公证票据，然后在干净用户账户上验证安装/卸载。
6. 在至少一台 M1、一台后续 Pro/Max 芯片和一台无风扇 MacBook Air 上完成真实闭盖验收。

Apple 要求通过 `SMAppService` 随应用分发的 LaunchDaemon 使用有效签名并进行公证。相关资料：[ServiceManagement](https://developer.apple.com/documentation/servicemanagement)、[Developer ID](https://developer.apple.com/support/developer-id/)、[公证 macOS 软件](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

在上述步骤完成前，不应把 Beta 标注为“已签名/已公证正式版”，也不应声称所有 M 系列均已实机验证。
