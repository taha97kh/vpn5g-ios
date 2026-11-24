import Foundation
import NetworkExtension
import Libbox

/// افزونه‌ی تونل VPN. چرخه‌ی زندگی:
/// startTunnel → خواندن پیکربندی sing-box از providerConfiguration →
/// LibboxSetup → LibboxNewService → service.start() (در این مرحله
/// OpenTun صدا زده می‌شود و تونل ساخته می‌شود) → شروع تایمر ۳۰ دقیقه‌ای
/// برای سطح رایگان/هدیه → شروع پایش سرعت.
/// stopTunnel → service.close().
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var boxService: LibboxBoxService?
    private var platformInterface: LibboxPlatformInterface?
    private var sessionTimer: DispatchWorkItem?
    private var trafficPoller: SingBoxTrafficPoller?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let configJSON = protocolConfiguration.providerConfiguration?["serverJSON"] as? String,
              !configJSON.isEmpty else {
            completionHandler(NSError(domain: "vpn5g.tunnel", code: 10,
                                      userInfo: [NSLocalizedDescriptionKey: "Missing sing-box config"]))
            return
        }
        let sessionLimitMinutes = (protocolConfiguration.providerConfiguration?["sessionLimitMinutes"] as? NSNumber)?.intValue ?? 30

        let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID)
        let basePath = groupURL?.appendingPathComponent("libbox").path ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)

        let platformInterface = LibboxPlatformInterface()
        platformInterface.provider = self
        self.platformInterface = platformInterface

        do {
            // sing-box v1.11.8: Setup takes ONE LibboxSetupOptions object
            // (base/working/temp paths), not four separate arguments.
            let setupOptions = LibboxSetupOptions()
            setupOptions.basePath = basePath
            setupOptions.workingPath = basePath
            setupOptions.tempPath = NSTemporaryDirectory()
            setupOptions.isTVOS = false
            try LibboxSetup(setupOptions)

            let service = try LibboxNewService(configJSON, platformInterface)
            self.boxService = service
            try service.start()
        } catch {
            completionHandler(error)
            return
        }

        // تایمر جلسه: فقط برای سطح رایگان و هدیه (۳۰ دقیقه)؛ اشتراک VIP
        // محدودیتی ندارد. مقدار ۰ یعنی بدون محدودیت.
        if sessionLimitMinutes > 0 {
            let item = DispatchWorkItem { [weak self] in
                self?.cancelTunnelWithError(NSError(domain: "vpn5g.tunnel", code: 11,
                                                    userInfo: [NSLocalizedDescriptionKey: "Session limit reached"]))
            }
            sessionTimer = item
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(sessionLimitMinutes * 60), execute: item)
        }

        trafficPoller = SingBoxTrafficPoller()
        trafficPoller?.start()
        completionHandler(nil)
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        sessionTimer?.cancel()
        sessionTimer = nil
        trafficPoller?.stop()
        trafficPoller = nil
        if let service = boxService {
            try? service.close()
            boxService = nil
        }
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // پیام از اپ اصلی (مثلاً درخواست قطع) — در v1 فقط قطع پشتیبانی می‌شود.
        if let text = String(data: messageData, encoding: .utf8), text == "stop" {
            cancelTunnelWithError(nil)
        }
        completionHandler?(nil)
    }
}
