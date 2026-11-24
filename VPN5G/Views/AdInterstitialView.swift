import SwiftUI

/// تبلیغ تمام‌صفحه‌ی قبل از اتصال مجدد.
/// شمارش معکوس با ساعت یکنواخت انجام می‌شود؛ بستن زودهنگام یعنی مشاهده‌ی
/// ناقص و اتصال شروع نمی‌شود. بعد از پایان شمارش، اتصال خودکار شروع می‌شود.
struct AdInterstitialView: View {
    @EnvironmentObject var ads: AdManager

    var body: some View {
        ZStack {
            Color.black.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                if let content = ads.interstitial?.content {
                    if let imageURL = content.imageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } placeholder: { ProgressView() }
                        .frame(maxHeight: 320)
                        .onTapGesture { openLink(content) }
                    }
                    if let text = content.text, !text.isEmpty {
                        Text(text)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .onTapGesture { openLink(content) }
                    }
                    if content.validLink != nil {
                        Button("ad_open_link") { openLink(content) }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0, green: 0.9, blue: 0.8))
                    }
                }
                Spacer()
                if ads.countdownRemaining > 0 {
                    Text(String(format: NSLocalizedString("ad_countdown", comment: ""), ads.countdownRemaining))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text("ad_watch_full")
                        .font(.callout).foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                        .tint(.white)
                }
                Spacer().frame(height: 24)
            }
            .padding(24)
        }
    }

    private func openLink(_ content: AdContent) {
        if let url = content.validLink {
            UIApplication.shared.open(url)
        }
    }
}
