import AppKit
import ClamshellGuardianCore
import Foundation

enum SetupError: LocalizedError {
    case compatibility(String)

    var errorDescription: String? {
        switch self {
        case .compatibility(let details):
            return "10 秒兼容性测试失败：\(details)"
        }
    }
}

final class SetupWindowController: NSWindowController, NSWindowDelegate {
    private let installer = HelperInstaller()
    private let helper = HelperClient()
    private let completion: () -> Void

    private let statusLabel = NSTextField(wrappingLabelWithString: "尚未开始")
    private let progress = NSProgressIndicator()
    private let startButton = NSButton(title: "安装安全组件并继续", target: nil, action: nil)
    private let wifiButton = NSButton(title: "打开 Wi‑Fi 设置（可选）", target: nil, action: nil)

    init(completion: @escaping () -> Void) {
        self.completion = completion

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 485),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "合盖守护 · 首次设置"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "合盖守护")
        title.font = .systemFont(ofSize: 28, weight: .bold)

        let subtitle = NSTextField(wrappingLabelWithString:
            "这是首次启动所需的一次性安全检查。测试通过后会自动返回主窗口并继续启动守护。"
        )
        subtitle.font = .systemFont(ofSize: 14)

        let checklist = NSTextField(wrappingLabelWithString:
            "设置将：\n" +
            "• 请求管理员权限安装受限 Helper\n" +
            "• 确认当前设备是 Apple Silicon（M 系列）Mac\n" +
            "• 用 10 秒测试确认 SleepDisabled 能开启并恢复\n" +
            "• 不安装 Codex、风扇软件或其他第三方依赖"
        )
        checklist.font = .systemFont(ofSize: 13)

        let warning = NSTextField(wrappingLabelWithString:
            "重要：测试时请保持上盖打开。实际闭盖运行只能放在坚硬、通风的桌面上，禁止放入包、床铺、抽屉或其他封闭空间。"
        )
        warning.textColor = .systemOrange
        warning.font = .systemFont(ofSize: 13, weight: .semibold)

        let hotspot = NSTextField(wrappingLabelWithString:
            "网络保护可在主窗口关闭。开启时只检测网络健康，不会主动连接热点或保存 Wi‑Fi 信息；如需热点后备，请自行使用 macOS 的自动加入功能。"
        )

        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false

        startButton.target = self
        startButton.action = #selector(startSetup)
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        if installer.isCurrentVersionInstalled {
            startButton.title = "运行 10 秒安全测试并继续"
        }

        wifiButton.target = self
        wifiButton.action = #selector(openWiFiSettings)

        let statusRow = NSStackView(views: [progress, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        let buttonRow = NSStackView(views: [startButton, wifiButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [
            title, subtitle, checklist, warning, hotspot, buttonRow, statusRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        subtitle.maximumNumberOfLines = 0
        checklist.maximumNumberOfLines = 0
        warning.maximumNumberOfLines = 0
        hotspot.maximumNumberOfLines = 0
        statusLabel.maximumNumberOfLines = 0
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28)
        ])
    }

    @objc private func startSetup() {
        bringToFront()
        startButton.isEnabled = false
        statusLabel.textColor = .labelColor
        progress.startAnimation(nil)
        if installer.isCurrentVersionInstalled {
            runCompatibilityTest()
            return
        }

        statusLabel.stringValue = "正在请求管理员权限并安装或更新 Helper…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.installer.install()
                DispatchQueue.main.async {
                    self.bringToFront()
                    self.runCompatibilityTest()
                }
            } catch {
                DispatchQueue.main.async { self.fail(error) }
            }
        }
    }

    private func runCompatibilityTest() {
        statusLabel.stringValue = "正在运行 10 秒 SleepDisabled 兼容性测试，请勿合盖…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.performCompatibilityTest()
                DispatchQueue.main.async {
                    self.bringToFront()
                    self.progress.stopAnimation(nil)
                    self.statusLabel.stringValue = "兼容性测试通过，正在进入主窗口…"
                    UserDefaults.standard.set(true, forKey: AppDelegate.setupCompletedKey)
                    UserDefaults.standard.synchronize()
                    self.close()
                    self.completion()
                }
            } catch {
                _ = self.helper.send(HelperRequest(command: .stop, reason: .compatibilityFailure))
                DispatchQueue.main.async { self.fail(error) }
            }
        }
    }

    private func performCompatibilityTest() throws {
        guard SystemChecks.isAppleSilicon else {
            throw SetupError.compatibility("当前版本仅支持 Apple Silicon（M 系列）Mac")
        }
        let sessionID = "setup-\(UUID().uuidString)"
        let deadline = Date().addingTimeInterval(10)
        guard let started = helper.send(HelperRequest(
            command: .start,
            sessionID: sessionID,
            deadline: deadline
        )), started.ok, started.active, started.sleepDisabled else {
            throw SetupError.compatibility("无法开启 SleepDisabled；可能已有其他软件占用该状态")
        }

        var nextHeartbeat = Date().addingTimeInterval(4)
        while Date() < deadline {
            if Date() >= nextHeartbeat {
                guard helper.send(HelperRequest(command: .heartbeat, sessionID: sessionID))?.ok == true else {
                    throw SetupError.compatibility("测试心跳失败")
                }
                nextHeartbeat = nextHeartbeat.addingTimeInterval(4)
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        let verificationDeadline = Date().addingTimeInterval(6)
        repeat {
            if let status = helper.send(HelperRequest(command: .status)),
               !status.active, !status.sleepDisabled {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < verificationDeadline
        throw SetupError.compatibility("到期后没有确认 SleepDisabled 恢复为 No")
    }

    private func fail(_ error: Error) {
        bringToFront()
        progress.stopAnimation(nil)
        statusLabel.stringValue = error.localizedDescription
        statusLabel.textColor = .systemRed
        startButton.title = "重试设置"
        startButton.isEnabled = true
    }

    @objc private func openWiFiSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.orderFrontRegardless()
        window?.makeKey()
    }
}
