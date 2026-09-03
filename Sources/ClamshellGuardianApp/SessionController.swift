import AppKit
import ClamshellGuardianCore
import Foundation

enum SessionPhase: Equatable {
    case idle
    case preparing
    case active
    case stopping
}

struct SessionSnapshot {
    let phase: SessionPhase
    let deadline: Date?
    let remainingSeconds: Int
    let batteryText: String
    let networkText: String
    let networkSafetyEnabled: Bool
    let scopeText: String
    let thermalText: String
    let lidText: String
    let summary: String
}

enum SessionStartError: LocalizedError {
    case alreadyActive
    case helperUnavailable
    case helperRejected(String)
    case assertionFailure

    var errorDescription: String? {
        switch self {
        case .alreadyActive:
            return "守护会话已经在运行。"
        case .helperUnavailable:
            return "管理员 Helper 不可用，请重新执行首次设置。"
        case .helperRejected(let message):
            return "Helper 拒绝启动：\(message)"
        case .assertionFailure:
            return "无法建立空闲睡眠保护。"
        }
    }
}

private struct SessionPreparationCancelled: Error {}

final class SessionController {
    var onSnapshot: ((SessionSnapshot) -> Void)?
    var onEnded: ((StopReason, String) -> Void)?
    var onStartFailure: ((Error) -> Void)?

    private let helper = HelperClient()
    private let network = NetworkHealthMonitor()
    private let idleAssertion = IdleSleepAssertion()
    private let stateStore = AppStateStore()
    private let reportStore = SessionReportStore()
    private let worker = DispatchQueue(label: "com.xufeiyang.clamshellguardian.session-worker", qos: .userInitiated)

    private(set) var phase: SessionPhase = .idle
    private var sessionID: String?
    private var startedAt: Date?
    private var deadline: Date?
    private var networkSafetyEnabled = GuardianPreferences.networkSafetyEnabled
    private var networkHealthy = false
    private var offlineSince: Date?
    private var offlineSinceUptime: TimeInterval?
    private var helperFailureSinceUptime: TimeInterval?
    private var heartbeatInFlight = false
    private var timers: [DispatchSourceTimer] = []
    private var metadata: AppSessionRecord?
    private var reportStartBattery: BatterySnapshot?
    private var reportNetworkInterruptionCount = 0
    private var reportTotalOfflineSeconds: TimeInterval = 0
    private var reportLongestOfflineSeconds: TimeInterval = 0
    private var reportLidClosedObserved = false
    private var reportHighestThermalLevel: ThermalLevel = .nominal

    init() {
        network.onChange = { [weak self] healthy in
            self?.handleNetworkChange(healthy)
        }
    }

    var isActiveOrPreparing: Bool {
        phase != .idle
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard phase == .idle else {
            publishSnapshot(summary: phase == .active ? "守护已在运行，截止时间不会延长" : "正在准备守护")
            return
        }
        networkSafetyEnabled = GuardianPreferences.networkSafetyEnabled
        phase = .preparing
        publishSnapshot(summary: networkSafetyEnabled ? "正在检查系统与网络…" : "正在检查系统安全状态…")

        worker.async { [weak self] in
            guard let self else { return }
            do {
                guard self.helper.send(HelperRequest(command: .status)) != nil else {
                    throw SessionStartError.helperUnavailable
                }
                try self.ensureStillPreparing()
                guard SystemChecks.isAppleSilicon else {
                    throw PreflightError.unsupportedArchitecture
                }
                let battery = SystemChecks.batterySnapshot()
                if !battery.isCharging,
                   let percent = battery.percent,
                   percent <= SessionGovernor.batteryFloor {
                    throw PreflightError.batteryTooLow
                }
                let initialThermal = SystemChecks.thermalLevel()
                if initialThermal == .serious || initialThermal == .critical {
                    throw PreflightError.thermalTooHigh
                }
                if self.networkSafetyEnabled {
                    guard SystemChecks.wifiPoweredOn() else { throw PreflightError.wifiDisabled }
                    guard NetworkHealthMonitor.canReachInternet(timeout: 8) else {
                        throw PreflightError.networkUnavailable
                    }
                }
                try self.ensureStillPreparing()

                let start = Date()
                let hardDeadline = start.addingTimeInterval(SessionGovernor.maximumDuration)
                let identifier = UUID().uuidString
                let response = self.helper.send(HelperRequest(
                    command: .start,
                    sessionID: identifier,
                    deadline: hardDeadline
                ))
                guard let response else { throw SessionStartError.helperUnavailable }
                guard response.ok, response.active, response.sleepDisabled else {
                    throw SessionStartError.helperRejected(response.message)
                }
                DispatchQueue.main.async {
                    self.activate(sessionID: identifier, startedAt: start, deadline: response.deadline ?? hardDeadline)
                }
            } catch {
                DispatchQueue.main.async {
                    if error is SessionPreparationCancelled || self.phase != .preparing {
                        return
                    }
                    self.phase = .idle
                    self.publishSnapshot(summary: "未启动")
                    self.onStartFailure?(error)
                }
            }
        }
    }

    func stop(reason: StopReason = .manual) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.stop(reason: reason) }
            return
        }
        guard phase == .active || phase == .preparing else { return }
        let reportDraft = phase == .active
            ? makeSessionReport(reason: reason, details: "正在结束守护")
            : nil
        if let reportDraft { reportStore.save(reportDraft) }
        phase = .stopping
        let identifier = sessionID
        cleanLocalResources(clearState: true)
        publishSnapshot(summary: "正在恢复正常睡眠策略…")

        worker.async { [weak self] in
            guard let self else { return }
            let response = self.helper.send(HelperRequest(
                command: .stop,
                sessionID: identifier,
                reason: reason
            ))
            DispatchQueue.main.async {
                self.phase = .idle
                self.sessionID = nil
                self.startedAt = nil
                self.deadline = nil
                self.publishSnapshot(summary: reason.chineseDescription)
                let details = response?.message ?? "Helper 未响应；其 15 秒心跳保护会自动恢复系统睡眠。"
                if var reportDraft {
                    reportDraft.details = details
                    self.reportStore.save(reportDraft)
                }
                self.resetReportMetrics()
                self.onEnded?(reason, details)
            }
        }
    }

    func currentSnapshot() -> SessionSnapshot {
        if phase == .idle {
            networkSafetyEnabled = GuardianPreferences.networkSafetyEnabled
        }
        return makeSnapshot(summary: phase == .active ? "可以合盖 · 闭盖守护中" : "未运行")
    }

    func preferencesDidChange() {
        guard phase == .idle else { return }
        networkSafetyEnabled = GuardianPreferences.networkSafetyEnabled
        publishSnapshot(summary: "未运行")
    }

    private func activate(sessionID: String, startedAt: Date, deadline: Date) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard phase == .preparing else {
            worker.async { [helper] in
                _ = helper.send(HelperRequest(command: .stop, sessionID: sessionID, reason: .manual))
            }
            return
        }
        guard idleAssertion.acquire() else {
            worker.async { [helper] in
                _ = helper.send(HelperRequest(command: .stop, sessionID: sessionID, reason: .compatibilityFailure))
            }
            phase = .idle
            onStartFailure?(SessionStartError.assertionFailure)
            return
        }

        self.sessionID = sessionID
        self.startedAt = startedAt
        self.deadline = deadline
        self.phase = .active
        self.networkHealthy = true
        self.offlineSince = nil
        self.offlineSinceUptime = nil
        self.helperFailureSinceUptime = nil
        self.reportStartBattery = SystemChecks.batterySnapshot()
        self.reportNetworkInterruptionCount = 0
        self.reportTotalOfflineSeconds = 0
        self.reportLongestOfflineSeconds = 0
        self.reportLidClosedObserved = SystemChecks.lidClosed()
        self.reportHighestThermalLevel = thermalLevel()
        self.metadata = AppSessionRecord(
            version: 1,
            sessionID: sessionID,
            startedAt: startedAt,
            deadline: deadline,
            batteryFloor: SessionGovernor.batteryFloor,
            offlineSince: nil,
            thermalLevel: thermalLevel(),
            networkSafetyEnabled: networkSafetyEnabled
        )
        if networkSafetyEnabled {
            network.start()
            network.probeInternet()
        }
        installTimers()
        persistMetadata()
        publishSnapshot(summary: "可以合盖 · 所有检查已通过")
    }

    private func installTimers() {
        cancelTimers()
        timers = [
            makeTimer(interval: 1) { [weak self] in self?.tick() },
            makeTimer(interval: 5) { [weak self] in self?.sendHeartbeat() }
        ]
        if networkSafetyEnabled {
            timers.append(makeTimer(interval: 30) { [weak self] in self?.network.probeInternet() })
        }
    }

    private func makeTimer(interval: TimeInterval, handler: @escaping () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
    }

    private func tick() {
        guard phase == .active, let deadline else { return }
        if Date() >= deadline {
            stop(reason: .expired)
            return
        }
        if networkSafetyEnabled,
           let offlineSinceUptime,
           ProcessInfo.processInfo.systemUptime - offlineSinceUptime
               >= SessionGovernor.networkSleepDelay {
            stop(reason: .networkOffline)
            return
        }
        let currentThermal = thermalLevel()
        metadata?.thermalLevel = currentThermal
        if currentThermal.severityRank > reportHighestThermalLevel.severityRank {
            reportHighestThermalLevel = currentThermal
        }
        reportLidClosedObserved = reportLidClosedObserved || SystemChecks.lidClosed()
        publishSnapshot(summary: offlineSince == nil ? "可以合盖 · 闭盖守护中" : "守护中 · 正在等待网络恢复")
    }

    private func sendHeartbeat() {
        guard phase == .active, !heartbeatInFlight, let sessionID else { return }
        heartbeatInFlight = true
        worker.async { [weak self] in
            guard let self else { return }
            let response = self.helper.send(HelperRequest(command: .heartbeat, sessionID: sessionID))
            DispatchQueue.main.async {
                self.heartbeatInFlight = false
                guard self.phase == .active else { return }
                guard let response else {
                    if self.helperFailureSinceUptime == nil {
                        self.helperFailureSinceUptime = ProcessInfo.processInfo.systemUptime
                    }
                    if let failedAt = self.helperFailureSinceUptime,
                       ProcessInfo.processInfo.systemUptime - failedAt
                           >= SessionGovernor.heartbeatTimeout {
                        self.finishLocally(reason: .heartbeatLost, details: "Helper 已连续 15 秒无响应，系统侧看门狗将恢复睡眠策略。")
                    }
                    return
                }
                self.helperFailureSinceUptime = nil
                guard response.active else {
                    self.finishLocally(
                        reason: response.stopReason ?? .heartbeatLost,
                        details: response.message
                    )
                    return
                }
                self.persistMetadata()
            }
        }
    }

    private func handleNetworkChange(_ healthy: Bool) {
        guard phase == .active, networkSafetyEnabled else { return }
        if healthy {
            if let offlineSinceUptime {
                let duration = max(0, ProcessInfo.processInfo.systemUptime - offlineSinceUptime)
                reportTotalOfflineSeconds += duration
                reportLongestOfflineSeconds = max(reportLongestOfflineSeconds, duration)
            }
            offlineSince = nil
            offlineSinceUptime = nil
        } else if offlineSince == nil {
            reportNetworkInterruptionCount += 1
            offlineSince = Date()
            offlineSinceUptime = ProcessInfo.processInfo.systemUptime
        }
        networkHealthy = healthy
        metadata?.offlineSince = offlineSince
        persistMetadata()
        publishSnapshot(summary: healthy ? "可以合盖 · 闭盖守护中" : "守护中 · 正在等待网络恢复")
    }

    private func finishLocally(reason: StopReason, details: String) {
        if let report = makeSessionReport(reason: reason, details: details) {
            reportStore.save(report)
        }
        cleanLocalResources(clearState: true)
        phase = .idle
        sessionID = nil
        startedAt = nil
        deadline = nil
        resetReportMetrics()
        publishSnapshot(summary: reason.chineseDescription)
        onEnded?(reason, details)
    }

    private func cleanLocalResources(clearState: Bool) {
        cancelTimers()
        network.stop()
        idleAssertion.release()
        if clearState {
            stateStore.clear()
            metadata = nil
        }
    }

    private func cancelTimers() {
        timers.forEach { $0.cancel() }
        timers.removeAll()
    }

    private func persistMetadata() {
        guard let metadata else { return }
        stateStore.save(metadata)
    }

    private func publishSnapshot(summary: String) {
        onSnapshot?(makeSnapshot(summary: summary))
    }

    private func makeSnapshot(summary: String) -> SessionSnapshot {
        let battery = SystemChecks.batterySnapshot()
        let percent = battery.percent.map { "\($0)%" } ?? "未知"
        let batteryText = battery.isCharging ? "\(percent)（接电）" : "\(percent)（电池）"
        let remaining: Int
        if let deadline {
            remaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
        } else {
            remaining = 0
        }
        let networkText: String
        if !networkSafetyEnabled {
            networkText = "未监控"
        } else if networkHealthy {
            networkText = "正常"
        } else if let offlineSince {
            let seconds = max(0, Int(Date().timeIntervalSince(offlineSince)))
            networkText = "离线 \(seconds / 60):\(String(format: "%02d", seconds % 60))"
        } else {
            networkText = phase == .active ? "检测中" : "—"
        }
        let lidText: String
        switch phase {
        case .idle: lidText = "不可合盖（尚未启动）"
        case .preparing: lidText = "请保持开盖"
        case .active: lidText = "✓ 可以合盖"
        case .stopping: lidText = "不可合盖（正在停止）"
        }
        return SessionSnapshot(
            phase: phase,
            deadline: deadline,
            remainingSeconds: remaining,
            batteryText: batteryText,
            networkText: networkText,
            networkSafetyEnabled: networkSafetyEnabled,
            scopeText: "所有应用与后台进程",
            thermalText: SystemChecks.thermalDescription(),
            lidText: lidText,
            summary: summary
        )
    }

    private func makeSessionReport(reason: StopReason, details: String) -> SessionReport? {
        guard let startedAt, let deadline else { return nil }
        let endedAt = Date()
        let endBattery = SystemChecks.batterySnapshot()
        var totalOffline = reportTotalOfflineSeconds
        var longestOffline = reportLongestOfflineSeconds
        if let offlineSinceUptime {
            let duration = max(0, ProcessInfo.processInfo.systemUptime - offlineSinceUptime)
            totalOffline += duration
            longestOffline = max(longestOffline, duration)
        }
        let currentThermal = thermalLevel()
        let highestThermal = currentThermal.severityRank > reportHighestThermalLevel.severityRank
            ? currentThermal
            : reportHighestThermalLevel
        return SessionReport(
            startedAt: startedAt,
            endedAt: endedAt,
            scheduledDeadline: deadline,
            stopReason: reason,
            details: details,
            startBatteryPercent: reportStartBattery?.percent,
            endBatteryPercent: endBattery.percent,
            startedOnPower: reportStartBattery?.isCharging ?? false,
            endedOnPower: endBattery.isCharging,
            networkSafetyEnabled: networkSafetyEnabled,
            networkInterruptionCount: reportNetworkInterruptionCount,
            totalOfflineSeconds: Int(totalOffline.rounded()),
            longestOfflineSeconds: Int(longestOffline.rounded()),
            systemWideProtectionConfirmed: true,
            lidClosedObserved: reportLidClosedObserved || SystemChecks.lidClosed(),
            highestThermalLevel: highestThermal
        )
    }

    private func resetReportMetrics() {
        reportStartBattery = nil
        reportNetworkInterruptionCount = 0
        reportTotalOfflineSeconds = 0
        reportLongestOfflineSeconds = 0
        reportLidClosedObserved = false
        reportHighestThermalLevel = .nominal
    }

    private func thermalLevel() -> ThermalLevel {
        SystemChecks.thermalLevel()
    }

    private func ensureStillPreparing() throws {
        let preparing = DispatchQueue.main.sync { phase == .preparing }
        if !preparing {
            throw SessionPreparationCancelled()
        }
    }

    func stopSynchronouslyForTermination() {
        guard phase == .active || phase == .preparing else { return }
        let identifier = sessionID
        if phase == .active,
           let report = makeSessionReport(
               reason: .applicationTerminating,
               details: "守护应用退出，已同步请求恢复正常睡眠策略。"
           ) {
            reportStore.save(report)
        }
        cleanLocalResources(clearState: true)
        _ = helper.send(HelperRequest(
            command: .stop,
            sessionID: identifier,
            reason: .applicationTerminating
        ))
        phase = .idle
        sessionID = nil
        startedAt = nil
        deadline = nil
        resetReportMetrics()
    }
}
