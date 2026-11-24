import Foundation

/// پیکربندی از راه دور — `app_config.json` (همان قرارداد اندروید).
/// فایل خراب یا غایب هرگز اپ را از کار نمی‌اندازد؛ از نسخه‌ی کش‌شده و
/// در غیر این صورت از پیش‌فرض‌ها استفاده می‌شود.
struct RemoteAppConfig: Codable {
    var notice: String?
    var announcement: Announcement?
    var configSources: [String]?
    var codes: [PromoCode]?
    var plans: [Plan]?
    var paymentGateway: PaymentGateway?
    var trialEnabled: Bool?
    var trialHours: Int?
    var ads: AdConfig?

    enum CodingKeys: String, CodingKey {
        case notice, announcement
        case configSources = "config_sources"
        case codes, plans
        case paymentGateway = "payment_gateway"
        case trialEnabled = "trial_enabled"
        case trialHours = "trial_hours"
        case ads
    }

    static let defaults = RemoteAppConfig(
        notice: nil, announcement: nil, configSources: nil,
        codes: nil, plans: nil, paymentGateway: nil,
        trialEnabled: false, trialHours: 24, ads: nil)
}

struct Announcement: Codable, Equatable {
    var enabled: Bool?
    var text: String?
    var imageURL: String?
    var id: String?
    /// (۱٫۱٫۱۵) لینک اختیاری تبلیغ؛ زدن روی کارت یا عکس، لینک را باز می‌کند.
    var linkURL: String?

    enum CodingKeys: String, CodingKey {
        case enabled, text
        case imageURL = "image_url"
        case id
        case linkURL = "link_url"
    }

    /// فقط لینک HTTPS معتبر پذیرفته می‌شود.
    var validLink: URL? {
        guard let raw = linkURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let url = URL(string: raw),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }
}

struct PromoCode: Codable, Equatable {
    var code: String
    var type: String          // "discount" | "gift"
    var discountPercent: Int?
    var giftDays: Int?
    /// مدت هدیه به ساعت: ۱ / ۵ / ۲۴ / ۱۶۸ — بر gift_days اولویت دارد.
    var giftHours: Int?
    /// سطح هدیه: "gift" یا شناسه‌ی طرح (مثل "sub_12").
    var tier: String?
    var maxUses: Int?
    var remainingUses: Int?

    enum CodingKeys: String, CodingKey {
        case code, type
        case discountPercent = "discount_percent"
        case giftDays = "gift_days"
        case giftHours = "gift_hours"
        case tier
        case maxUses = "max_uses"
        case remainingUses = "remaining_uses"
    }

    var isGift: Bool { type.lowercased() == "gift" }
    /// مدت هدیه به ثانیه؛ gift_hours بر gift_days اولویت دارد.
    var giftDurationSeconds: TimeInterval? {
        if let h = giftHours { return TimeInterval(h * 3600) }
        if let d = giftDays { return TimeInterval(d * 86400) }
        return nil
    }
    var isExhausted: Bool { remainingUses == 0 }
}

struct Plan: Codable, Equatable, Identifiable {
    var id: String
    var days: Int?
    var period: String?
    var nameFa: String?
    var priceToman: Int?

    enum CodingKeys: String, CodingKey {
        case id, days, period
        case nameFa = "name_fa"
        case priceToman = "price_toman"
    }

    /// مدت به روز؛ days صریح اولویت دارد، بعد شناسه‌ی sub_*، بعد period.
    var durationDays: Int? {
        if let d = days { return d }
        switch id {
        case "sub_1": return 30
        case "sub_3": return 90
        case "sub_6": return 180
        case "sub_12": return 360
        default: break
        }
        switch period?.lowercased() {
        case "monthly": return 30
        case "yearly": return 365
        default: return nil
        }
    }

    /// طرح فقط وقتی نمایش داده می‌شود که شناسه، مدت معلوم و قیمت داشته باشد.
    var isDisplayable: Bool { durationDays != nil && priceToman != nil }
    var displayName: String { nameFa?.isEmpty == false ? nameFa! : id }
}

struct PaymentGateway: Codable {
    var enabled: Bool?
    var url: String?
    var merchantID: String?
    var callbackURL: String?
    var nameFa: String?

    enum CodingKeys: String, CodingKey {
        case enabled, url
        case merchantID = "merchant_id"
        case callbackURL = "callback_url"
        case nameFa = "name_fa"
    }
}
