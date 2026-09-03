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
