import AppKit
import ClamshellGuardianCore
import CoreWLAN
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

struct BatterySnapshot {
    let percent: Int?
    let isCharging: Bool
}

enum PreflightError: LocalizedError {
    case unsupportedArchitecture
    case wifiDisabled
    case networkUnavailable
    case batteryTooLow
    case thermalTooHigh

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture:
            return "当前版本仅支持 Apple Silicon（M 系列）Mac。"
        case .wifiDisabled:
            return "Wi‑Fi 当前已关闭。请先打开 Wi‑Fi。"
        case .networkUnavailable:
            return "当前无法连接互联网。请确认现有 Wi‑Fi 或已开启的 iPhone 热点可以上网。"
        case .batteryTooLow:
            return "当前使用电池且电量不高于 15%，为避免关机，本次守护未启动。"
        case .thermalTooHigh:
            return "系统热状态已经达到严重或危险，本次守护未启动。请先让电脑降温。"
        }
    }
}

enum SystemChecks {
    static var isAppleSilicon: Bool {
#if arch(arm64)
        true
#else
        false
#endif
    }

    static func batterySnapshot() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let rawList = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatterySnapshot(percent: nil, isCharging: false)
        }
        for source in rawList {
            guard let rawDescription = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue(),
                  let description = rawDescription as? [String: Any] else { continue }
            let current = description[kIOPSCurrentCapacityKey as String] as? Int
            let maximum = description[kIOPSMaxCapacityKey as String] as? Int
            let state = description[kIOPSPowerSourceStateKey as String] as? String
            let percent: Int?
            if let current, let maximum, maximum > 0 {
                percent = Int((Double(current) / Double(maximum) * 100).rounded())
            } else {
                percent = nil
            }
            return BatterySnapshot(
                percent: percent,
                isCharging: state == (kIOPSACPowerValue as String)
            )
        }
        return BatterySnapshot(percent: nil, isCharging: false)
    }

    static func wifiPoweredOn() -> Bool {
        CWWiFiClient.shared().interface()?.powerOn() ?? false
    }

    static func thermalDescription() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "正常"
        case .fair: return "轻微"
        case .serious: return "严重"
        case .critical: return "危险"
        @unknown default: return "未知"
        }
    }

    static func thermalLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }

    static func lidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return false
        }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

}

final class IdleSleepAssertion {
    private var assertionID = IOPMAssertionID(0)
    private(set) var isActive = false

    func acquire() -> Bool {
        if isActive { return true }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "合盖守护：所有应用与后台任务运行中" as CFString,
            &assertionID
        )
        isActive = result == kIOReturnSuccess
        return isActive
    }

    func release() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        isActive = false
    }

    deinit {
        release()
    }
}
