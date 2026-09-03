import AppKit
import Foundation

final class ControlWindowController: NSWindowController, NSWindowDelegate {
    private let onToggle: () -> Void
    private let onShowLastReport: () -> Void
    private let onNetworkSafetyChanged: (Bool) -> Void

    private let statusLabel = NSTextField(labelWithString: "未运行")
    private let statusDetail = NSTextField(wrappingLabelWithString: "点击下方按钮开始固定 60 分钟守护。")
    private let remainingValue = NSTextField(labelWithString: "—")
    private let batteryValue = NSTextField(labelWithString: "—")
    private let networkValue = NSTextField(labelWithString: "—")
    private let scopeValue = NSTextField(labelWithString: "所有应用与后台进程")
    private let displayValue = NSTextField(labelWithString: "合盖后立即关闭")
    private let thermalValue = NSTextField(labelWithString: "—")
    private let lidValue = NSTextField(labelWithString: "不可合盖（尚未启动）")
    private let toggleButton = NSButton(title: "开始 60 分钟守护", target: nil, action: nil)
    private let reportButton = NSButton(title: "查看上次运行报告…", target: nil, action: nil)
    private let networkSafetyCheckbox = NSButton(
        checkboxWithTitle: "需要持续联网（连续离线 10 分钟后结束）",
        target: nil,
        action: nil
    )

    init(
        onToggle: @escaping () -> Void,
        onShowLastReport: @escaping () -> Void,
        onNetworkSafetyChanged: @escaping (Bool) -> Void
    ) {
        self.onToggle = onToggle
        self.onShowLastReport = onShowLastReport
        self.onNetworkSafetyChanged = onNetworkSafetyChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 610),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "合盖守护"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ snapshot: SessionSnapshot, isConfigured: Bool) {
        statusLabel.stringValue = snapshot.summary
        remainingValue.stringValue = isConfigured ? format(seconds: snapshot.remainingSeconds) : "—"
        batteryValue.stringValue = snapshot.batteryText
        networkValue.stringValue = snapshot.networkText
        scopeValue.stringValue = snapshot.scopeText
        thermalValue.stringValue = snapshot.thermalText
        lidValue.stringValue = snapshot.lidText
        networkSafetyCheckbox.state = snapshot.networkSafetyEnabled ? .on : .off
        networkSafetyCheckbox.isEnabled = snapshot.phase == .idle

        switch snapshot.phase {
        case .idle:
            statusLabel.textColor = .labelColor
            if isConfigured {
                statusDetail.stringValue = "尚未启动。点击下方按钮，检查通过后即可合盖运行。"
            } else {
                statusLabel.stringValue = "首次使用需进行 10 秒安全测试"
                statusDetail.stringValue = "点击下方按钮；测试通过后会自动记住设置并继续启动守护，无需再找其他按钮。"
            }
            toggleButton.title = "开始 60 分钟守护"
            toggleButton.isEnabled = true
        case .preparing:
            statusLabel.textColor = .systemOrange
            statusLabel.stringValue = "请保持开盖"
            statusDetail.stringValue = snapshot.networkSafetyEnabled
                ? "正在确认 Helper、防睡眠状态、电量、温度与互联网连接…"
                : "正在确认 Helper、防睡眠状态、电量与温度…"
            toggleButton.title = "取消启动"
            toggleButton.isEnabled = true
        case .active:
            if !snapshot.networkSafetyEnabled || snapshot.networkText == "正常" {
                statusLabel.stringValue = "✓ 可以合盖"
                statusLabel.textColor = .systemGreen
                statusDetail.stringValue = "Helper 已确认整机防睡眠开启；合盖后会立即关闭显示器，所有应用与后台进程继续运行。"
            } else {
                statusLabel.textColor = .systemOrange
                statusDetail.stringValue = "防睡眠仍在工作，正在等待现有 Wi‑Fi 或 macOS 的热点回退恢复网络。"
            }
            toggleButton.title = "立即停止守护"
            toggleButton.isEnabled = true
        case .stopping:
            statusLabel.textColor = .secondaryLabelColor
            statusDetail.stringValue = "正在恢复正常合盖睡眠策略…"
            toggleButton.title = "正在停止…"
            toggleButton.isEnabled = false
        }
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let image = NSImageView(image: NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "合盖守护") ?? NSImage())
        image.contentTintColor = .systemBlue
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .semibold)

        let title = NSTextField(labelWithString: "合盖守护")
        title.font = .systemFont(ofSize: 28, weight: .bold)

        let subtitle = NSTextField(wrappingLabelWithString: "固定守护 60 分钟，让所有应用与后台进程在合盖后继续运行。")
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor

        let titleText = NSStackView(views: [title, subtitle])
        titleText.orientation = .vertical
        titleText.alignment = .leading
        titleText.spacing = 3

        let header = NSStackView(views: [image, titleText])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        statusLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        statusDetail.font = .systemFont(ofSize: 13)
        statusDetail.textColor = .secondaryLabelColor
        statusDetail.maximumNumberOfLines = 0

        let statusStack = NSStackView(views: [statusLabel, statusDetail])
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 5

        let statusPanel = NSVisualEffectView()
        statusPanel.material = .contentBackground
        statusPanel.blendingMode = .withinWindow
        statusPanel.state = .active
        statusPanel.wantsLayer = true
        statusPanel.layer?.cornerRadius = 10
        statusPanel.layer?.borderWidth = 1
        statusPanel.layer?.borderColor = NSColor.separatorColor.cgColor
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusPanel.addSubview(statusStack)
        NSLayoutConstraint.activate([
            statusStack.leadingAnchor.constraint(equalTo: statusPanel.leadingAnchor, constant: 16),
            statusStack.trailingAnchor.constraint(equalTo: statusPanel.trailingAnchor, constant: -16),
            statusStack.topAnchor.constraint(equalTo: statusPanel.topAnchor, constant: 13),
            statusStack.bottomAnchor.constraint(equalTo: statusPanel.bottomAnchor, constant: -13)
        ])

        let grid = NSGridView(views: [
            [makeCaption("剩余时间"), remainingValue],
            [makeCaption("电量"), batteryValue],
            [makeCaption("网络"), networkValue],
            [makeCaption("运行范围"), scopeValue],
            [makeCaption("显示器"), displayValue],
            [makeCaption("热状态"), thermalValue],
            [makeCaption("合盖状态"), lidValue]
        ])
        grid.rowSpacing = 9
        grid.columnSpacing = 24
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        toggleButton.target = self
        toggleButton.action = #selector(toggleGuardian)
        toggleButton.bezelStyle = .rounded
        toggleButton.controlSize = .large
        toggleButton.font = .systemFont(ofSize: 16, weight: .semibold)
        toggleButton.keyEquivalent = "\r"
        toggleButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        reportButton.target = self
        reportButton.action = #selector(showLastReport)
        reportButton.bezelStyle = .inline
        reportButton.controlSize = .small

        networkSafetyCheckbox.target = self
        networkSafetyCheckbox.action = #selector(networkSafetyDidChange)
        networkSafetyCheckbox.font = .systemFont(ofSize: 13)

        let hotspotNote = NSTextField(wrappingLabelWithString:
            "可选网络保护只检测通用互联网连接，不会主动连接热点或保存 Wi‑Fi 信息。若需要热点后备，请使用 macOS 自带的自动加入功能。"
        )
        hotspotNote.font = .systemFont(ofSize: 12)
        hotspotNote.textColor = .secondaryLabelColor
        hotspotNote.maximumNumberOfLines = 0

        let safetyNote = NSTextField(wrappingLabelWithString:
            "安全：合盖后 Helper 会立即让显示器休眠，不修改亮度值。仅在坚硬、通风的桌面上使用；到期、低电量或严重过热时会恢复正常睡眠。"
        )
        safetyNote.font = .systemFont(ofSize: 12, weight: .medium)
        safetyNote.textColor = .systemOrange
        safetyNote.maximumNumberOfLines = 0

        let stack = NSStackView(views: [header, statusPanel, grid, networkSafetyCheckbox, toggleButton, reportButton, hotspotNote, safetyNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 42),
            image.heightAnchor.constraint(equalToConstant: 42),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -26),
            statusPanel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            toggleButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hotspotNote.widthAnchor.constraint(equalTo: stack.widthAnchor),
            safetyNote.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func makeCaption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13, weight: .medium)
        return label
    }

    @objc private func toggleGuardian() {
        onToggle()
    }

    @objc private func showLastReport() {
        onShowLastReport()
    }

    @objc private func networkSafetyDidChange() {
        onNetworkSafetyChanged(networkSafetyCheckbox.state == .on)
    }

    private func format(seconds: Int) -> String {
        guard seconds > 0 else { return "60:00（启动后）" }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
