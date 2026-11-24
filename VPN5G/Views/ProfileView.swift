import SwiftUI

/// صفحه‌ی «من»: حساب، اشتراک، پشتیبانی، ربات و کانال، راهنما، درباره.
struct ProfileView: View {
    @EnvironmentObject var auth: SupabaseAuth
    @EnvironmentObject var subscription: SubscriptionStore
    @State private var showAuth = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("profile_title")
                    .font(.system(size: 26, weight: .bold)).foregroundColor(.white)

                if auth.isSignedIn, let email = auth.email {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("profile_email").font(.headline).foregroundColor(.white)
                        Text(email).foregroundColor(.gray)
                        Text("profile_subscription").font(.headline).foregroundColor(.white)
                            .padding(.top, 8)
                        if subscription.effective.isActive {
                            Text(subscription.effective.planID ?? "")
                                .foregroundColor(Color(red: 0.85, green: 0.69, blue: 0.22))
                            if let days = subscription.effective.remainingDays {
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

                    Button("profile_sign_out") { auth.signOut() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                } else {
                    Button("profile_sign_in") { showAuth = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0, green: 0.9, blue: 0.8))
                }

                // پشتیبانی و ربات و کانال
                LinkRow(title: "profile_support", url: AppConstants.supportBotURL, icon: "headphones")
                LinkRow(title: "profile_bot", url: AppConstants.botURL, icon: "paperplane.fill")
                LinkRow(title: "profile_channel", url: AppConstants.channelURL, icon: "megaphone.fill")
                LinkRow(title: "profile_guide", url: AppConstants.botURL, icon: "book.fill")

                VStack(alignment: .leading, spacing: 4) {
                    Text("profile_about").font(.headline).foregroundColor(.white)
                    Text("\(NSLocalizedString("profile_version", comment: "")) 1.0.0")
                        .foregroundColor(.gray)
                    Text("profile_made_by").foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showAuth) { AuthView() }
    }
}

private struct LinkRow: View {
    var title: String
    var url: String
    var icon: String
    var body: some View {
        Button {
            if let link = URL(string: url) { UIApplication.shared.open(link) }
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Color(red: 0, green: 0.9, blue: 0.8))
                Text(LocalizedStringKey(title)).foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.left").foregroundColor(.gray)
            }
            .padding()
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
