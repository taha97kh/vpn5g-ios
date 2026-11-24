import SwiftUI

/// نقطه‌ی ورود اپ — TAHA VPN 5G.
/// صفحه‌ی شروع تا آماده‌شدن واقعی لیست سرورها نمایش داده می‌شود؛ بعد
/// تب‌های اصلی باز می‌شوند. همه‌ی متن‌ها فارسی است.
@main
struct VPN5GApp: App {
    @StateObject private var sync = ConfigSync.shared
    @StateObject private var tunnel = TunnelManager.shared
    @StateObject private var subscription = SubscriptionStore.shared
    @StateObject private var ads = AdManager.shared
    @StateObject private var auth = SupabaseAuth.shared

    @State private var started = false
    @State private var showAuth = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if started {
                    MainTabs()
                        .environmentObject(sync)
                        .environmentObject(tunnel)
                        .environmentObject(subscription)
                        .environmentObject(ads)
                        .environmentObject(auth)
                } else {
                    StartupView(onReady: { started = true })
                }
                if ads.isShowingInterstitial {
                    AdInterstitialView()
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showAuth) {
                AuthView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .authChanged)) { _ in
                if !auth.isSignedIn { showAuth = false }
            }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("خانه", systemImage: "house.fill") }
            PremiumView()
                .tabItem { Label("ویژه", systemImage: "crown.fill") }
            LocationsView()
                .tabItem { Label("تمام مکان‌ها", systemImage: "globe") }
            ProfileView()
                .tabItem { Label("من", systemImage: "person.fill") }
        }
        .tint(Color(red: 0, green: 0.9, blue: 0.8))
    }
}
