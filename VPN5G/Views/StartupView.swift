import SwiftUI

/// صفحه‌ی شروع — پیشرفت واقعی ۰ تا ۱۰۰٪ + متن‌های چرخان.
/// بارگذاری سریع است: اول از کش استفاده می‌شود و بروزرسانی سنگین در
/// پس‌زمینه انجام می‌شود؛ ۱۰۰٪ فقط بعد از آماده‌شدن واقعی نمایش داده
/// می‌شود. بدون اینترنت، اپ در بارگذاری گیر نمی‌کند.
struct StartupView: View {
    var onReady: () -> Void

    @StateObject private var sync = ConfigSync.shared
    @State private var messageIndex = 0
    @State private var failed = false

    private let messages = [
        "startup_msg_security", "startup_msg_tunnel", "startup_msg_fast",
        "startup_msg_route", "startup_msg_status", "startup_msg_update",
        "startup_msg_stable", "startup_msg_premium", "startup_msg_quality",
        "startup_msg_power", "startup_msg_secure", "startup_msg_almost",
        "startup_msg_launch",
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.02, green: 0.09, blue: 0.08)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                // لوگوی شفاف PNG با انیمیشن ضربان ملایم.
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .modifier(PulseEffect())
                // موشن‌گرافیک نام اپ: درخشش متحرک روی نوشته.
                AnimatedBrandText(text: "TAHA VPN 5G")
                    .padding(.top, 16)
                Text("4ref.ai")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(red: 0, green: 0.9, blue: 0.8))
                    .padding(.top, 4)
                Spacer().frame(height: 48)
                if failed {
                    Text("startup_no_server")
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("startup_retry") { retry() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0, green: 0.9, blue: 0.8))
                        .padding(.top, 16)
                } else {
                    Text(LocalizedStringKey(messages[messageIndex]))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                        .id(messageIndex)
                    ProgressView(value: Double(sync.progress), total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(Color(red: 0, green: 0.9, blue: 0.8))
                        .padding(.top, 16)
                    Text("\(Int(sync.progress * 100))٪")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                }
                Spacer()
                Text("profile_made_by")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 32)
        }
        .onAppear { start() }
        .onChange(of: sync.progress) { value in
            if value >= 1.0 && !sync.servers.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onReady() }
            } else if value >= 1.0 && sync.servers.isEmpty {
                failed = true
            }
        }
        .onReceive(Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                messageIndex = (messageIndex + 1) % messages.count
            }
        }
    }

    private func start() {
        failed = false
        // اگر کش سرور داریم، سریع وارد شو و بروزرسانی را در پس‌زمینه انجام بده.
        Task {
            await sync.refresh()
            AdManager.shared.update(from: sync.remoteConfig)
            await SubscriptionStore.shared.refreshServerStatus()
        }
    }

    private func retry() {
        failed = false
        start()
    }
}

/// ضربان ملایم لوگو (مقیاس ۱ تا ۱٫۰۶ و شناوری عمودی، چرخه‌ی ۲ ثانیه‌ای).
private struct PulseEffect: ViewModifier {
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(y: offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    scale = 1.06
                    offset = -6
                }
            }
    }
}

/// نوشته‌ی برند با درخشش متحرک (گرادیان متحرک روی متن).
private struct AnimatedBrandText: View {
    let text: String
    @State private var phase: CGFloat = 0
    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, Color(red: 0, green: 0.9, blue: 0.8), .white],
                    startPoint: .init(x: phase - 0.5, y: 0),
                    endPoint: .init(x: phase + 0.5, y: 0))
            )
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}
