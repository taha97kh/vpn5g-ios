import SwiftUI
import NetworkExtension

/// صفحه‌ی اصلی: دکمه‌ی اتصال، سرعت زنده، کارت اطلاعیه، سرورهای توصیه‌شده.
struct HomeView: View {
    @EnvironmentObject var sync: ConfigSync
    @EnvironmentObject var tunnel: TunnelManager
    @EnvironmentObject var subscription: SubscriptionStore
    @EnvironmentObject var ads: AdManager
    @EnvironmentObject var auth: SupabaseAuth
    @StateObject private var speeds = SpeedMonitor.shared

    @State private var showAuth = false
    @State private var dismissedAnnouncement: String? = UserDefaults.standard.string(forKey: "vpn5g_announcement_dismissed")

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // سربرگ برند
                Text("TAHA VPN 5G")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)

                // دایره‌ی اتصال
                ConnectCircle(
                    status: tunnel.status,
                    onTap: connectTapped
                )

                // سرعت زنده (فقط تونل؛ صفر واقعی = صفر)
                if tunnel.isConnected {
                    HStack(spacing: 24) {
                        SpeedChip(label: "home_download", value: speeds.downloadText, icon: "arrow.down.circle.fill")
                        SpeedChip(label: "home_upload", value: speeds.uploadText, icon: "arrow.up.circle.fill")
                    }
                    .onAppear { speeds.start() }
                    .onDisappear { speeds.stop() }
                }

                // کارت اطلاعیه (با لینک اختیاری)
                if let ann = sync.remoteConfig.announcement,
                   ann.enabled == true, let text = ann.text, !text.isEmpty,
                   dismissedAnnouncement != (ann.id ?? text) {
                    AnnouncementCard(announcement: ann) {
                        UserDefaults.standard.set(ann.id ?? text, forKey: "vpn5g_announcement_dismissed")
                        dismissedAnnouncement = ann.id ?? text
                    }
                }

                // توصیه‌شده
                if !sync.freeServers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("home_recommended")
                            .font(.headline).foregroundColor(.white)
                        ForEach(sync.freeServers.prefix(3)) { server in
                            ServerRowView(server: server, locked: false) {
                                tunnel.requestConnect(server: server)
                            }
                        }
                    }
                }

                Button("home_update_servers") {
                    Task { await sync.refresh() }
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 0, green: 0.9, blue: 0.8))
                .disabled(sync.isSyncing)

                if sync.servers.isEmpty && !sync.isSyncing {
                    Text("home_no_server").foregroundColor(.gray)
                }

                Text("profile_made_by")
                    .font(.system(size: 12)).foregroundColor(.gray)
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showAuth) { AuthView() }
        .onChange(of: tunnel.status) { status in
            if status == .connected { speeds.start() } else { speeds.stop() }
        }
    }

    private func connectTapped() {
        if tunnel.isConnected || tunnel.isConnecting {
            tunnel.disconnect()
            return
        }
        guard auth.isSignedIn else {
            showAuth = true
            return
        }
        let tier = subscription.effective.tier
        let pool = subscription.servers(for: tier)
        guard let server = pool.first else { return }
        tunnel.requestConnect(server: server)
    }
}

private struct SpeedChip: View {
    var label: String
    var value: String
    var icon: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(Color(red: 0, green: 0.9, blue: 0.8))
            Text(LocalizedStringKey(label)).foregroundColor(.gray).font(.caption)
            Text(value).foregroundColor(.white).font(.system(.body, design: .monospaced))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct AnnouncementCard: View {
    var announcement: Announcement
    var onDismiss: () -> Void
    @State private var showLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(announcement.text ?? "")
                    .foregroundColor(.white)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark").foregroundColor(.gray)
                }
            }
            if let imageURL = announcement.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                } placeholder: { ProgressView() }
                .onTapGesture { openLink() }
            }
            if announcement.validLink != nil {
                Button("ad_open_link") { openLink() }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0, green: 0.9, blue: 0.8))
            }
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { openLink() }
    }

    private func openLink() {
        if let url = announcement.validLink {
            UIApplication.shared.open(url)
        }
    }
}

private struct ConnectCircle: View {
    var status: NEVPNStatus
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(status == .connected
                          ? Color(red: 0, green: 0.9, blue: 0.8)
                          : Color.white.opacity(0.08))
                    .frame(width: 180, height: 180)
                VStack(spacing: 4) {
                    Image(systemName: status == .connected ? "bolt.fill" : "power")
                        .font(.system(size: 44))
                        .foregroundColor(status == .connected ? .black : .white)
                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(status == .connected ? .black : .white)
                    Text("4ref.ai")
                        .font(.caption)
                        .foregroundColor(status == .connected ? .black.opacity(0.7) : .gray)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        switch status {
        case .connected: return NSLocalizedString("home_connected", comment: "")
        case .connecting, .reasserting: return NSLocalizedString("home_connecting", comment: "")
        default: return NSLocalizedString("home_connect", comment: "")
        }
    }
}
