import Foundation
import Network

/// همگام‌سازی سرورها — همان منابع و قوانین نسخه اندروید:
/// ۸ منبع پیش‌فرض، سقف ۳۰۰ خط برای هر منبع بزرگ، پینگ TCP واقعی،
/// قانون سخت: پیکربندی بدون پینگ هرگز نمایش داده نمی‌شود.
/// رایگان = ۲۰ سریع‌ترین؛ هدیه = ۵۰ سریع‌ترین؛ ویژه = کل مجموعه.
final class ConfigSync: ObservableObject {
    static let shared = ConfigSync()

    @Published private(set) var servers: [ServerConfig] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var progress: Float = 0

    private var cachedConfig: RemoteAppConfig = .defaults
    private var configTask: Task<Void, Never>?

    var remoteConfig: RemoteAppConfig { cachedConfig }

    var freeServers: [ServerConfig] {
        Array(servers.sorted { ($0.pingMs ?? .max) < ($1.pingMs ?? .max) }
            .prefix(AppConstants.freeServerCount))
    }
    var giftServers: [ServerConfig] {
        Array(servers.sorted { ($0.pingMs ?? .max) < ($1.pingMs ?? .max) }
            .prefix(AppConstants.giftServerCount))
    }

    /// بروزرسانی کامل: پیکربندی از راه دور + منابع + پینگ.
    /// پیشرفت واقعی است (مراحل واقعی)، نه تایمر ساختگی.
    func refresh() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        progress = 0.05
        await fetchRemoteConfig()
        progress = 0.15
        let sources = cachedConfig.configSources?.isEmpty == false
            ? cachedConfig.configSources! : AppConstants.defaultConfigSources
        var allURIs: [String] = []
        for (i, url) in sources.enumerated() {
            if let lines = await fetchSource(url) {
                allURIs.append(contentsOf: lines)
            }
            progress = 0.15 + 0.30 * Float(i + 1) / Float(sources.count)
        }
        progress = 0.45
        var parsed: [ServerConfig] = []
        var seen = Set<String>()
        for uri in allURIs {
            guard let server = ServerConfig.parse(uri: uri) else { continue }
            guard seen.insert(server.dedupeKey).inserted else { continue }
            parsed.append(server)
        }
        progress = 0.55
        // پینگ TCP همه‌ی نامزدها (با سقف همزمانی).
        let pinged = await pingAll(parsed)
        progress = 0.95
        // فقط سرورهای پینگ‌شده نگه داشته می‌شوند — قانون سخت.
        let alive = pinged.filter { $0.pingMs != nil }
            .sorted { ($0.pingMs ?? .max) < ($1.pingMs ?? .max) }
        await MainActor.run {
            self.servers = alive
            self.lastSync = Date()
            self.progress = 1.0
        }
    }

    // MARK: - پیکربندی از راه دور

    func fetchRemoteConfig() async {
        guard let url = URL(string: AppConstants.appConfigURL) else { return }
        var req = URLRequest(url: url, timeoutInterval: AppConstants.networkTimeout)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            if let cfg = try? JSONDecoder().decode(RemoteAppConfig.self, from: data) {
                cachedConfig = cfg
                saveCachedConfig(data)
            }
        } catch {
            // بدون اینترنت: از کش استفاده می‌شود؛ اپ هرگز گیر نمی‌کند.
            if let data = loadCachedConfig(),
               let cfg = try? JSONDecoder().decode(RemoteAppConfig.self, from: data) {
                cachedConfig = cfg
            }
        }
    }

    private func cacheURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app_config.json")
    }
    private func saveCachedConfig(_ data: Data) { try? data.write(to: cacheURL()) }
    private func loadCachedConfig() -> Data? { try? Data(contentsOf: cacheURL()) }

    // MARK: - منابع

    private func fetchSource(_ urlString: String) async -> [String]? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: AppConstants.networkTimeout)
        req.setValue("text/plain", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            var text = String(data: data, encoding: .utf8) ?? ""
            // بدنه‌ی base64 (sub.txt و super-sub.txt) را باز می‌کنیم.
            if !text.contains("://"), let decoded = decodeBase64Loose(text), decoded.contains("://") {
                text = decoded
            }
            var lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.contains("://") }
            // منابع بزرگ: پخش یکنواخت ۳۰۰ خط.
            if AppConstants.defaultConfigSources.contains(urlString),
               urlString != AppConstants.liveJSON, urlString != AppConstants.subTxt,
               lines.count > AppConstants.githubSourcePingCap {
                lines = spread(lines, count: AppConstants.githubSourcePingCap)
            }
            return lines
        } catch { return nil }
    }

    private func decodeBase64Loose(_ s: String) -> String? {
        let cleaned = s.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        var padded = cleaned
        while padded.count % 4 != 0 { padded += "=" }
        guard let data = Data(base64Encoded: padded) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func spread<T>(_ items: [T], count: Int) -> [T] {
        guard items.count > count else { return items }
        let step = Double(items.count) / Double(count)
        return (0..<count).map { items[Int(Double($0) * step)] }
    }

    // MARK: - پینگ TCP

    private func pingAll(_ servers: [ServerConfig]) async -> [ServerConfig] {
        var result: [ServerConfig] = []
        await withTaskGroup(of: ServerConfig?.self) { group in
            var active = 0
            var index = 0
            func enqueue() {
                while active < 40 && index < servers.count {
                    let server = servers[index]; index += 1; active += 1
                    group.addTask {
                        var s = server
                        s.pingMs = await Self.tcpPing(host: server.host, port: server.port)
                        return s
                    }
                }
            }
            enqueue()
            for await item in group {
                active -= 1
                if let s = item { result.append(s) }
                enqueue()
            }
        }
        return result
    }

    /// یک اتصال TCP با مهلت ۳ ثانیه؛ برمی‌گرداند میلی‌ثانیه یا nil.
    static func tcpPing(host: String, port: Int) async -> Int? {
        await withCheckedContinuation { cont in
            let connection = NWConnection(
                to: .hostPort(host: .init(host), port: .init(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))),
                using: .tcp)
            let start = Date()
            var done = false
            let finish: (Int?) -> Void = { value in
                guard !done else { return }
                done = true
                connection.cancel()
                cont.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(Int(Date().timeIntervalSince(start) * 1000))
                case .failed, .cancelled:
                    finish(nil)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }
}
