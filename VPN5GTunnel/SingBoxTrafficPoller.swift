import Foundation

/// پایش سرعت زنده از Clash API داخلی sing-box (127.0.0.1:9090/traffic).
/// اختلاف بایت‌های تجمعی در هر ثانیه = سرعت لحظه‌ای. نتیجه در App Group
/// نوشته می‌شود تا اپ اصلی آن را بخواند. اگر API در دسترس نباشد، صفر
/// نوشته می‌شود — هرگز عدد ساختگی تولید نمی‌شود.
final class SingBoxTrafficPoller {
    private var timer: Timer?
    private var lastUp: Int64 = -1
    private var lastDown: Int64 = -1
    private let defaults: UserDefaults? =
        UserDefaults(suiteName: AppConstants.appGroupID)

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastUp = -1
        lastDown = -1
    }

    private func pollOnce() {
        guard let url = URL(string: "http://127.0.0.1:9090/traffic") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let up = json["up"] as? Int64,
                  let down = json["down"] as? Int64 else {
                self?.writeSpeed(up: 0, down: 0)
                return
            }
            if self.lastUp >= 0, self.lastDown >= 0 {
                self.writeSpeed(up: max(0, up - self.lastUp),
                                down: max(0, down - self.lastDown))
            }
            self.lastUp = up
            self.lastDown = down
        }.resume()
    }

    private func writeSpeed(up: Int64, down: Int64) {
        defaults?.set(up, forKey: "vpn5g_speed_up")
        defaults?.set(down, forKey: "vpn5g_speed_down")
        defaults?.set(Date().timeIntervalSince1970, forKey: "vpn5g_speed_updated_at")
    }
}
