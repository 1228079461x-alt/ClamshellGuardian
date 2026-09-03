import Foundation

public enum StopReason: String, Codable, CaseIterable, Sendable {
    case manual
    case expired
    case batteryFloor = "battery_floor"
    case thermalPressure = "thermal_pressure"
    case heartbeatLost = "heartbeat_lost"
    case networkOffline = "network_offline"
    case applicationTerminating = "application_terminating"
    case helperRestarted = "helper_restarted"
    case compatibilityFailure = "compatibility_failure"

    public var chineseDescription: String {
        switch self {
        case .manual: return "用户手动停止"
        case .expired: return "60 分钟已到期"
        case .batteryFloor: return "电量已降至 15%"
        case .thermalPressure: return "系统热状态过高"
        case .heartbeatLost: return "守护应用心跳中断"
        case .networkOffline: return "网络连续离线 10 分钟"
        case .applicationTerminating: return "守护应用正在退出"
        case .helperRestarted: return "守护 Helper 已重启"
        case .compatibilityFailure: return "当前 macOS 不兼容闭盖守护"
        }
    }
}

public enum ThermalLevel: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    public var severityRank: Int {
        switch self {
        case .nominal: return 0
        case .fair: return 1
        case .unknown: return 2
        case .serious: return 3
        case .critical: return 4
        }
    }
}

public struct SessionReport: Codable, Equatable, Sendable {
    public let version: Int
    public let startedAt: Date
    public let endedAt: Date
    public let scheduledDeadline: Date
    public let stopReason: StopReason
    public var details: String
    public let startBatteryPercent: Int?
    public let endBatteryPercent: Int?
    public let startedOnPower: Bool
    public let endedOnPower: Bool
    public let networkSafetyEnabled: Bool
    public let networkInterruptionCount: Int
    public let totalOfflineSeconds: Int
    public let longestOfflineSeconds: Int
    public let systemWideProtectionConfirmed: Bool
    public let lidClosedObserved: Bool
    public let highestThermalLevel: ThermalLevel

    public init(
        version: Int = 1,
        startedAt: Date,
        endedAt: Date,
        scheduledDeadline: Date,
        stopReason: StopReason,
        details: String,
        startBatteryPercent: Int?,
        endBatteryPercent: Int?,
        startedOnPower: Bool,
        endedOnPower: Bool,
        networkSafetyEnabled: Bool,
        networkInterruptionCount: Int,
        totalOfflineSeconds: Int,
        longestOfflineSeconds: Int,
        systemWideProtectionConfirmed: Bool,
        lidClosedObserved: Bool,
        highestThermalLevel: ThermalLevel
    ) {
        self.version = version
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.scheduledDeadline = scheduledDeadline
        self.stopReason = stopReason
        self.details = details
        self.startBatteryPercent = startBatteryPercent
        self.endBatteryPercent = endBatteryPercent
        self.startedOnPower = startedOnPower
        self.endedOnPower = endedOnPower
        self.networkSafetyEnabled = networkSafetyEnabled
        self.networkInterruptionCount = networkInterruptionCount
        self.totalOfflineSeconds = totalOfflineSeconds
        self.longestOfflineSeconds = longestOfflineSeconds
        self.systemWideProtectionConfirmed = systemWideProtectionConfirmed
        self.lidClosedObserved = lidClosedObserved
        self.highestThermalLevel = highestThermalLevel
    }
}

public struct GovernorInput: Equatable, Sendable {
    public var now: Date
    public var deadline: Date
    public var lastHeartbeat: Date
    public var batteryPercent: Int?
    public var isCharging: Bool
    public var thermalLevel: ThermalLevel

    public init(
        now: Date,
        deadline: Date,
        lastHeartbeat: Date,
        batteryPercent: Int?,
        isCharging: Bool,
        thermalLevel: ThermalLevel
    ) {
        self.now = now
        self.deadline = deadline
        self.lastHeartbeat = lastHeartbeat
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.thermalLevel = thermalLevel
    }
}

public enum SessionGovernor {
    public static let maximumDuration: TimeInterval = 3_600
    public static let heartbeatTimeout: TimeInterval = 15
    public static let batteryFloor = 15
    public static let networkSleepDelay: TimeInterval = 600

    public static func stopReason(for input: GovernorInput) -> StopReason? {
        if input.now >= input.deadline {
            return .expired
        }
        if input.now.timeIntervalSince(input.lastHeartbeat) >= heartbeatTimeout {
            return .heartbeatLost
        }
        if !input.isCharging,
           let batteryPercent = input.batteryPercent,
           batteryPercent <= batteryFloor {
            return .batteryFloor
        }
        if input.thermalLevel == .serious || input.thermalLevel == .critical {
            return .thermalPressure
        }
        return nil
    }

    public static func validatedDeadline(requested: Date, now: Date) -> Date? {
        let interval = requested.timeIntervalSince(now)
        guard interval > 0, interval <= maximumDuration else { return nil }
        return requested
    }
}

public struct SessionRecord: Codable, Equatable, Sendable {
    public let version: Int
    public let sessionID: String
    public let ownerUID: UInt32
    public let startedAt: Date
    public let deadline: Date

    public init(
        version: Int = 1,
        sessionID: String,
        ownerUID: UInt32,
        startedAt: Date,
        deadline: Date
    ) {
        self.version = version
        self.sessionID = sessionID
        self.ownerUID = ownerUID
        self.startedAt = startedAt
        self.deadline = deadline
    }
}
