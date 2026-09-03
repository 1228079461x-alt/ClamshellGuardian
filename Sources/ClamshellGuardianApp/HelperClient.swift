import AppKit
import ClamshellGuardianCore
import Darwin
import Foundation

final class HelperClient {
    func send(_ request: HelperRequest) -> HelperResponse? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = GuardianConstants.socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
        address.sun_len = UInt8(length)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, length)
            }
        }
        guard connected == 0 else { return nil }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var payload = try? encoder.encode(request) else { return nil }
        payload.append(0x0A)
        let didSend = payload.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            var sent = 0
            while sent < bytes.count {
                let result = Darwin.send(descriptor, base.advanced(by: sent), bytes.count - sent, 0)
                if result <= 0 { return false }
                sent += result
            }
            return true
        }
        guard didSend else { return nil }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 2_048)
        while responseData.count < 16_384 {
            let count = recv(descriptor, &buffer, buffer.count, 0)
            if count <= 0 { break }
            responseData.append(contentsOf: buffer.prefix(count))
            if responseData.contains(0x0A) { break }
        }
        if let newline = responseData.firstIndex(of: 0x0A) {
            responseData = responseData.prefix(upTo: newline)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperResponse.self, from: responseData)
    }

    func waitUntilAvailable(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if send(HelperRequest(command: .status)) != nil { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }
}

enum HelperInstallError: LocalizedError {
    case missingResource
    case plistCreation
    case authorization(String)
    case helperUnavailable

    var errorDescription: String? {
        switch self {
        case .missingResource: return "应用包中缺少守护 Helper。"
        case .plistCreation: return "无法生成 LaunchDaemon 配置。"
        case .authorization(let message): return "管理员安装失败：\(message)"
        case .helperUnavailable: return "Helper 已安装，但没有在限定时间内启动。"
        }
    }
}

final class HelperInstaller {
    private let client = HelperClient()

    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: GuardianConstants.helperInstallPath)
            && FileManager.default.fileExists(atPath: GuardianConstants.launchDaemonPath)
    }

    var isCurrentVersionInstalled: Bool {
        guard isInstalled,
              let status = client.send(HelperRequest(command: .status)) else {
            return false
        }
        return status.ok && status.version == GuardianConstants.ipcVersion
    }

    func install() throws {
        guard let bundledHelper = Bundle.main.resourceURL?.appendingPathComponent("ClamshellGuardianHelper"),
              FileManager.default.isExecutableFile(atPath: bundledHelper.path) else {
            throw HelperInstallError.missingResource
        }

        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ClamshellGuardian-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let plistURL = temporaryDirectory.appendingPathComponent("\(GuardianConstants.helperLabel).plist")
        let plist: [String: Any] = [
            "Label": GuardianConstants.helperLabel,
            "ProgramArguments": [
                GuardianConstants.helperInstallPath,
                "--allowed-uid",
                String(getuid())
            ],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "ThrottleInterval": 2,
            "StandardOutPath": GuardianConstants.helperLogPath,
            "StandardErrorPath": GuardianConstants.helperLogPath
        ]
        guard let plistData = try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        ) else {
            throw HelperInstallError.plistCreation
        }
        try plistData.write(to: plistURL, options: .atomic)

        let command = [
            "/bin/mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons",
            "/usr/sbin/chown root:wheel /Library/PrivilegedHelperTools /Library/LaunchDaemons",
            "/bin/chmod 0755 /Library/PrivilegedHelperTools /Library/LaunchDaemons",
            "/usr/bin/install -o root -g wheel -m 0755 \(shellQuote(bundledHelper.path)) \(shellQuote(GuardianConstants.helperInstallPath))",
            "/usr/bin/install -o root -g wheel -m 0644 \(shellQuote(plistURL.path)) \(shellQuote(GuardianConstants.launchDaemonPath))",
            "(if /bin/launchctl print system/\(GuardianConstants.helperLabel) >/dev/null 2>&1; then /bin/launchctl bootout system/\(GuardianConstants.helperLabel); fi)",
            "/bin/launchctl bootstrap system \(shellQuote(GuardianConstants.launchDaemonPath))",
            "/bin/launchctl enable system/\(GuardianConstants.helperLabel)",
            "/bin/launchctl kickstart -k system/\(GuardianConstants.helperLabel)"
        ].joined(separator: " && ")
        try runAsAdministrator(command)
        guard client.waitUntilAvailable(timeout: 8) else {
            throw HelperInstallError.helperUnavailable
        }
    }

    func uninstall() throws {
        _ = client.send(HelperRequest(command: .stop, reason: .manual))
        let command = [
            "/usr/bin/pmset -a disablesleep 0",
            "(if /bin/launchctl print system/\(GuardianConstants.helperLabel) >/dev/null 2>&1; then /bin/launchctl bootout system/\(GuardianConstants.helperLabel); fi)",
            "/bin/rm -f \(shellQuote(GuardianConstants.launchDaemonPath))",
            "/bin/rm -f \(shellQuote(GuardianConstants.helperInstallPath))",
            "/bin/rm -f \(shellQuote(GuardianConstants.statePath))",
            "/bin/rm -f \(shellQuote(GuardianConstants.socketPath))",
            "/bin/rm -f \(shellQuote(GuardianConstants.helperLogPath))"
        ].joined(separator: " && ")
        try runAsAdministrator(command)
    }

    private func runAsAdministrator(_ command: String) throws {
        if !Thread.isMainThread {
            var result: Result<Void, Error>!
            DispatchQueue.main.sync {
                result = Result { try self.runAsAdministratorOnMainThread(command) }
            }
            try result.get()
            return
        }
        try runAsAdministratorOnMainThread(command)
    }

    private func runAsAdministratorOnMainThread(_ command: String) throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        guard let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges") else {
            throw HelperInstallError.authorization("无法创建授权脚本")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? error.description
            throw HelperInstallError.authorization(message)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
