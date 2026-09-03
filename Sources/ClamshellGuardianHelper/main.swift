import ClamshellGuardianCore
import Darwin
import Foundation
import IOKit
import IOKit.ps

private final class SystemPowerController {
    struct BatteryState {
        let percent: Int?
        let isCharging: Bool
    }

    func setSleepDisabled(_ disabled: Bool) -> Bool {
        runPMSet(["-a", "disablesleep", disabled ? "1" : "0"])
    }

    func sleepNow() -> Bool {
        runPMSet(["sleepnow"])
    }

    func displaySleepNow() -> Bool {
        runPMSet(["displaysleepnow"])
    }

    func sleepDisabled() -> Bool {
        registryBool(key: "SleepDisabled") ?? false
    }

    func lidClosed() -> Bool {
        registryBool(key: "AppleClamshellState") ?? false
    }

    func batteryState() -> BatteryState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let rawList = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryState(percent: nil, isCharging: false)
        }

        for source in rawList {
            guard let rawDescription = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue(),
                  let description = rawDescription as? [String: Any] else {
                continue
            }
            let current = description[kIOPSCurrentCapacityKey as String] as? Int
            let maximum = description[kIOPSMaxCapacityKey as String] as? Int
            let state = description[kIOPSPowerSourceStateKey as String] as? String
            let percent: Int?
            if let current, let maximum, maximum > 0 {
                percent = Int((Double(current) / Double(maximum) * 100).rounded())
            } else {
                percent = nil
            }
            return BatteryState(
                percent: percent,
                isCharging: state == (kIOPSACPowerValue as String)
            )
        }
        return BatteryState(percent: nil, isCharging: false)
    }

    func thermalLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }

    private func registryBool(key: String) -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    @discardableResult
    private func runPMSet(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

private final class SessionCoordinator {
    private let allowedUID: uid_t
    private let power = SystemPowerController()
    private let lock = NSLock()
    private var record: SessionRecord?
    private var lastHeartbeat: Date?
    private var lastHeartbeatUptime: TimeInterval?
    private var deadlineUptime: TimeInterval?
    private var lastStopReason: StopReason?
    private var lidDisplayState: LidDisplayState = .armed
    private var watchdogTimer: DispatchSourceTimer?
    private var signalSources: [DispatchSourceSignal] = []

    init(allowedUID: uid_t) {
        self.allowedUID = allowedUID
        recoverOwnedStaleState()
    }

    func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.evaluateSafetyRules()
        }
        timer.resume()
        watchdogTimer = timer

        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global(qos: .userInitiated))
            source.setEventHandler { [weak self] in
                self?.stopInternally(reason: .applicationTerminating)
                Darwin.exit(EXIT_SUCCESS)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func handle(_ request: HelperRequest) -> HelperResponse {
        guard request.version == GuardianConstants.ipcVersion else {
            return response(ok: false, message: "不支持的 IPC 版本")
        }

        switch request.command {
        case .start:
            guard let sessionID = request.sessionID,
                  !sessionID.isEmpty,
                  let requestedDeadline = request.deadline,
                  let deadline = SessionGovernor.validatedDeadline(requested: requestedDeadline, now: Date()) else {
                return response(ok: false, message: "会话参数无效或超过 3600 秒")
            }
            return start(sessionID: sessionID, deadline: deadline)
        case .heartbeat:
            guard let sessionID = request.sessionID else {
                return response(ok: false, message: "缺少会话 ID")
            }
            return heartbeat(sessionID: sessionID)
        case .stop:
            return stop(sessionID: request.sessionID, reason: request.reason ?? .manual)
        case .status:
            return response(ok: true, message: "状态已读取")
        }
    }

    private func start(sessionID: String, deadline: Date) -> HelperResponse {
        lock.lock()
        defer { lock.unlock() }

        guard record == nil else {
            return responseLocked(ok: false, message: "已有守护会话正在运行")
        }
        guard !power.sleepDisabled() else {
            return responseLocked(ok: false, message: "系统睡眠已被其他软件禁用，拒绝覆盖")
        }

        let now = Date()
        let startUptime = ProcessInfo.processInfo.systemUptime
        let newRecord = SessionRecord(
            sessionID: sessionID,
            ownerUID: UInt32(allowedUID),
            startedAt: now,
            deadline: deadline
        )
        guard persist(newRecord) else {
            return responseLocked(ok: false, message: "无法写入 root 会话标记")
        }
        guard power.setSleepDisabled(true), power.sleepDisabled() else {
            removeStateFile()
            _ = power.setSleepDisabled(false)
            return responseLocked(ok: false, message: "当前 macOS 未能启用闭盖守护")
        }

        record = newRecord
        lastHeartbeat = now
        lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
        deadlineUptime = startUptime + deadline.timeIntervalSince(now)
        lastStopReason = nil
        lidDisplayState = .armed
        return responseLocked(ok: true, message: "闭盖守护已启动")
    }

    private func heartbeat(sessionID: String) -> HelperResponse {
        lock.lock()
        defer { lock.unlock() }
        guard record?.sessionID == sessionID else {
            return responseLocked(ok: false, message: "会话不存在或 ID 不匹配")
        }
        lastHeartbeat = Date()
        lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
        return responseLocked(ok: true, message: "心跳已续期")
    }

    private func stop(sessionID: String?, reason: StopReason) -> HelperResponse {
        lock.lock()
        if let expected = record?.sessionID,
           let sessionID,
           expected != sessionID {
            let result = responseLocked(ok: false, message: "会话 ID 不匹配")
            lock.unlock()
            return result
        }
        let hadOwnedSession = record != nil || FileManager.default.fileExists(atPath: GuardianConstants.statePath)
        record = nil
        lastHeartbeat = nil
        lastHeartbeatUptime = nil
        deadlineUptime = nil
        lastStopReason = reason
        lidDisplayState = .armed
        lock.unlock()

        guard hadOwnedSession else {
            return response(ok: true, message: "当前没有守护会话")
        }

        let restored = restoreNormalSleep(forceSleepWhenClosed: true)
        return response(
            ok: restored,
            message: restored ? "已恢复正常睡眠" : "恢复正常睡眠失败，请运行 sudo pmset -a disablesleep 0"
        )
    }

    private func evaluateSafetyRules() {
        lock.lock()
        guard let record, let lastHeartbeat else {
            let needsRecovery = FileManager.default.fileExists(atPath: GuardianConstants.statePath)
            lidDisplayState = .armed
            lock.unlock()
            if needsRecovery {
                _ = restoreNormalSleep(forceSleepWhenClosed: true)
            }
            return
        }
        let capturedHeartbeatUptime = lastHeartbeatUptime
        let capturedDeadlineUptime = deadlineUptime
        let displayTransition = LidDisplayPolicy.transition(
            from: lidDisplayState,
            lidClosed: power.lidClosed()
        )
        lidDisplayState = displayTransition.nextState
        let capturedSessionID = record.sessionID
        let battery = power.batteryState()
        let uptime = ProcessInfo.processInfo.systemUptime
        let input = GovernorInput(
            now: Date(),
            deadline: record.deadline,
            lastHeartbeat: lastHeartbeat,
            batteryPercent: battery.percent,
            isCharging: battery.isCharging,
            thermalLevel: power.thermalLevel()
        )
        let reason: StopReason?
        if let capturedDeadlineUptime, uptime >= capturedDeadlineUptime {
            reason = .expired
        } else if let capturedHeartbeatUptime,
                  uptime - capturedHeartbeatUptime >= SessionGovernor.heartbeatTimeout {
            reason = .heartbeatLost
        } else {
            var monotonicInput = input
            monotonicInput.lastHeartbeat = input.now
            reason = SessionGovernor.stopReason(for: monotonicInput)
        }
        lock.unlock()

        if let reason {
            stopInternally(reason: reason)
        } else if displayTransition.shouldRequestDisplaySleep,
                  !power.displaySleepNow() {
            lock.lock()
            if self.record?.sessionID == capturedSessionID, power.lidClosed() {
                lidDisplayState = .armed
            }
            lock.unlock()
        }
    }

    private func stopInternally(reason: StopReason) {
        lock.lock()
        let hadOwnedSession = record != nil || FileManager.default.fileExists(atPath: GuardianConstants.statePath)
        record = nil
        lastHeartbeat = nil
        lastHeartbeatUptime = nil
        deadlineUptime = nil
        lastStopReason = reason
        lidDisplayState = .armed
        lock.unlock()
        if hadOwnedSession {
            _ = restoreNormalSleep(forceSleepWhenClosed: true)
        }
    }

    private func restoreNormalSleep(forceSleepWhenClosed: Bool) -> Bool {
        _ = power.setSleepDisabled(false)
        let restored = !power.sleepDisabled()
        if restored {
            removeStateFile()
        }
        if restored && forceSleepWhenClosed && power.lidClosed() {
            _ = power.sleepNow()
        }
        return restored
    }

    private func recoverOwnedStaleState() {
        guard FileManager.default.fileExists(atPath: GuardianConstants.statePath) else { return }
        _ = restoreNormalSleep(forceSleepWhenClosed: true)
        lastStopReason = .helperRestarted
    }

    private func persist(_ record: SessionRecord) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(record)
            try data.write(to: URL(fileURLWithPath: GuardianConstants.statePath), options: .atomic)
            chmod(GuardianConstants.statePath, 0o600)
            return true
        } catch {
            return false
        }
    }

    private func removeStateFile() {
        try? FileManager.default.removeItem(atPath: GuardianConstants.statePath)
    }

    private func response(ok: Bool, message: String) -> HelperResponse {
        lock.lock()
        defer { lock.unlock() }
        return responseLocked(ok: ok, message: message)
    }

    private func responseLocked(ok: Bool, message: String) -> HelperResponse {
        HelperResponse(
            ok: ok,
            message: message,
            active: record != nil,
            sessionID: record?.sessionID,
            deadline: record?.deadline,
            sleepDisabled: power.sleepDisabled(),
            stopReason: lastStopReason
        )
    }
}

private final class UnixSocketServer {
    private let allowedUID: uid_t
    private let coordinator: SessionCoordinator

    init(allowedUID: uid_t, coordinator: SessionCoordinator) {
        self.allowedUID = allowedUID
        self.coordinator = coordinator
    }

    func run() throws -> Never {
        unlink(GuardianConstants.socketPath)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = GuardianConstants.socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
        address.sun_len = UInt8(length)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, length)
            }
        }
        guard bindResult == 0 else {
            close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard chown(GuardianConstants.socketPath, allowedUID, gid_t.max) == 0,
              chmod(GuardianConstants.socketPath, 0o600) == 0,
              listen(descriptor, 8) == 0 else {
            close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        while true {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else {
                if errno == EINTR { continue }
                continue
            }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSignal = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            handle(client)
            close(client)
        }
    }

    private func handle(_ client: Int32) {
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(client, &peerUID, &peerGID) == 0,
              IPCAuthorization.isAllowed(peerUID: UInt32(peerUID), configuredUID: UInt32(allowedUID)) else {
            sendResponse(
                HelperResponse(
                    ok: false,
                    message: "调用用户未获授权",
                    active: false,
                    sleepDisabled: false
                ),
                to: client
            )
            return
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 2_048)
        while data.count < 16_384 {
            let count = recv(client, &buffer, buffer.count, 0)
            if count <= 0 { break }
            data.append(buffer, count: count)
            if data.contains(0x0A) { break }
        }
        if let newline = data.firstIndex(of: 0x0A) {
            data = data.prefix(upTo: newline)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let request = try? decoder.decode(HelperRequest.self, from: data) else {
            sendResponse(
                HelperResponse(
                    ok: false,
                    message: "IPC 请求格式无效",
                    active: false,
                    sleepDisabled: false
                ),
                to: client
            )
            return
        }
        sendResponse(coordinator.handle(request), to: client)
    }

    private func sendResponse(_ response: HelperResponse, to descriptor: Int32) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(response) else { return }
        data.append(0x0A)
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let result = Darwin.send(descriptor, base.advanced(by: sent), bytes.count - sent, 0)
                if result <= 0 { break }
                sent += result
            }
        }
    }
}

private func parseAllowedUID() -> uid_t? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--allowed-uid"),
          arguments.indices.contains(index + 1),
          let value = UInt32(arguments[index + 1]) else {
        return nil
    }
    return uid_t(value)
}

guard geteuid() == 0 else {
    fputs("ClamshellGuardianHelper must run as root.\n", stderr)
    exit(EXIT_FAILURE)
}
guard let allowedUID = parseAllowedUID(), allowedUID != 0 else {
    fputs("Missing or invalid --allowed-uid.\n", stderr)
    exit(EXIT_FAILURE)
}

private let coordinator = SessionCoordinator(allowedUID: allowedUID)
coordinator.startWatchdog()
private let server = UnixSocketServer(allowedUID: allowedUID, coordinator: coordinator)
do {
    try server.run()
} catch {
    fputs("Helper failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
