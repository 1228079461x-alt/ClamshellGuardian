import ClamshellGuardianCore
import Darwin
import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
}

let now = Date(timeIntervalSince1970: 2_000_000_000)
let tests: [(String, () throws -> Void)] = [
    ("到达硬截止时间立即结束", {
        let input = GovernorInput(
            now: now,
            deadline: now,
            lastHeartbeat: now,
            batteryPercent: 80,
            isCharging: false,
            thermalLevel: .nominal
        )
        try check(SessionGovernor.stopReason(for: input) == .expired, "未返回 expired")
    }),
    ("仅在未充电且电量不高于 15% 时结束", {
        var input = GovernorInput(
            now: now,
            deadline: now.addingTimeInterval(100),
            lastHeartbeat: now,
            batteryPercent: 15,
            isCharging: false,
            thermalLevel: .nominal
        )
        try check(SessionGovernor.stopReason(for: input) == .batteryFloor, "15% 放电时未停止")
        input.isCharging = true
        try check(SessionGovernor.stopReason(for: input) == nil, "接电时不应因 15% 停止")
    }),
    ("serious 热状态立即结束", {
        let input = GovernorInput(
            now: now,
            deadline: now.addingTimeInterval(100),
            lastHeartbeat: now,
            batteryPercent: 90,
            isCharging: true,
            thermalLevel: .serious
        )
        try check(SessionGovernor.stopReason(for: input) == .thermalPressure, "未返回 thermalPressure")
    }),
    ("心跳超过 15 秒立即结束", {
        let input = GovernorInput(
            now: now,
            deadline: now.addingTimeInterval(100),
            lastHeartbeat: now.addingTimeInterval(-16),
            batteryPercent: 90,
            isCharging: true,
            thermalLevel: .nominal
        )
        try check(SessionGovernor.stopReason(for: input) == .heartbeatLost, "16 秒时未停止")
        var exactBoundary = input
        exactBoundary.lastHeartbeat = now.addingTimeInterval(-15)
        try check(SessionGovernor.stopReason(for: exactBoundary) == .heartbeatLost, "15 秒边界未停止")
    }),
    ("客户端不能请求超过一小时", {
        try check(
            SessionGovernor.validatedDeadline(requested: now.addingTimeInterval(3_600), now: now) != nil,
            "恰好 3600 秒应被接受"
        )
        try check(
            SessionGovernor.validatedDeadline(requested: now.addingTimeInterval(3_600.01), now: now) == nil,
            "超过 3600 秒应被拒绝"
        )
        try check(
            SessionGovernor.validatedDeadline(requested: now.addingTimeInterval(3_602), now: now) == nil,
            "明显超期应被拒绝"
        )
    }),
    ("离线不足 10 分钟等待、到 10 分钟睡眠", {
        try check(
            NetworkSafetyPolicy.state(now: now, offlineSince: now.addingTimeInterval(-300)) == .waitingForConnection,
            "5 分钟时应继续等待"
        )
        try check(
            NetworkSafetyPolicy.state(now: now, offlineSince: now.addingTimeInterval(-600)) == .sleepRequired,
            "10 分钟边界未要求睡眠"
        )
        try check(
            NetworkSafetyPolicy.state(now: now, offlineSince: now.addingTimeInterval(-599)) == .waitingForConnection,
            "10 分钟前状态错误"
        )
        try check(NetworkSafetyPolicy.state(now: now, offlineSince: nil) == .healthy, "联网状态错误")
        try check(
            NetworkSafetyPolicy.state(enabled: false, now: now, offlineSince: now.addingTimeInterval(-3_600)) == .healthy,
            "关闭断网保护后不应因离线停止"
        )
    }),
    ("发行包仅接受 Apple Silicon 架构", {
        try check(PlatformSupport.supports(architecture: "arm64"), "arm64 应受支持")
        try check(!PlatformSupport.supports(architecture: "x86_64"), "Intel 架构不应被当前发行包接受")
        try check(!PlatformSupport.supports(architecture: ""), "空架构不应受支持")
    }),
    ("非授权 UID 被拒绝", {
        try check(IPCAuthorization.isAllowed(peerUID: 501, configuredUID: 501), "授权 UID 被拒绝")
        try check(!IPCAuthorization.isAllowed(peerUID: 502, configuredUID: 501), "错误接受其他 UID")
        try check(!IPCAuthorization.isAllowed(peerUID: 0, configuredUID: 0), "不应接受 root/root 配置")
    }),
    ("不覆盖其他软件的 SleepDisabled", {
        try check(!SleepOwnershipPolicy.canStart(sleepDisabled: true, ownedStateMarkerExists: false), "错误覆盖外部状态")
        try check(SleepOwnershipPolicy.canStart(sleepDisabled: false, ownedStateMarkerExists: false), "干净状态应可启动")
        try check(SleepOwnershipPolicy.shouldRecoverOnHelperLaunch(ownedStateMarkerExists: true), "遗留标记应恢复")
    }),
    ("运行报告可完整保存并恢复", {
        let report = SessionReport(
            startedAt: now,
            endedAt: now.addingTimeInterval(120),
            scheduledDeadline: now.addingTimeInterval(3_600),
            stopReason: .manual,
            details: "测试结束",
            startBatteryPercent: 88,
            endBatteryPercent: 86,
            startedOnPower: false,
            endedOnPower: false,
            networkSafetyEnabled: true,
            networkInterruptionCount: 1,
            totalOfflineSeconds: 20,
            longestOfflineSeconds: 20,
            systemWideProtectionConfirmed: true,
            lidClosedObserved: true,
            highestThermalLevel: .fair
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(SessionReport.self, from: data)
        try check(restored == report, "运行报告 JSON 往返后不一致")
        try check(ThermalLevel.critical.severityRank > ThermalLevel.serious.severityRank, "热状态严重度顺序错误")
    }),
    ("每个停止原因都有中文说明", {
        try check(StopReason.allCases.count == 9, "停止原因数量不符")
        try check(StopReason.allCases.allSatisfy { !$0.chineseDescription.isEmpty }, "存在空白中文说明")
    })
]

var failures = 0
for (name, body) in tests {
    do {
        try body()
        print("✓ \(name)")
    } catch {
        failures += 1
        print("✗ \(name)：\(error)")
    }
}

if failures > 0 {
    print("安全策略测试失败：\(failures)/\(tests.count)")
    exit(EXIT_FAILURE)
}

print("安全策略测试通过：\(tests.count)/\(tests.count)")
