import Foundation
import NetworkExtension
import Libbox

/// پل میان sing-box (libbox) و NetworkExtension.
/// نکته‌ی مهم: نام دقیق متدهای پروتکل `LibboxPlatformInterfaceProtocol` و
/// توابع `LibboxSetup` / `LibboxNewService` باید در اولین بیلد مک با سربرگ
/// تولیدشده‌ی `Libbox-Swift.h` تطبیق داده شود؛ اسکریپت
/// `core/scripts/verify-libbox-api.sh` همین تطبیق را خودکار انجام می‌دهد.
/// اگر سربرگ متد بیشتری از این پروتکل داشت، برای آن یک پیاده‌سازی خالی
/// (false/nil) اضافه کنید تا تطبیق پروتکل کامل شود.
final class LibboxPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol {
    weak var provider: PacketTunnelProvider?

    // MARK: - Local DNS
    // از DNS خودِ sing-box (بخش dns در پیکربندی) استفاده می‌شود.
    func localDNSTransport() -> LibboxLocalDNSTransportProtocol? { nil }

    // MARK: - Interface control / monitoring
    // هیچ‌کدام را پلتفرم تامین نمی‌کند؛ sing-box از پیاده‌سازی داخلی Go
    // استفاده می‌کند.
    func usePlatformAutoDetectInterfaceControl() -> Bool { false }
    func autoDetectInterfaceControl(_ fd: Int32) throws {}
    func useProcFS() -> Bool { false }

    func findConnectionOwner(_ ipProtocol: Int32, _ sourceAddress: String?, _ sourcePort: Int32,
                             _ destinationAddress: String?, _ destinationPort: Int32) throws -> LibboxConnectionOwner? {
        throw NSError(domain: "vpn5g.libbox", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "FindConnectionOwner not implemented"])
    }

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        // v1: اعلان تغییر شبکه پیاده نشده؛ در صورت تغییر شبکه، کاربر دوباره
        // وصل می‌شود. (بهبود آینده: NWPathMonitor.)
    }
    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {}

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol? {
        // فهرست خالی؛ sing-box مسیر پیش‌فرض را خودش پیدا می‌کند.
        EmptyNetworkInterfaceIterator()
    }

    // MARK: - Network Extension
    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }

    // MARK: - Wi-Fi / certificates / DNS cache
    func readWIFIState() -> LibboxWIFIState? { nil }
    func systemCertificates() -> LibboxStringIteratorProtocol? { EmptyStringIterator() }
    func clearDNSCache() {}

    // MARK: - Notifications (اعلان‌های سیستم در افزونه استفاده نمی‌شود)
    func sendNotification(_ notification: LibboxNotification?) throws {}
    func cancelNotification(_ identifier: String?, _ typeID: Int32) throws {}

    // MARK: - OpenTun
    /// sing-box هنگام Start، این متد را صدا می‌زند. تنظیمات تونل ساخته و
    /// اعمال می‌شود و توصیف‌گر فایل (fd) رابط utun برگردانده می‌شود.
    /// روش گرفتن fd (الگوی به‌کاررفته در کلاینت‌های واقعی sing-box در iOS):
    /// اول `packetFlow.value(forKeyPath: "socket.fileDescriptor")` و اگر
    /// نشد، جست‌وجوی fd در میان توصیف‌گرها با getpeername (کنترل utun).
    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_ ret: UnsafeMutablePointer<Int32>?) throws {
        guard let provider, let options else {
            throw NSError(domain: "vpn5g.libbox", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Missing provider or tun options"])
        }
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())
            var dnsError: NSError?
            if let dnsServer = options.getDNSServerAddress(&dnsError) {
                settings.dnsSettings = NEDNSSettings(servers: [dnsServer])
            }
            var addresses: [String] = []
            var masks: [String] = []
            if let iterator = options.getInet4Address() {
                while iterator.hasNext() {
                    if let prefix = iterator.next() {
                        addresses.append(prefix.address() ?? "")
                        masks.append(prefix.prefix() ?? "")
                    }
                }
            }
            if !addresses.isEmpty {
                settings.ipv4Settings = NEIPv4Settings(addresses: addresses, subnetMasks: masks)
                settings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
            }
        }
        if options.isHTTPProxyEnabled() {
            let proxy = NEProxySettings()
            proxy.httpServer = NEProxyServer(address: options.getHTTPProxyServer() ?? "",
                                             port: Int(options.getHTTPProxyServerPort()))
            proxy.httpsServer = proxy.httpServer
            proxy.autoProxyConfigurationEnabled = false
            settings.proxySettings = proxy
        }

        let semaphore = DispatchSemaphore(value: 0)
        var applyError: Error?
        Task {
            do {
                try await provider.setTunnelNetworkSettings(settings)
            } catch {
                applyError = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let applyError { throw applyError }

        if let fd = provider.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret?.pointee = fd
            return
        }
        if let fd = findTunnelFileDescriptor() {
            ret?.pointee = fd
            return
        }
        throw NSError(domain: "vpn5g.libbox", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Could not obtain tunnel file descriptor"])
    }

    /// جست‌وجوی سوکت کنترل utun در میان توصیف‌گرهای باز
    /// (AF_SYSTEM با sc_id == 2 یعنی utun). روش مستند برای iOS 15 به بعد.
    private func findTunnelFileDescriptor() -> Int32? {
        for fd in Int32(0)..<Int32(1024) {
            var addr = sockaddr_ctl()
            var len = socklen_t(MemoryLayout<sockaddr_ctl>.size)
            let result = withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getpeername(fd, $0, &len)
                }
            }
            if result == 0,
               addr.sc_family == sa_family_t(AF_SYSTEM),
               addr.sc_id == 2 {
                return fd
            }
        }
        return nil
    }
}

// MARK: - Empty iterators (gomobile iterator protocols)

final class EmptyStringIterator: NSObject, LibboxStringIteratorProtocol {
    func hasNext() -> Bool { false }
    func next() -> String? { nil }
}

final class EmptyNetworkInterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    func hasNext() -> Bool { false }
    func next() -> LibboxNetworkInterface? { nil }
}
