import Foundation
import Network

final class NetworkHealthMonitor {
    typealias ChangeHandler = (Bool) -> Void

    private let queue = DispatchQueue(label: "com.xufeiyang.clamshellguardian.network")
    private var monitor: NWPathMonitor?
    private var pathSatisfied = false
    private var lastTLSResult: Bool?
    private var running = false
    private var lastPublished: Bool?
    private var generation = 0

    var onChange: ChangeHandler?

    static func canReachInternet(timeout: TimeInterval = 8) -> Bool {
        let urls = ["https://www.apple.com", "https://www.cloudflare.com"].compactMap(URL.init(string:))
        let lock = NSLock()
        let completed = DispatchSemaphore(value: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        var remaining = urls.count
        var didComplete = false
        var succeeded = false

        let tasks = urls.map { url in
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            return session.dataTask(with: request) { _, response, error in
                var shouldSignal = false
                lock.lock()
                remaining -= 1
                if !didComplete, error == nil, response != nil {
                    succeeded = true
                    didComplete = true
                    shouldSignal = true
                } else if !didComplete, remaining == 0 {
                    didComplete = true
                    shouldSignal = true
                }
                lock.unlock()
                if shouldSignal { completed.signal() }
            }
        }
        tasks.forEach { $0.resume() }
        _ = completed.wait(timeout: .now() + timeout)
        lock.lock()
        let result = succeeded
        lock.unlock()
        tasks.forEach { $0.cancel() }
        session.invalidateAndCancel()
        return result
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.pathSatisfied = false
            self.lastTLSResult = nil
            self.lastPublished = nil
            let monitor = NWPathMonitor()
            self.monitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                self.queue.async {
                    self.pathSatisfied = path.status == .satisfied
                    self.lastTLSResult = nil
                    self.publishIfNeeded()
                    if self.pathSatisfied {
                        self.probeInternet()
                    }
                }
            }
            monitor.start(queue: self.queue)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.running = false
            self.generation += 1
            self.monitor?.cancel()
            self.monitor = nil
        }
    }

    func probeInternet() {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            guard self.pathSatisfied else {
                self.lastTLSResult = false
                self.publishIfNeeded()
                return
            }
            self.generation += 1
            let probeGeneration = self.generation
            self.probe(hosts: ["www.apple.com", "www.cloudflare.com"], index: 0) { [weak self] success in
                guard let self else { return }
                self.queue.async {
                    guard self.running, self.generation == probeGeneration else { return }
                    self.lastTLSResult = success
                    self.publishIfNeeded()
                }
            }
        }
    }

    private func probe(
        hosts: [NWEndpoint.Host],
        index: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard index < hosts.count else {
            completion(false)
            return
        }

        let connection = NWConnection(host: hosts[index], port: 443, using: .tls)
        var finished = false
        let finish: (Bool) -> Void = { success in
            self.queue.async {
                guard !finished else { return }
                finished = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                if success {
                    completion(true)
                } else {
                    self.probe(hosts: hosts, index: index + 1, completion: completion)
                }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 8) {
            finish(false)
        }
    }

    private func publishIfNeeded() {
        let healthy = pathSatisfied && (lastTLSResult ?? true)
        guard healthy != lastPublished else { return }
        lastPublished = healthy
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(healthy)
        }
    }
}
