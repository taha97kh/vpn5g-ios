import Foundation

/// سطح دسترسی کاربر.
enum Tier: String, Codable {
    /// رایگان: ۲۰ سرور سریع + قطع ۳۰ دقیقه‌ای.
    case free
    /// هدیه: ۵۰ سرور سریع، بدون قطع ۳۰ دقیقه‌ای تا پایان مدت هدیه.
    case gift
    /// اشتراک کامل: همه‌ی سرورها، بدون محدودیت زمانی.
    case vip
}

/// وضعیت اشتراک کاربر — ترکیب دو منبع حقیقت (همان منطق اندروید):
/// ردیف سرور (فعال‌سازی توسط ربات) و هدیه‌ی فعال‌شده با کد.
/// اشتراک موثر، دیرتر منقضی‌شونده‌ی این دو است.
struct SubscriptionStatus: Codable, Equatable {
    var tier: Tier
    var planID: String?
    var expiresAt: Date?

    static let free = SubscriptionStatus(tier: .free, planID: nil, expiresAt: nil)

    var isActive: Bool {
        guard tier != .free else { return false }
        guard let exp = expiresAt else { return tier == .vip }
        return exp > Date()
    }

    var remainingDays: Int? {
        guard let exp = expiresAt else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
        return max(0, days)
    }

    /// ترکیب دو وضعیت: دیرتر منقضی‌شونده برنده است؛ اشتراک کامل همیشه
    /// بر هدیه اولویت دارد.
    static func effective(server: SubscriptionStatus?, gift: SubscriptionStatus?) -> SubscriptionStatus {
        let candidates = [server, gift].compactMap { $0 }.filter { $0.isActive }
        if candidates.contains(where: { $0.tier == .vip }) {
            return candidates.filter { $0.tier == .vip }
                .max(by: { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }) ?? .free
        }
        return candidates.max(by: { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }) ?? .free
    }
}

/// ردیف اشتراک کاربر در جدول `vpn5g_registrations` (خوانده‌شده با توکن
/// خود کاربر از طریق RLS).
struct RegistrationRow: Codable {
    var subscriptionStatus: String?
    var subscriptionExpiresAt: String?
    var subscriptionPlan: String?

    enum CodingKeys: String, CodingKey {
        case subscriptionStatus = "subscription_status"
        case subscriptionExpiresAt = "subscription_expires_at"
        case subscriptionPlan = "subscription_plan"
    }

    func toStatus() -> SubscriptionStatus? {
        guard subscriptionStatus?.lowercased() == "active" else { return nil }
        let exp: Date?
        if let raw = subscriptionExpiresAt {
            exp = ISO8601DateFormatter().date(from: raw)
        } else { exp = nil }
        let tier: Tier = (subscriptionPlan == "gift") ? .gift : .vip
        return SubscriptionStatus(tier: tier, planID: subscriptionPlan, expiresAt: exp)
    }
}
