import AppKit
import ClamshellGuardianCore
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let setupCompletedKey = "guardian.setupCompleted.v1"

    private let installer = HelperInstaller()
    private let reportStore = SessionReportStore()
    private lazy var session = SessionController()
    private var setupWindow: SetupWindowController?
    private var controlWindow: ControlWindowController?
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let summaryItem = NSMenuItem(title: "未运行", action: nil, keyEquivalent: "")
    private let remainingItem = NSMenuItem(title: "剩余时间：—", action: nil, keyEquivalent: "")
    private let batteryItem = NSMenuItem(title: "电量：—", action: nil, keyEquivalent: "")
    private let networkItem = NSMenuItem(title: "网络：—", action: nil, keyEquivalent: "")
    private let scopeItem = NSMenuItem(title: "运行范围：所有应用与后台进程", action: nil, keyEquivalent: "")
    private let thermalItem = NSMenuItem(title: "热状态：—", action: nil, keyEquivalent: "")
    private let lidItem = NSMenuItem(title: "合盖状态：不可合盖（尚未启动）", action: nil, keyEquivalent: "")
    private let networkSafetyItem = NSMenuItem(
        title: "需要持续联网（离线 10 分钟后结束）",
        action: nil,
        keyEquivalent: ""
    )
    private let toggleItem = NSMenuItem(title: "开始 60 分钟守护", action: nil, keyEquivalent: "")
    private var lastSnapshot: SessionSnapshot?
    private var quitAfterStop = false
    private var startAfterSetupRequested = false
    private var helperReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        helperReady = installer.isCurrentVersionInstalled
        configureMenuBar()
        configureSessionCallbacks()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.showControlWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.stopSynchronouslyForTermination()
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shield", accessibilityDescription: "合盖守护")
            button.imagePosition = .imageLeading
            button.toolTip = "合盖守护"
        }

        menu.delegate = self
        for item in [summaryItem, remainingItem, batteryItem, networkItem, scopeItem, thermalItem, lidItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        networkSafetyItem.target = self
        networkSafetyItem.action = #selector(toggleNetworkSafety)
        menu.addItem(networkSafetyItem)

        let showWindow = NSMenuItem(title: "显示控制窗口", action: #selector(showControlWindowAction), keyEquivalent: "")
        showWindow.target = self
        menu.addItem(showWindow)

        toggleItem.target = self
        toggleItem.action = #selector(toggleGuardian)
        menu.addItem(toggleItem)

        let report = NSMenuItem(title: "查看上次运行报告…", action: #selector(showLastSessionReport), keyEquivalent: "")
        report.target = self
        menu.addItem(report)

        let wifi = NSMenuItem(title: "打开 Wi‑Fi 设置（可选）", action: #selector(openWiFiSettings), keyEquivalent: "")
        wifi.target = self
        menu.addItem(wifi)

        menu.addItem(.separator())
        let setup = NSMenuItem(title: "重新运行首次设置…", action: #selector(showSetupAction), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
        let uninstall = NSMenuItem(title: "卸载管理员组件与数据…", action: #selector(uninstall), keyEquivalent: "")
        uninstall.target = self
        menu.addItem(uninstall)
        let quit = NSMenuItem(title: "退出合盖守护", action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        updateMenu(session.currentSnapshot())
    }

    private func configureSessionCallbacks() {
        session.onSnapshot = { [weak self] snapshot in
            self?.updateMenu(snapshot)
        }
        session.onStartFailure = { [weak self] error in
            self?.showControlWindow()
            self?.showAlert(title: "守护未启动", message: error.localizedDescription)
        }
        session.onEnded = { [weak self] reason, details in
            guard let self else { return }
            if self.quitAfterStop {
                NSApp.terminate(nil)
                return
            }
            self.summaryItem.title = "已结束：\(reason.chineseDescription)"
            self.statusItem.button?.toolTip = "\(reason.chineseDescription)。\(details)"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenu(lastSnapshot ?? session.currentSnapshot())
    }

    @objc private func toggleGuardian() {
        if session.isActiveOrPreparing {
            session.stop(reason: .manual)
        } else {
            beginGuardian()
        }
    }

    private func beginGuardian() {
        helperReady = installer.isCurrentVersionInstalled
        guard UserDefaults.standard.bool(forKey: Self.setupCompletedKey), helperReady else {
            startAfterSetupRequested = true
            showSetup()
            return
        }
        session.start()
    }

    private func showControlWindow() {
        if controlWindow == nil {
            controlWindow = ControlWindowController(
                onToggle: { [weak self] in self?.toggleGuardian() },
                onShowLastReport: { [weak self] in self?.showLastSessionReport() },
                onNetworkSafetyChanged: { [weak self] enabled in
                    self?.setNetworkSafety(enabled)
                }
            )
        }
        controlWindow?.update(
            lastSnapshot ?? session.currentSnapshot(),
            isConfigured: UserDefaults.standard.bool(forKey: Self.setupCompletedKey) && helperReady
        )
        NSApp.activate(ignoringOtherApps: true)
        controlWindow?.showWindow(nil)
        controlWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func showControlWindowAction() {
        showControlWindow()
    }

    private func showSetup() {
        if setupWindow == nil {
            setupWindow = SetupWindowController { [weak self] in
                guard let self else { return }
                let shouldStart = self.startAfterSetupRequested
                self.startAfterSetupRequested = false
                self.helperReady = true
                self.setupWindow = nil
                self.showControlWindow()
                if shouldStart {
                    self.session.start()
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.showWindow(nil)
        setupWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func showSetupAction() {
        guard !session.isActiveOrPreparing else {
            showAlert(title: "请先停止守护", message: "首次设置测试会切换系统睡眠状态，不能与当前会话同时运行。")
            return
        }
        startAfterSetupRequested = false
        showSetup()
    }

    @objc private func openWiFiSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func uninstall() {
        guard !session.isActiveOrPreparing else {
            showAlert(title: "请先停止守护", message: "停止当前守护后再卸载管理员组件。")
            return
        }
        let alert = NSAlert()
        alert.messageText = "卸载合盖守护组件？"
        alert.informativeText = "将先恢复 SleepDisabled=No，再移除 Helper、LaunchDaemon 和应用会话数据。应用本身不会被删除。"
        alert.addButton(withTitle: "卸载")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.installer.uninstall()
                DispatchQueue.main.async {
                    UserDefaults.standard.removeObject(forKey: Self.setupCompletedKey)
                    AppStateStore().clear()
                    self.reportStore.clear()
                    if let bundleIdentifier = Bundle.main.bundleIdentifier {
                        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
                    }
                    self.showAlert(title: "卸载完成", message: "SleepDisabled 已恢复，管理员组件和应用会话数据已移除。")
                }
            } catch {
                DispatchQueue.main.async {
                    self.showAlert(title: "卸载失败", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func quitApplication() {
        if session.isActiveOrPreparing {
            quitAfterStop = true
            session.stop(reason: .applicationTerminating)
        } else {
            NSApp.terminate(nil)
        }
    }

    private func updateMenu(_ snapshot: SessionSnapshot) {
        lastSnapshot = snapshot
        summaryItem.title = snapshot.summary
        remainingItem.title = "剩余时间：\(format(seconds: snapshot.remainingSeconds))"
        batteryItem.title = "电量：\(snapshot.batteryText)"
        networkItem.title = "网络：\(snapshot.networkText)"
        scopeItem.title = "运行范围：\(snapshot.scopeText)"
        thermalItem.title = "热状态：\(snapshot.thermalText)"
        lidItem.title = "合盖状态：\(snapshot.lidText)"
        networkSafetyItem.state = snapshot.networkSafetyEnabled ? .on : .off
        networkSafetyItem.isEnabled = snapshot.phase == .idle
        let isConfigured = UserDefaults.standard.bool(forKey: Self.setupCompletedKey) && helperReady
        switch snapshot.phase {
        case .idle:
            toggleItem.title = "开始 60 分钟守护"
            toggleItem.isEnabled = true
        case .preparing:
            toggleItem.title = "取消启动"
            toggleItem.isEnabled = true
        case .active:
            toggleItem.title = "立即停止"
            toggleItem.isEnabled = true
        case .stopping:
            toggleItem.title = "正在停止…"
            toggleItem.isEnabled = false
        }
        controlWindow?.update(snapshot, isConfigured: isConfigured)

        switch snapshot.phase {
        case .active:
            statusItem.button?.image = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "守护中")
            statusItem.button?.title = " " + format(seconds: snapshot.remainingSeconds)
        case .preparing, .stopping:
            statusItem.button?.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "处理中")
            statusItem.button?.title = " …"
        case .idle:
            statusItem.button?.image = NSImage(systemSymbolName: "shield", accessibilityDescription: "未运行")
            statusItem.button?.title = ""
        }
    }

    @objc private func toggleNetworkSafety() {
        guard !session.isActiveOrPreparing else { return }
        setNetworkSafety(!GuardianPreferences.networkSafetyEnabled)
    }

    private func setNetworkSafety(_ enabled: Bool) {
        guard !session.isActiveOrPreparing else { return }
        GuardianPreferences.networkSafetyEnabled = enabled
        session.preferencesDidChange()
    }

    private func format(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    @objc private func showLastSessionReport() {
        guard let report = reportStore.load() else {
            showAlert(title: "暂无运行报告", message: "完成或停止一次 60 分钟守护后，这里会保存最近一次结果。")
            return
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let duration = max(0, Int(report.endedAt.timeIntervalSince(report.startedAt).rounded()))
        let message = """
        开始：\(formatter.string(from: report.startedAt))
        结束：\(formatter.string(from: report.endedAt))
        实际运行：\(formatDuration(duration))
        结束原因：\(report.stopReason.chineseDescription)
        详情：\(report.details)

        电量：\(formatBattery(report.startBatteryPercent, onPower: report.startedOnPower)) → \(formatBattery(report.endBatteryPercent, onPower: report.endedOnPower))
        检测到合盖：\(report.lidClosedObserved ? "是" : "否")
        网络中断：\(report.networkInterruptionCount) 次；累计 \(formatDuration(report.totalOfflineSeconds))；最长 \(formatDuration(report.longestOfflineSeconds))
        断网保护：\(report.networkSafetyEnabled ? "开启（离线 10 分钟后结束）" : "关闭")
        保护范围：\(report.systemWideProtectionConfirmed ? "整机——所有应用与后台进程" : "未确认")
        最高热状态：\(thermalDescription(report.highestThermalLevel))
        屏幕：检测到合盖后，Helper 已主动请求显示器立即休眠；不会改变亮度设置
        """
        showAlert(title: "上次运行报告", message: message)
    }

    private func formatBattery(_ percent: Int?, onPower: Bool) -> String {
        let value = percent.map { "\($0)%" } ?? "未知"
        return "\(value)（\(onPower ? "接电" : "电池")）"
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func thermalDescription(_ level: ThermalLevel) -> String {
        switch level {
        case .nominal: return "正常"
        case .fair: return "轻微"
        case .serious: return "严重"
        case .critical: return "危险"
        case .unknown: return "未知"
        }
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = title.contains("失败") || title.contains("未启动") ? .warning : .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
