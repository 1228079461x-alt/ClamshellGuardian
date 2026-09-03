# Security Policy

## 使用风险

本应用会临时禁用合盖睡眠。错误使用可能造成耗电、发热或设备在密闭空间内持续运行。只在坚硬、通风的桌面上使用，并在离开前确认绿色状态与倒计时；不要把处于守护状态的电脑放进包中。

系统固件仍保留最终热保护权。应用不会调节风扇，也不承诺温度或 RPM；`serious`/`critical` 截止是额外保护，不是散热条件不良时继续运行的保证。

## 权限模型

- root Helper 只接受安装用户 UID 通过 `0600` Unix socket 发来的四种版本化消息。
- Helper 不接受任意命令、路径或 shell 参数。
- 会话最长 3600 秒，不能通过心跳续期。
- 应用失联 15 秒、电池不高于 15%（未充电）、严重热压力或到期均会恢复睡眠。
- 已被其他软件设置的 `SleepDisabled=Yes` 不会被本应用接管。

## Beta 分发说明

0.1.0 Release 是 ad-hoc 签名、未公证的 Beta。使用前请从本仓库 Release 下载并核对 SHA-256。正式公开分发需要 Apple Developer ID 与公证；当前构建不能冒充已被 Apple 验证的软件。

## 报告漏洞

请通过 GitHub Security Advisory 私下报告可导致任意 root 命令执行、越权控制 Helper、无法恢复 `SleepDisabled` 或绕过硬截止时间的问题。报告中请包含 macOS 版本、Mac 型号、复现步骤和相关日志，但不要提交密码、序列号或私人项目内容。

## 紧急恢复

```sh
sudo /usr/bin/pmset -a disablesleep 0
```

随后运行 `pmset -g | grep -i SleepDisabled`，确认值为 `0`/`No`。
