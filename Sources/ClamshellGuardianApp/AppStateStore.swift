import ClamshellGuardianCore
import Foundation

struct AppSessionRecord: Codable {
    let version: Int
    let sessionID: String
    let startedAt: Date
    let deadline: Date
    let batteryFloor: Int
    var offlineSince: Date?
    var thermalLevel: ThermalLevel
    let networkSafetyEnabled: Bool
}

enum GuardianPreferences {
    static let networkSafetyEnabledKey = "guardian.networkSafetyEnabled.v1"

    static var networkSafetyEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: networkSafetyEnabledKey) != nil else { return true }
            return defaults.bool(forKey: networkSafetyEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: networkSafetyEnabledKey)
        }
    }
}

final class AppStateStore {
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base
            .appendingPathComponent("合盖守护", isDirectory: true)
            .appendingPathComponent("session.json")
    }

    func save(_ record: AppSessionRecord) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            // State persistence is diagnostic only; the root helper remains authoritative.
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        let directory = fileURL.deletingLastPathComponent()
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ), contents.isEmpty {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

final class SessionReportStore {
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base
            .appendingPathComponent("合盖守护", isDirectory: true)
            .appendingPathComponent("last-session.json")
    }

    func save(_ report: SessionReport) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            // The report is diagnostic only and never controls the root helper.
        }
    }

    func load() -> SessionReport? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionReport.self, from: data)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        let directory = fileURL.deletingLastPathComponent()
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ), contents.isEmpty {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
