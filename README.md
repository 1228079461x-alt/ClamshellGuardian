# 合盖守护（ClamshellGuardian）

一个原生、中文、面向 Apple Silicon Mac 的菜单栏工具。在固定 60 分钟内阻止合盖睡眠，让整台 Mac 上已运行的应用、终端任务和后台进程继续工作。

> 当前为 **0.1.0 Beta**。它会改变系统级睡眠策略，请先阅读安全提示，并仅在坚硬、通风的桌面上使用。不要把运行中的合盖 Mac 放进包、床铺、抽屉或其他封闭空间。

## 它保护什么

- 保护整台电脑，不绑定 Codex、ChatGPT、Claude Code、Chrome 或任何指定应用。
- 固定 60 分钟，到期不可从客户端续长。
- 应用每 5 秒发送心跳；应用崩溃或被强制退出后，Helper 会在 15 秒内恢复正常睡眠策略。
- 使用电池且电量降到 15% 时停止；系统热状态达到 `serious` 或 `critical` 时停止。
- 可选“需要持续联网”：默认开启，连续离线 10 分钟时停止；关闭后不会因断网终止本地任务。
- 不接管风扇，不要求 Macs Fan Control。无风扇的 MacBook Air 也不会因此被拒绝。
- 不请求提醒事项、iCloud、辅助功能、录屏或定位权限；不含遥测。

屏幕不会被强制点亮。MacBook 合盖后显示面板由系统关闭，因此无需把亮度写成最低值，也不会把低亮度残留到下一次开盖。

## 兼容性

| 项目 | 范围 |
|---|---|
| 处理器 | Apple Silicon `arm64`（M1 及后续 M 系列） |
| 系统 | macOS 14 或更高版本 |
| 已完成的本机验证 | M1 MacBook Pro、macOS 27.0：编译、单元测试、包结构和签名验证 |
| 尚待社区验证 | 其他 M 系列型号上的真实闭盖行为 |

代码没有型号白名单，也不依赖某一代芯片的传感器名称，所以发行包面向所有 M 系列 Mac；但无法在未实际测试每一款硬件的情况下声称“每台机器保证通过”。首次设置会执行 10 秒兼容性测试，失败时拒绝进入闭盖模式。

## 下载与使用

1. 从 [Releases](https://github.com/1228079461x-alt/ClamshellGuardian/releases) 下载 `ClamshellGuardian-0.1.0-arm64-beta.zip`。
2. 解压后把“合盖守护.app”拖到“应用程序”。
3. 当前 Beta 尚未使用 Apple Developer ID 公证。首次打开如被 Gatekeeper 阻止，请按 Apple 的[安全打开说明](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac)操作；只应使用本仓库 Release，并核对 `SHA256SUMS.txt`。
4. 点击“开始 60 分钟守护”。第一次会请求管理员密码，安装受限 Helper 并执行 10 秒兼容性测试。
5. 只有界面显示绿色“✓ 可以合盖”和倒计时后才能合盖。
6. 再次打开应用只显示当前状态，不会延长已经开始的截止时间。

若任务必须联网，保持“需要持续联网”开启。主 Wi‑Fi 中断后，应用只会等待网络恢复；是否自动加入 iPhone 热点完全由 macOS 设置决定，应用不会主动连接热点、保存 SSID/密码或在 Wi‑Fi 正常时消耗热点流量。

## 安全恢复与卸载

菜单栏中选择“立即停止”会恢复正常睡眠。也可选择“卸载管理员组件与数据…”，其顺序为：停止会话、恢复 `SleepDisabled=No`、卸载 LaunchDaemon、删除 Helper 与本地报告。

如果界面或 Helper 状态异常，执行：

```sh
sudo /usr/bin/pmset -a disablesleep 0
pmset -g | grep -i SleepDisabled
```

结果应为 `SleepDisabled 0` 或 `SleepDisabled=No`。在确认恢复前不要把电脑放入包中。详细说明见 [SECURITY.md](SECURITY.md) 与 [docs/UNINSTALL.md](docs/UNINSTALL.md)。

## 从源码构建

需要 macOS、Command Line Tools 和 Swift 5.10 或更高版本：

```sh
./scripts/build.sh
./scripts/package-release.sh
```

输出位于 `dist/`。构建脚本会先运行策略测试，再生成仅含 `arm64` 的应用、创建图标、执行 ad-hoc 签名并验证包结构。它不会安装 Helper、切换睡眠状态或执行闭盖测试。

```sh
swift run ClamshellGuardianPolicyTests
```

测试覆盖：硬截止时间、15% 电量、热状态、15 秒心跳、可选的 10 分钟断网策略、Apple Silicon 架构、IPC UID、SleepDisabled 所有权和报告序列化。

## 技术与限制

普通 IOKit idle-sleep assertion 不能替代合盖策略。本应用的 root Helper 使用绝对路径调用 `pmset -a disablesleep 1/0`，应用本身同时持有公开的 `PreventUserIdleSystemSleep` assertion。`disablesleep` 没有出现在当前 `pmset` 手册中，属于未公开支持的系统开关；macOS 更新后兼容性测试失败时，应用会拒绝启用。

当前 Beta 采用管理员授权安装传统 LaunchDaemon。面向普通用户的正式发行版应使用 Apple Developer ID 签名、公证，并迁移到 `SMAppService`；原因和步骤见 [docs/SIGNING_AND_NOTARIZATION.md](docs/SIGNING_AND_NOTARIZATION.md)。

参考：[Apple IOKit 电源断言](https://developer.apple.com/documentation/iokit/iopmassertiontypes)、[ServiceManagement](https://developer.apple.com/documentation/servicemanagement)、[Developer ID](https://developer.apple.com/support/developer-id/)、[软件公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 许可证

仓库目前尚未选择开源许可证。代码可供审计；在维护者明确添加许可证前，默认版权规则仍然适用。
