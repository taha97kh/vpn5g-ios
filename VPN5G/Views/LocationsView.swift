import SwiftUI

/// تمام مکان‌ها — دکمه‌ی کد هدیه مخصوص کد هدیه است و از کد خرید اشتراک
/// کاملاً جدا است. اینجا هیچ دکمه‌ای برای خرید اشتراک وجود ندارد.
struct LocationsView: View {
    @EnvironmentObject var sync: ConfigSync
    @EnvironmentObject var subscription: SubscriptionStore
    @EnvironmentObject var tunnel: TunnelManager
    @EnvironmentObject var auth: SupabaseAuth

    @State private var filter: LocationFilter = .all
    @State private var giftCode = ""
    @State private var giftMessage: String?
    @State private var giftIsError = false
    @State private var giftBusy = false
    @State private var showAuth = false

    enum LocationFilter { case all, subscription, free }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("locations_title")
                    .font(.system(size: 26, weight: .bold)).foregroundColor(.white)

                // دکمه‌ی کد هدیه — جدا و مخصوص کد هدیه.
                VStack(spacing: 10) {
                    TextField("locations_enter_gift", text: $giftCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Button {
                        Task { await redeemGift() }
                    } label: {
                        Text("locations_gift_code")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(red: 0, green: 0.9, blue: 0.8))
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(giftBusy || giftCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let giftMessage {
                        Text(giftMessage)
                            .foregroundColor(giftIsError ? .red : .green)
                            .font(.callout)
                    }
                }

                // قرص‌های شناور: اشتراکی اول، بعد رایگان.
                HStack(spacing: 8) {
                    FilterPill(title: "همه", selected: filter == .all) { filter = .all }
                    FilterPill(title: "اشتراکی", selected: filter == .subscription) {
                        filter = (filter == .subscription) ? .all : .subscription
                    }
                    FilterPill(title: "رایگان", selected: filter == .free) {
                        filter = (filter == .free) ? .all : .free
                    }
                }

                // گروه‌های کشوری — کشویی، پیش‌فرض بسته.
                let tier = subscription.effective.tier
                let visible = visibleServers(tier: tier)
                let grouped = Dictionary(grouping: visible, by: { $0.country })
                    .sorted { ($0.value.first?.pingMs ?? .max) < ($1.value.first?.pingMs ?? .max) }
                ForEach(grouped, id: \.key) { country, list in
                    let locked = isLocked(country: list.first?.countryCode ?? "XX", tier: tier)
                    CountryGroupView(title: "\(country) (\(list.count))", locked: locked, servers: list) { server in
                        if !locked { tunnel.requestConnect(server: server) }
                    }
                }
                if grouped.isEmpty {
                    Text("home_no_server").foregroundColor(.gray)
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showAuth) { AuthView() }
    }

    private func visibleServers(tier: Tier) -> [ServerConfig] {
        switch filter {
        case .all: return subscription.servers(for: tier) + lockedServers(tier: tier)
        case .subscription: return lockedServers(tier: tier)
        case .free: return subscription.servers(for: tier)
        }
    }

    /// سرورهایی که در سطح فعلی قفل‌اند (برای نمایش با قفل).
    private func lockedServers(tier: Tier) -> [ServerConfig] {
        switch tier {
        case .free: return Array(ConfigSync.shared.servers.dropFirst(AppConstants.freeServerCount))
        case .gift: return Array(ConfigSync.shared.servers.dropFirst(AppConstants.giftServerCount))
        case .vip: return []
        }
    }

    private func isLocked(country: String, tier: Tier) -> Bool {
        switch tier {
        case .vip: return false
        case .gift:
            return !Set(ConfigSync.shared.giftServers.map { $0.countryCode }).contains(country)
        case .free:
            return !Set(ConfigSync.shared.freeServers.map { $0.countryCode }).contains(country)
        }
    }

    private func redeemGift() async {
        guard auth.isSignedIn else { showAuth = true; return }
        giftBusy = true
        defer { giftBusy = false }
        let result = await subscription.redeemGiftCode(giftCode)
        switch result {
        case .success:
            giftMessage = NSLocalizedString("locations_gift_ok", comment: "")
            giftIsError = false
            giftCode = ""
        case .invalid(let text):
            giftMessage = text
            giftIsError = true
        }
    }
}

private struct FilterPill: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selected ? Color(red: 0, green: 0.9, blue: 0.8) : Color.white.opacity(0.08))
                .foregroundColor(selected ? .black : .white)
                .clipShape(Capsule())
        }
    }
}
