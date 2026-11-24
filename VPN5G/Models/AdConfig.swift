import Foundation

/// سیستم تبلیغات (قرارداد ۱٫۱٫۱۵ — همان اندروید).
/// همه‌ی مقادیر از سرور خوانده می‌شوند؛ هیچ قیمتی در اپ ثابت نیست.
struct AdConfig: Codable {
    var interstitial: InterstitialAd?
    var prices: AdPrices?
}

struct InterstitialAd: Codable {
    var enabled: Bool?
    var durationSeconds: Int?
    var skipForSubscribers: Bool?
    var content: AdContent?

    enum CodingKeys: String, CodingKey {
        case enabled
        case durationSeconds = "duration_seconds"
        case skipForSubscribers = "skip_for_subscribers"
        case content
    }

    /// مدت نمایش؛ بازه‌ی مجاز ۱ تا ۲۰ ثانیه، پیش‌فرض ۱۰.
    var clampedDuration: Int {
        let d = durationSeconds ?? 10
        return min(20, max(1, d))
    }

    var isEnabled: Bool { enabled ?? false }
    var skipsSubscribers: Bool { skipForSubscribers ?? true }
}

struct AdContent: Codable, Equatable {
    var text: String?
    var imageURL: String?
    var linkURL: String?

    enum CodingKeys: String, CodingKey {
        case text
        case imageURL = "image_url"
        case linkURL = "link_url"
    }

    var validLink: URL? {
        guard let raw = linkURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let url = URL(string: raw),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    var hasContent: Bool {
        (text?.isEmpty == false) || (imageURL?.isEmpty == false)
    }
}

/// قیمت مدل‌های تبلیغاتی (تومان) — فقط از سرور؛ نبودن قیمت یعنی آن مدل
/// در دسترس نیست.
struct AdPrices: Codable {
    var once: Int?
    var tenTimes: Int?
    var hourly: Int?
    var monthly: Int?

    enum CodingKeys: String, CodingKey {
        case once
        case tenTimes = "ten_times"
        case hourly
        case monthly
    }
}
