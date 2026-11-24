import Foundation

/// وضعیت اشتراک کاربر — ترکیب ردیف سرور و هدیه‌ی محلی (همان منطق اندروید).
@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    @Published private(set) var serverStatus: SubscriptionStatus?
    @Published private(set) var giftStatus: SubscriptionStatus?
    @Published private(set) var effective: SubscriptionStatus = .free

    private let giftDefaultsKey = "vpn5g_gift_subscription_json"
    private let redeemedCodesKey = "vpn5g_redeemed_codes_json"

    private init() {
        loadGift()
        NotificationCenter.default.addObserver(
            forName: .authChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refreshServerStatus() }
            }
    }

    // MARK: - سرورها بر اساس سطح

    func servers(for tier: Tier) -> [ServerConfig] {
        let all = ConfigSync.shared.servers
        switch tier {
        case .free:
            return Array(all.prefix(AppConstants.freeServerCount))
        case .gift:
            return Array(all.prefix(AppConstants.giftServerCount))
        case .vip:
            return all
        }
    }

    // MARK: - ردیف سرور (RLS با توکن خود کاربر)

    func refreshServerStatus() async {
        guard let session = SupabaseAuth.shared.session else {
            serverStatus = nil
            recompute()
            return
        }
        let urlString = SupabaseConfig.url
            + "/rest/v1/vpn5g_registrations?select=subscription_status,subscription_expires_at,subscription_plan"
            + "&user_id=eq.\(session.userID)"
        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url, timeoutInterval: AppConstants.networkTimeout)
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            if let rows = try? JSONDecoder().decode([RegistrationRow].self, from: data),
               let row = rows.first {
                serverStatus = row.toStatus()
            }
        } catch {
            // خطا در خواندن، وضعیت کش‌شده را پاک نمی‌کند.
        }
        recompute()
    }

    // MARK: - ردیم کد (اعتبارسنجی از سمت سرور)

    enum RedeemResult {
        case success(SubscriptionStatus)
        case invalid(String)
    }

    /// کد اشتراک: اول RPC سرور، در صورت در دسترس نبودن فهرست پیکربندی.
    func redeemSubscriptionCode(_ code: String) async -> RedeemResult {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            return .invalid(NSLocalizedString("premium_code_bad", comment: ""))
        }
        if let validation = await SupabaseAuth.shared.validateAndRedeemCode(code: trimmed) {
            return applyValidation(validation, code: trimmed)
        }
        // بازگشت: فهرست پیکربندی (فقط وقتی RPC در دسترس نیست).
        if let match = ConfigSync.shared.remoteConfig.codes?
            .first(where: { $0.code.uppercased() == trimmed }), !match.isExhausted {
            if match.isGift {
                return applyGift(match, code: trimmed)
            }
            return .invalid(NSLocalizedString("premium_code_bad", comment: ""))
        }
        return .invalid(NSLocalizedString("premium_code_bad", comment: ""))
    }

    /// کد هدیه: فقط در بخش تمام مکان‌ها؛ مگر اینکه نوع هدیه مشخصاً اشتراک باشد.
    func redeemGiftCode(_ code: String) async -> RedeemResult {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            return .invalid(NSLocalizedString("locations_gift_bad", comment: ""))
        }
        if let validation = await SupabaseAuth.shared.validateAndRedeemCode(code: trimmed) {
            return applyValidation(validation, code: trimmed)
        }
        if let match = ConfigSync.shared.remoteConfig.codes?
            .first(where: { $0.code.uppercased() == trimmed && $0.isGift }), !match.isExhausted {
            return applyGift(match, code: trimmed)
        }
        return .invalid(NSLocalizedString("locations_gift_bad", comment: ""))
    }

    private func applyValidation(_ v: SupabaseAuth.CodeValidation, code: String) -> RedeemResult {
        guard v.valid else {
            return .invalid(v.message ?? NSLocalizedString("premium_code_bad", comment: ""))
        }
        let seconds: TimeInterval?
        if let h = v.giftHours { seconds = TimeInterval(h * 3600) }
        else if let d = v.giftDays { seconds = TimeInterval(d * 86400) }
        else if let plan = v.planID, let days = Plan(id: plan, days: nil, period: nil, nameFa: nil, priceToman: nil).durationDays {
            seconds = TimeInterval(days * 86400)
        } else { seconds = nil }
        let tier: Tier = (v.tier == "gift") ? .gift : .vip
        let status = SubscriptionStatus(
            tier: tier, planID: v.planID ?? v.tier,
            expiresAt: seconds.map { Date().addingTimeInterval($0) })
        if tier == .gift { storeGift(status) } else { giftStatus = status; saveGift() }
        markRedeemed(code)
        Task { await SupabaseAuth.shared.recordCodeRedemption(code: code) }
        recompute()
        return .success(status)
    }

    private func applyGift(_ match: PromoCode, code: String) -> RedeemResult {
        guard let seconds = match.giftDurationSeconds else {
            return .invalid(NSLocalizedString("locations_gift_bad", comment: ""))
        }
        let tier: Tier = (match.tier == "gift" || match.tier == nil) ? .gift : .vip
        let status = SubscriptionStatus(
            tier: tier, planID: match.tier,
            expiresAt: Date().addingTimeInterval(seconds))
        if tier == .gift { storeGift(status) } else { giftStatus = status; saveGift() }
        markRedeemed(code)
        Task { await SupabaseAuth.shared.recordCodeRedemption(code: code) }
        recompute()
        return .success(status)
    }

    // MARK: - نگهداری محلی

    private func storeGift(_ status: SubscriptionStatus) {
        giftStatus = status
        saveGift()
    }

    private func saveGift() {
        guard let gift = giftStatus,
              let data = try? JSONEncoder().encode(gift) else {
            UserDefaults.standard.removeObject(forKey: giftDefaultsKey)
            return
        }
        UserDefaults.standard.set(data, forKey: giftDefaultsKey)
    }

    private func loadGift() {
        guard let data = UserDefaults.standard.data(forKey: giftDefaultsKey),
              let gift = try? JSONDecoder().decode(SubscriptionStatus.self, from: data),
              gift.isActive else {
            giftStatus = nil
            return
        }
        giftStatus = gift
        recompute()
    }

    func clearLocal() {
        giftStatus = nil
        serverStatus = nil
        UserDefaults.standard.removeObject(forKey: giftDefaultsKey)
        recompute()
    }

    private func markRedeemed(_ code: String) {
        var list = (try? JSONDecoder().decode([String].self,
            from: UserDefaults.standard.data(forKey: redeemedCodesKey) ?? Data())) ?? []
        if !list.contains(code) { list.append(code) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: redeemedCodesKey)
        }
    }

    func isRedeemed(_ code: String) -> Bool {
        let list = (try? JSONDecoder().decode([String].self,
            from: UserDefaults.standard.data(forKey: redeemedCodesKey) ?? Data())) ?? []
        return list.contains(code)
    }

    private func recompute() {
        effective = SubscriptionStatus.effective(server: serverStatus, gift: giftStatus)
        writeTierToAppGroup()
    }

    /// سطح موثر را در گروه اشتراکی می‌نویسد تا افزونه‌ی تونل تایمر
    /// ۳۰ دقیقه‌ای را فقط برای سطح رایگان اعمال کند.
    private func writeTierToAppGroup() {
        UserDefaults(suiteName: AppConstants.appGroupID)?
            .set(effective.tier.rawValue, forKey: "vpn5g_tier")
    }
}
