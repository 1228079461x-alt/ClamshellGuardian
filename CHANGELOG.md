# Changelog

## 0.1.1 Beta — 2026-09-04

- 修复合盖守护开启后显示器可能仍然点亮的问题。
- Helper 现在检测 `AppleClamshellState`，每次合盖主动执行一次 `pmset displaysleepnow`。
- 熄屏命令失败会重试；重新开盖后为下一次合盖重新待命。
- 不修改亮度值，避免开盖后遗留最低亮度。
- IPC 提升到 v2，确保升级时旧 Helper 会被替换。

## 0.1.0 Beta — 2026-09-03

- 首个独立公开 Beta。
- 固定 60 分钟整机闭盖守护，不绑定任何应用。
- 加入 15% 电量、系统热状态、15 秒心跳和崩溃恢复保护。
- 加入可关闭的 10 分钟断网保护。
- 移除 Codex、ChatGPT、iPhone 热点、Reminders 与 Macs Fan Control 的强制依赖。
- 构建为 macOS 14+、Apple Silicon `arm64` 应用。
