import SwiftUI

/// اجزای مشترک صفحه‌ها.

/// گروه کشوری کشویی — پیش‌فرض بسته؛ وضعیت باز/بسته در UserDefaults
/// ذخیره می‌شود تا در استفاده‌ی بعدی حفظ شود.
struct CountryGroupView: View {
    var title: String
    var locked: Bool
    var servers: [ServerConfig]
    var onSelect: ((ServerConfig) -> Void)?

    @State private var expanded: Bool = false

    private var storageKey: String { "vpn5g_country_open_\(title)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expanded.toggle()
                    UserDefaults.standard.set(expanded, forKey: storageKey)
                }
            } label: {
                HStack {
                    Text(title).foregroundColor(.white).font(.headline)
                    Spacer()
                    if locked {
                        Image(systemName: "lock.fill").foregroundColor(.gray)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(servers) { server in
                    ServerRowView(server: server, locked: locked) {
                        onSelect?(server)
                    }
                    .padding(.leading, 8)
                }
            }
        }
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            expanded = UserDefaults.standard.bool(forKey: storageKey)
        }
    }
}

/// یک ردیف سرور: نام، پینگ، قفل.
struct ServerRowView: View {
    var server: ServerConfig
    var locked: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(flagEmoji(for: server.countryCode))
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.displayName)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(server.country)
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill").foregroundColor(.gray)
                } else if let ping = server.pingMs {
                    Text("\(ping) ms")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(pingColor(ping))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    private func pingColor(_ ms: Int) -> Color {
        if ms < 150 { return Color(red: 0, green: 0.9, blue: 0.8) }
        if ms < 400 { return .yellow }
        return .orange
    }

    private func flagEmoji(for code: String) -> String {
        guard code.count == 2, code != "XX" else { return "🌐" }
        let base: UInt32 = 127397
        var result = ""
        for scalar in code.uppercased().unicodeScalars {
            guard let s = Unicode.Scalar(base + scalar.value) else { continue }
            result.append(Character(s))
        }
        return result
    }
}
