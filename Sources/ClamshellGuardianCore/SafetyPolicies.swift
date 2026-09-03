import Foundation

public enum NetworkGuardState: Equatable, Sendable {
    case healthy
    case waitingForConnection
    case sleepRequired
}

public enum NetworkSafetyPolicy {
    public static func state(
        enabled: Bool = true,
        now: Date,
        offlineSince: Date?
    ) -> NetworkGuardState {
        guard enabled else { return .healthy }
        guard let offlineSince else { return .healthy }
        let duration = now.timeIntervalSince(offlineSince)
        if duration >= SessionGovernor.networkSleepDelay { return .sleepRequired }
        return .waitingForConnection
    }
}

public enum PlatformSupport {
    public static func supports(architecture: String) -> Bool {
        architecture.lowercased() == "arm64"
    }
}

public enum LidDisplayState: Equatable, Sendable {
    case armed
    case sleepRequestIssued
}

public struct LidDisplayTransition: Equatable, Sendable {
    public let nextState: LidDisplayState
    public let shouldRequestDisplaySleep: Bool

    public init(nextState: LidDisplayState, shouldRequestDisplaySleep: Bool) {
        self.nextState = nextState
        self.shouldRequestDisplaySleep = shouldRequestDisplaySleep
    }
}

public enum LidDisplayPolicy {
    public static func transition(
        from state: LidDisplayState,
        lidClosed: Bool
    ) -> LidDisplayTransition {
        guard lidClosed else {
            return LidDisplayTransition(nextState: .armed, shouldRequestDisplaySleep: false)
        }
        guard state == .armed else {
            return LidDisplayTransition(nextState: .sleepRequestIssued, shouldRequestDisplaySleep: false)
        }
        return LidDisplayTransition(nextState: .sleepRequestIssued, shouldRequestDisplaySleep: true)
    }
}

public enum IPCAuthorization {
    public static func isAllowed(peerUID: UInt32, configuredUID: UInt32) -> Bool {
        configuredUID != 0 && peerUID == configuredUID
    }
}

public enum SleepOwnershipPolicy {
    public static func canStart(sleepDisabled: Bool, ownedStateMarkerExists: Bool) -> Bool {
        !sleepDisabled && !ownedStateMarkerExists
    }

    public static func shouldRecoverOnHelperLaunch(ownedStateMarkerExists: Bool) -> Bool {
        ownedStateMarkerExists
    }
}
