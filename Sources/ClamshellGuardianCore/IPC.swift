import Foundation

public enum HelperCommand: String, Codable, Sendable {
    case start
    case heartbeat
    case stop
    case status
}

public struct HelperRequest: Codable, Sendable {
    public let version: Int
    public let command: HelperCommand
    public let sessionID: String?
    public let deadline: Date?
    public let reason: StopReason?

    public init(
        version: Int = GuardianConstants.ipcVersion,
        command: HelperCommand,
        sessionID: String? = nil,
        deadline: Date? = nil,
        reason: StopReason? = nil
    ) {
        self.version = version
        self.command = command
        self.sessionID = sessionID
        self.deadline = deadline
        self.reason = reason
    }
}

public struct HelperResponse: Codable, Sendable {
    public let version: Int
    public let ok: Bool
    public let message: String
    public let active: Bool
    public let sessionID: String?
    public let deadline: Date?
    public let sleepDisabled: Bool
    public let stopReason: StopReason?

    public init(
        version: Int = GuardianConstants.ipcVersion,
        ok: Bool,
        message: String,
        active: Bool,
        sessionID: String? = nil,
        deadline: Date? = nil,
        sleepDisabled: Bool,
        stopReason: StopReason? = nil
    ) {
        self.version = version
        self.ok = ok
        self.message = message
        self.active = active
        self.sessionID = sessionID
        self.deadline = deadline
        self.sleepDisabled = sleepDisabled
        self.stopReason = stopReason
    }
}

public enum GuardianConstants {
    public static let ipcVersion = 2
    public static let helperLabel = "com.xufeiyang.clamshellguardian.helper"
    public static let helperInstallPath = "/Library/PrivilegedHelperTools/com.xufeiyang.clamshellguardian.helper"
    public static let launchDaemonPath = "/Library/LaunchDaemons/com.xufeiyang.clamshellguardian.helper.plist"
    public static let socketPath = "/var/run/com.xufeiyang.clamshellguardian.sock"
    public static let statePath = "/var/db/com.xufeiyang.clamshellguardian.session.json"
    public static let helperLogPath = "/var/log/clamshellguardian-helper.log"
    public static let appBundleIdentifier = "com.xufeiyang.clamshellguardian"
}
