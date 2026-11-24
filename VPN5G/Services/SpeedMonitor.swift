import Foundation

/// سرعت زنده‌ی دانلود/آپلود — خوانده‌شده از گروه اشتراکی که افزونه‌ی
/// تونل هر ثانیه در آن می‌نویسد (آمار رابط Clash هسته).
/// صفر فقط وقتی نمایش داده می‌شود که واقعاً ترافیکی نباشد یا تونل قطع
/// باشد؛ هیچ عددی ساخته نمی‌شود.
@MainActor
final class SpeedMonitor: ObservableObject {
    static let shared = SpeedMonitor()

    @Published private(set) var downloadSpeed: Int64 = 0  // بایت بر ثانیه
    @Published private(set) var uploadSpeed: Int64 = 0

    private var timer: Timer?
    private var lastDown: Int64 = -1
    private var lastUp: Int64 = -1
    private var lastAt: Date?

    private init() {}

    var downloadText: String { Self.format(downloadSpeed) }
    var uploadText: String { Self.format(uploadSpeed) }

    static func format(_ bytesPerSecond: Int64) -> String {
        let b = max(0, bytesPerSecond)
        switch b {
        case 0..<1024: return "\(b) B/s"
        case 1024..<(1024 * 1024):
            return String(format: "%.1f KB/s", Double(b) / 1024)
        default:
            return String(format: "%.2f MB/s", Double(b) / (1024 * 1024))
        }
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        stop()
        downloadSpeed = 0
        uploadSpeed = 0
        lastDown = -1
        lastUp = -1
        lastAt = nil
    }

    private func poll() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupID) else { return }
        let down = defaults.object(forKey: "tunnel_down_bytes") as? Int64 ?? -1
        let up = defaults.object(forKey: "tunnel_up_bytes") as? Int64 ?? -1
        let now = Date()
        guard down >= 0, up >= 0 else {
            downloadSpeed = 0
            uploadSpeed = 0
            return
        }
        if lastDown >= 0, lastUp >= 0, let last = lastAt {
            let dt = max(0.1, now.timeIntervalSince(last))
            // پرش غیرمنطقی (ریست شمارنده) را به صفر تبدیل کن، نه عدد منفی.
            let dDown = max(0, down - lastDown)
            let dUp = max(0, up - lastUp)
            downloadSpeed = Int64(Double(dDown) / dt)
            uploadSpeed = Int64(Double(dUp) / dt)
        }
        lastDown = down
        lastUp = up
        lastAt = now
    }
}
