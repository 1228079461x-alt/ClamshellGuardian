# 安全架构与审计说明

## 组件边界

- `ClamshellGuardianApp`：无 root 权限的 AppKit 菜单栏应用，负责 UI、预检、可选网络监控、5 秒心跳、idle-sleep assertion 与最近一次运行报告。它不枚举、选择或限制被保护的应用。
- `ClamshellGuardianHelper`：root LaunchDaemon，只接受有限 IPC、切换 `pmset` 并独立执行硬安全截止。
- `ClamshellGuardianCore`：无特权的纯 Swift 策略和 Codable IPC 模型，由应用、Helper 与测试共用。

## IPC 边界

Unix socket 固定为 `/var/run/com.xufeiyang.clamshellguardian.sock`，权限 `0600`，owner 是安装时的用户。Helper 使用 `getpeereid` 再次核对 peer UID。每个请求最多 16 KiB，读写超时 2 秒，只接受协议版本 2 的 `start`、`heartbeat`、`stop` 和 `status`。0.1.1 提升协议版本，确保旧版 Helper 不会被误认为已包含主动熄屏修复。

Helper 不接受 shell 文本、程序路径、环境变量或任意参数。`start` 的 deadline 必须晚于当前时间且不超过 3600 秒；会话 ID 由应用生成，后续心跳必须完全匹配。

## SleepDisabled 所有权

Helper 开始前要求系统 `SleepDisabled` 为 false；如果其他软件已经设置为 true，它会拒绝覆盖。切换前先写入 `/var/db/com.xufeiyang.clamshellguardian.session.json`。Helper 启动时只有检测到自己的 root-owned 标记才会清理遗留状态。

Helper 每 0.5 秒独立检查时间、电量、系统热状态和心跳。应用崩溃或 `kill -9` 后，最后心跳达到 15 秒即恢复睡眠。所有停止路径先执行 `pmset -a disablesleep 0`；若上盖仍关闭，再调用 `pmset sleepnow`。恢复失败时状态标记保留，watchdog 会继续重试。

守护期间，Helper 同一轮 watchdog 读取 `AppleClamshellState`。每次从开盖转为合盖时，它通过绝对路径执行一次 `pmset displaysleepnow`；命令失败则在后续轮次重试，重新开盖后状态机重新待命。应用不修改亮度，因此不会在开盖后遗留最低亮度。

## 可选网络策略

网络保护默认开启，但不是系统级 Helper 的启动门槛。开启时，应用用 `NWPathMonitor` 观察路径，并每 30 秒尝试与 Apple 或 Cloudflare 的 443/TLS 端点建立连接。连续离线 10 分钟后，应用请求 Helper 停止。关闭后不启动网络监控，也不会因离线终止会话。

应用不选择 Wi‑Fi、不主动加入热点、不读取或记录 SSID 与密码。热点回退完全由 macOS 自身策略决定。

## 数据与权限

运行状态及最近一次报告保存在 `~/Library/Application Support/合盖守护/`。数据只包括会话 ID、时间、电量、热状态、是否启用网络保护、离线统计、是否观察到合盖及停止原因；不记录进程列表、聊天内容、命令、项目文件、SSID 或密码。

Beta 只请求安装/卸载 Helper 所需的管理员授权。它不请求 Reminders、iCloud、Accessibility、Screen Recording、Location 或网络扩展权限，也不依赖 Codex、ChatGPT 或 Macs Fan Control。

## 分发架构

0.1.1 Beta 使用 ad-hoc 签名与传统 LaunchDaemon 安装，以便在没有开发者证书的环境中构建和审计。正式发行的目标结构是 Developer ID 签名、公证，并以 `SMAppService` 注册 app-bundled LaunchDaemon。两者不能被描述为同等信任级别，详见 `docs/SIGNING_AND_NOTARIZATION.md`。
