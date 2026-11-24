import Foundation

/// تبلیغ تمام‌صفحه‌ی قبل از اتصال مجدد (قرارداد ۱٫۱٫۱۵).
///
/// قانون: اتصال اولِ هر بار اجرای اپ بدون تبلیغ است؛ از اتصال دوم به بعد،
/// تبلیغ قبل از شروع تونل نمایش داده می‌شود و تونل فقط بعد از مشاهده‌ی
/// کامل (پایان شمارش معکوس) شروع می‌شود. بستن زودهنگام = عدم مشاهده =
/// عدم اتصال. زمان با ساعت یکنواخت (systemUptime) اندازه‌گیری می‌شود،
/// نه ساعت دیواری — تغییر ساعت گوشی شمارنده را دور نمی‌زند.
@MainActor
final class AdManager: ObservableObject {
    static let shared = AdManager()

    @Published private(set) var interstitial: InterstitialAd?
    @Published private(set) var isShowingInterstitial = false
    @Published private(set) var countdownRemaining = 0

    private var completion: ((Bool) -> Void)?
    private var countdownTimer: Timer?
    private var countdownStartUptime: TimeInterval = 0
    private var countdownDuration: Int = 10

    private init() {}

    func update(from config: RemoteAppConfig) {
        interstitial = config.ads?.interstitial
    }

    /// آیا برای این اتصال باید تبلیغ نشان داده شود؟
    func shouldShowInterstitial(tier: Tier) -> Bool {
        guard let ad = interstitial, ad.isEnabled, ad.content?.hasContent == true else {
            return false
        }
        if tier != .free && ad.skipsSubscribers { return false }
        return true
    }

    var interstitialDuration: Int { interstitial?.clampedDuration ?? 10 }

    /// نمایش تبلیغ؛ `completion(true)` فقط وقتی صدا زده می‌شود که شمارش
    /// معکوس کامل شده باشد.
    func requestInterstitial(completion: @escaping (Bool) -> Void) {
        guard let ad = interstitial, ad.isEnabled else {
            completion(true)
            return
        }
        self.completion = completion
        countdownDuration = ad.clampedDuration
        countdownRemaining = countdownDuration
        countdownStartUptime = ProcessInfo.processInfo.systemUptime
        isShowingInterstitial = true
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        // زمان سپری‌شده از ساعت یکنواخت — نه ساعت دیواری.
        let elapsed = Int(ProcessInfo.processInfo.systemUptime - countdownStartUptime)
        let remaining = max(0, countdownDuration - elapsed)
        countdownRemaining = remaining
        if remaining <= 0 {
            finish(completed: true)
        }
    }

    /// کاربر تبلیغ را زود بست (یا صفحه ناخواسته بسته شد) — ناقص.
    func dismissEarly() {
        finish(completed: false)
    }

    private func finish(completed: Bool) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        isShowingInterstitial = false
        let adID = interstitial?.content?.text
        Task {
            await SupabaseAuth.shared.recordAdView(adID: adID, completed: completed)
        }
        let handler = completion
        completion = nil
        handler?(completed)
    }
}
