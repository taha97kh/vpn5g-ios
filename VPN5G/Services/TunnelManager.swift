import Foundation
import NetworkExtension

/// مدیریت تونل VPN — `NETunnelProviderManager` + افزونه‌ی تونل.
/// قانون تبلیغ: اتصال اولِ هر بار اجرای اپ بدون تبلیغ است؛ از اتصال دوم
/// به بعد، تبلیغ تمام‌صفحه قبل از شروع تونل نمایش داده می‌شود.
@MainActor
final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    enum ConnectGate {
        /// مستقیم وصل شو.
        case proceed
        /// اول تبلیغ تمام‌صفحه را نشان بده؛ بعد از تکمیل، `startAfterAd()` صدا زده می‌شود.
        case needsAd
    }

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var currentServer: ServerConfig?
    @Published private(set) var connectedAt: Date?
    @Published private(set) var lastError: String?
    /// تعداد اتصال‌های این بار اجرای اپ (برای قانون تبلیغ).
    @Published private(set) var sessionConnectCount = 0

    private var manager: NETunnelProviderManager?
    private var pendingServer: ServerConfig?
    private var baselineIP: String?
    private var statusObserver: NSObjectProtocol?

    private init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshStatus() }
            }
        Task { await loadManager() }
    }

    // MARK: - اتصال

    /// تصمیم دروازه‌ی تبلیغ برای یک اتصال جدید.
    func gateForConnect(tier: Tier) -> ConnectGate {
        if sessionConnectCount == 0 { return .proceed }
        if AdManager.shared.shouldShowInterstitial(tier: tier) { return .needsAd }
        return .proceed
    }

    func requestConnect(server: ServerConfig) {
        pendingServer = server
        let tier = SubscriptionStore.shared.effective.tier
        switch gateForConnect(tier: tier) {
        case .proceed:
            Task { await startTunnel(server: server) }
        case .needsAd:
            AdManager.shared.requestInterstitial { [weak self] completed in
                Task { @MainActor in
                    guard completed, let server = self?.pendingServer else { return }
                    await self?.startTunnel(server: server)
                }
            }
        }
    }

    /// شروع تونل بعد از تکمیل تبلیغ.
    func startAfterAd() async {
        guard let server = pendingServer else { return }
        await startTunnel(server: server)
    }

    func disconnect() {
        pendingServer = nil
        manager?.connection.stopVPNTunnel()
        connectedAt = nil
        SpeedMonitor.shared.reset()
    }

    // MARK: - شروع تونل

    private func startTunnel(server: ServerConfig) async {
        guard let configJSON = SingBoxConfigBuilder.buildJSON(server: server) else {
            lastError = NSLocalizedString("error_generic", comment: "")
            return
        }
        baselineIP = try? await fetchExitIP()
        await loadManager()
        guard let manager = manager else {
            lastError = NSLocalizedString("error_generic", comment: "")
            return
        }
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppConstants.tunnelBundleID
        proto.serverAddress = server.host
        proto.providerConfiguration = [
            "serverJSON": configJSON,
            "tier": SubscriptionStore.shared.effective.tier.rawValue,
            // محدودیت ۳۰ دقیقه فقط برای سطح رایگان است؛ هدیه و اشتراک
            // محدودیتی ندارند (۰ = بدون محدودیت).
            "sessionLimitMinutes": SubscriptionStore.shared.effective.tier == .free
                ? AppConstants.sessionLimitMinutes : 0,
            "serverRemark": server.displayName,
        ]
        manager.protocolConfiguration = proto
        manager.localizedDescription = "TAHA VPN 5G"
        manager.isEnabled = true
        do {
            // Xcode 26 SDK: these are async throws now.
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        } catch {
            lastError = NSLocalizedString("error_generic", comment: "")
            return
        }
        sessionConnectCount += 1
        currentServer = server
        connectedAt = Date()
        do {
            try manager.connection.startVPNTunnel()
        } catch {
            lastError = NSLocalizedString("error_generic", comment: "")
            return
        }
        // تایید واقعی تونل: IP خروجی باید عوض شده باشد.
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await self.verifyTunnel()
        }
    }

    /// IP خروجی فعلی؛ اگر با IP قبل از اتصال یکی باشد، تونل واقعی نیست.
    func verifyTunnel() async {
        guard status == .connected, let baseline = baselineIP else { return }
        guard let current = try? await fetchExitIP(), current != baseline else {
            // تونل تایید نشد — سرور بعدی را امتحان کن.
            await failover()
            return
        }
    }

    /// رفتن به سرور بعدی در صورت خرابی تونل.
    func failover() async {
        guard let current = currentServer else { return }
        let tier = SubscriptionStore.shared.effective.tier
        let pool = SubscriptionStore.shared.servers(for: tier)
        guard let idx = pool.firstIndex(of: current), idx + 1 < pool.count else {
            disconnect()
            lastError = NSLocalizedString("home_no_server", comment: "")
            return
        }
        await startTunnel(server: pool[idx + 1])
    }

    private func fetchExitIP() async throws -> String {
        let url = URL(string: "https://api.ipify.org?format=json")!
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = json["ip"] as? String else { throw URLError(.badServerResponse) }
        return ip
    }

    // MARK: - وضعیت

    private func loadManager() async {
        if manager != nil { return }
        let managers = try? await NETunnelProviderManager.loadAllFromPreferences()
        if let existing = managers?.first {
            manager = existing
        } else {
            manager = NETunnelProviderManager()
        }
        refreshStatus()
    }

    private func refreshStatus() {
        let newStatus = manager?.connection.status ?? .invalid
        if status != newStatus {
            status = newStatus
            if newStatus == .disconnected {
                connectedAt = nil
                SpeedMonitor.shared.reset()
            }
        }
    }

    var isConnected: Bool { status == .connected }
    var isConnecting: Bool { status == .connecting || status == .reasserting }
}
