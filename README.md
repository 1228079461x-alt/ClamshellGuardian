# 合盖守护（ClamshellGuardian）

**完成首次安装后，在 Apple Silicon MacBook 上点击一次“开始”，接下来的 60 分钟内合上屏幕，Mac 不睡眠，已经运行的应用、终端命令和后台任务继续工作。**

合盖后屏幕会熄灭；再次开盖时，macOS 可能要求输入登录密码。这只是系统锁屏，不代表电脑刚才睡眠，也不会中断守护中的任务。

> 当前版本：**0.1.1 Beta**。本应用会临时改变系统睡眠策略。只能在坚硬、通风的桌面上使用，绝对不要把运行中的合盖 Mac 放进包、床铺、抽屉或其他封闭空间。

## 30 秒上手

1. 在 [v0.1.1 Release](https://github.com/1228079461x-alt/ClamshellGuardian/releases/tag/v0.1.1) 下载 `ClamshellGuardian-0.1.1-arm64-beta.zip`。
2. 解压，把“合盖守护.app”拖进“应用程序”。
3. 打开应用，点击 **“开始 60 分钟守护”**。
4. 首次使用时输入管理员密码，安装安全 Helper；保持上盖打开，等待 10 秒兼容性测试完成。
5. 只有看到绿色 **“✓ 可以合盖”** 和倒计时后再合盖。
6. 想提前结束时，打开菜单栏盾牌，点击 **“立即停止”**。

当前 Beta 未经 Apple 公证。若首次打开被 Gatekeeper 阻止，请按照 Apple 的[安全打开说明](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac)操作，并只从本仓库 Release 下载文件、核对随附的 `SHA256SUMS.txt`。

## 合盖后会发生什么

| 情况 | 实际行为 |
|---|---|
| 合上 MacBook | 屏幕立即熄灭，Mac 保持运行；不是关机，也不是只保活某一个应用。 |
| Codex、Claude Code、Chrome 或其他应用正在运行 | 都可以继续运行，应用没有“Codex 专用”限制。 |
| 再次打开上盖 | 屏幕点亮，60 分钟倒计时继续；是否要求密码由 macOS“锁定屏幕”设置决定。 |
| 原有 Wi‑Fi 正常 | 继续使用原有 Wi‑Fi，不会主动改用 iPhone 热点。 |
| Wi‑Fi 中断 | 应用不会自行连接热点或保存密码；macOS 可按自己的“自动加入热点”设置尝试连接。 |
| 守护达到 60 分钟 | 恢复普通合盖睡眠；若当时仍合盖，Mac 随即睡眠。 |
| 手动停止 | 立即恢复普通睡眠策略；不会关闭正在运行的应用。 |

打开“需要持续联网”时（默认开启），连续离线 10 分钟会提前结束守护并恢复睡眠。只运行本地任务、不希望断网导致停止时，请在启动前取消勾选它。

## 它会保护什么

- 固定运行 60 分钟，不能通过重复打开应用延长截止时间。
- 应用每 5 秒联系 Helper；应用崩溃、被强制退出或失联后，Helper 最迟约 15 秒恢复正常睡眠。
- 使用电池且电量降到 15% 时结束；连接电源时不受这个电量条件限制。
- 系统热状态达到 `serious` 或 `critical` 时结束。
- Helper 每次检测到合盖都会请求显示器休眠，但不会永久修改屏幕亮度。
- 会话结束后恢复 `SleepDisabled=No`；若本来已有其他软件开启该状态，本应用拒绝接管。

## 它不会做什么

- **不保证网络永远可用。** 路由器、运营商、iPhone 热点或在线服务中断仍会造成断网。
- **不主动连接或一直使用手机热点。** 热点切换由 macOS 负责；主 Wi‑Fi 正常时不会因为本应用消耗手机流量。
- **不控制风扇。** 不要求 Macs Fan Control，也不承诺温度或风扇转速；系统热状态截止只是额外保护。
- **不让关机后的电脑继续工作。** 它只防止已开机的 Mac 因合盖而睡眠。
- **不能只关闭内置屏幕。** `pmset displaysleepnow` 会让当时连接的显示器一起休眠。
- 不读取聊天、项目文件或浏览记录，不请求提醒事项、iCloud、辅助功能、录屏或定位权限，也不含遥测。

## 常见问题

### 开盖后为什么要输入密码？

应用在合盖时关闭显示器。若 macOS 设置为“显示器关闭后立即需要密码”，开盖就会进入锁屏界面。这是正常的安全行为，不表示 Mac 在合盖期间睡眠。可在“系统设置 → 锁定屏幕”中延长需要密码的时间，但会降低安全性。

### 怎样确认已经可以合盖？

以应用界面的绿色 **“✓ 可以合盖”** 和倒计时为准。也可以在终端执行：

```sh
pmset -g | grep -i SleepDisabled
```

守护中应显示 `SleepDisabled 1` 或 `SleepDisabled=Yes`；停止后应恢复为 `0` 或 `No`。

### 为什么固定为 60 分钟？

这是当前版本的硬性安全上限。即使界面卡住或客户端发送异常请求，Helper 也不会接受更长的截止时间。

### 这是 Amphetamine 的替代品吗？

不是完整替代。Amphetamine 是功能更丰富的通用防睡眠工具；合盖守护只做“一次点击、固定 60 分钟、到期自动恢复”的窄场景，并额外设置电量、热状态和崩溃恢复条件。

## 兼容性与已验证范围

| 项目 | 范围 |
|---|---|
| 处理器 | Apple Silicon `arm64`（M1 及后续 M 系列） |
| 系统 | macOS 14 或更高版本 |
| 已完成验证 | M1 MacBook Pro、macOS 27.0：同版本代码通过安装与真实合盖测试（熄屏、保持运行、开盖恢复）；Release 包通过 CI 构建和策略测试 |
| 尚待社区验证 | 其他 M 系列机型的真实合盖行为 |

代码没有型号白名单，但不同机型和未来 macOS 版本仍可能有差异。首次安装的 10 秒测试只验证当前系统能正确开启并恢复睡眠开关；它不能代替真实合盖测试。首次使用建议接电，在通风桌面上进行一次短时间测试。

## 卸载与紧急恢复

正常卸载：打开菜单栏盾牌，选择“卸载管理员组件与数据…”。应用会先停止会话、恢复 `SleepDisabled=No`，再删除 LaunchDaemon、Helper 和本地运行报告。

如果应用无法打开，执行：

```sh
sudo /usr/bin/pmset -a disablesleep 0
pmset -g | grep -i SleepDisabled
```

确认结果为 `0`/`No` 后，Mac 才恢复普通合盖睡眠。在确认恢复前不要把电脑放进包中。详细说明见 [SECURITY.md](SECURITY.md) 与 [docs/UNINSTALL.md](docs/UNINSTALL.md)。

## 从源码构建

需要 macOS、Command Line Tools 和 Swift 5.10 或更高版本：

```sh
./scripts/build.sh
./scripts/package-release.sh
```

输出位于 `dist/`。构建脚本会运行策略测试，生成仅含 `arm64` 的应用，执行 ad-hoc 签名并验证包结构。构建过程不会安装 Helper、改变睡眠设置或自动执行真实合盖测试。

```sh
swift run ClamshellGuardianPolicyTests
```

## 实现与安全边界

普通 IOKit idle-sleep assertion 不能阻止合盖睡眠。本应用的 root Helper 使用固定绝对路径调用 `pmset -a disablesleep 1/0`，合盖时调用 `pmset displaysleepnow`；应用同时持有公开的 `PreventUserIdleSystemSleep` assertion。Helper 只接受安装用户通过受限 Unix socket 发来的 `start`、`heartbeat`、`stop` 和 `status` 消息，不执行客户端提供的 shell 命令或路径。

`disablesleep` 并非 `pmset` 手册公开列出的稳定接口。macOS 更新可能使它失效，因此兼容性测试失败时应用会拒绝启动。当前 Beta 使用传统 LaunchDaemon，且只有 ad-hoc 签名；正式公开分发仍需要 Apple Developer ID、公证，并迁移到 `SMAppService`。详见 [架构说明](docs/ARCHITECTURE.md) 和[签名与公证说明](docs/SIGNING_AND_NOTARIZATION.md)。

## 许可证

仓库尚未选择开源许可证。代码可供查看和审计；在维护者添加许可证前，默认版权规则适用。
