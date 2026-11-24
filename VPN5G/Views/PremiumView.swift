import SwiftUI

/// بخش ویژه — محیط اختصاصی اشتراک.
/// ساختار: عنوان → توضیح کوتاه → دکمه‌ی ثبت کد (بالای صفحه) →
/// وضعیت اشتراک → زمان باقی‌مانده → کشورهای قفل‌شده (کشویی، بسته) →
/// طرح‌ها → خرید از ربات (فقط یک دکمه).
struct PremiumView: View {
    @EnvironmentObject var subscription: SubscriptionStore
    @EnvironmentObject var sync: ConfigSync
    @EnvironmentObject var auth: SupabaseAuth

    @State private var code = ""
    @State private var message: String?
    @State private var isError = false
    @State private var isBusy = false
    @State private var showAuth = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("premium_title")
                    .font(.system(size: 26, weight: .bold)).foregroundColor(.white)
                Text("premium_subtitle")
                    .foregroundColor(.gray)

                // دکمه‌ی ثبت کد — بالای صفحه.
                VStack(spacing: 10) {
                    TextField("premium_enter_code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Button {
                        Task { await redeem() }
                    } label: {
                        Text("premium_register_code")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(red: 0.85, green: 0.69, blue: 0.22))
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isBusy || code.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let message {
                        Text(message)
                            .foregroundColor(isError ? .red : .green)
                            .font(.callout)
                    }
                }

                // وضعیت اشتراک
                SubscriptionStatusCard(status: subscription.effective)

                // کشورهای قفل‌شده — کشویی، پیش‌فرض بسته.
                LockedCountriesSection(
                    servers: sync.servers,
                    unlocked: subscription.effective.tier == .vip,
                    giftUnlockedCountries: giftCountries
                )

                // طرح‌ها از سرور (بدون قیمت ثابت در اپ).
                if let plans = sync.remoteConfig.plans?.filter({ $0.isDisplayable }), !plans.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(plans.sorted(by: { ($0.durationDays ?? 0) < ($1.durationDays ?? 0) })) { plan in
                            PlanCard(plan: plan)
                        }
                    }
                }

                // خرید اشتراک — فقط یک دکمه‌ی باز کردن ربات.
                Button("premium_open_bot") {
                    if let url = URL(string: AppConstants.botURL) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0, green: 0.9, blue: 0.8))
                .frame(maxWidth: .infinity)

                Text("profile_made_by")
                    .font(.system(size: 12)).foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showAuth) { AuthView() }
    }

    private var giftCountries: Set<String> {
        guard subscription.effective.tier == .gift else { return [] }
        return Set(ConfigSync.shared.giftServers.map { $0.countryCode })
    }

    private func redeem() async {
        guard auth.isSignedIn else { showAuth = true; return }
        isBusy = true
        defer { isBusy = false }
        let result = await subscription.redeemSubscriptionCode(code)
        switch result {
        case .success:
            message = NSLocalizedString("premium_code_ok", comment: "")
            isError = false
            code = ""
        case .invalid(let text):
            message = text
            isError = true
        }
    }
}

private struct SubscriptionStatusCard: View {
    var status: SubscriptionStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("premium_status").font(.headline).foregroundColor(.white)
            if status.isActive {
                Text(status.planID ?? "")
                    .foregroundColor(Color(red: 0.85, green: 0.69, blue: 0.22))
                if let days = status.remainingDays {
                    Text(String(format: NSLocalizedString("premium_days_left", comment: ""), days))
                        .foregroundColor(.white)
                }
            } else {
                Text("premium_no_subscription").foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct PlanCard: View {
    var plan: Plan
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.displayName).foregroundColor(.white).font(.headline)
                if let days = plan.durationDays {
                    Text("\(days) روز").foregroundColor(.gray).font(.caption)
                }
            }
            Spacer()
            if let price = plan.priceToman {
                Text("\(price) تومان").foregroundColor(.white)
            }
            Button("premium_buy") {
                if let url = URL(string: AppConstants.buyURL(planID: plan.id)) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .tint(Color(red: 0, green: 0.9, blue: 0.8))
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// کشورهای قفل‌شده: گروه‌بندی‌شده، کشویی، پیش‌فرض بسته.
/// وضعیت باز/بسته در UserDefaults ذخیره می‌شود.
private struct LockedCountriesSection: View {
    var servers: [ServerConfig]
    var unlocked: Bool
    var giftUnlockedCountries: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("premium_locked_countries")
                .font(.headline).foregroundColor(.white)
            let grouped = Dictionary(grouping: servers, by: { $0.country })
                .sorted { $0.value.count > $1.value.count }
            ForEach(grouped, id: \.key) { country, list in
                let code = list.first?.countryCode ?? "XX"
                let isOpen = unlocked || giftUnlockedCountries.contains(code)
                CountryGroupView(
                    title: "\(country) (\(list.count))",
                    locked: !isOpen,
                    servers: list,
                    onSelect: nil
                )
            }
            if grouped.isEmpty {
                Text("home_no_server").foregroundColor(.gray)
            }
        }
    }
}
