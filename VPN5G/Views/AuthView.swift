import SwiftUI

/// ورود / ثبت‌نام — فقط ایمیل و رمز عبور؛ کد یکبارمصرف وجود ندارد.
struct AuthView: View {
    @EnvironmentObject var auth: SupabaseAuth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSignup = false
    @State private var showRecovery = false
    @State private var error: String?
    @State private var busy = false
    @State private var linkSent = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    Image("Logo")
                        .resizable().scaledToFit().frame(width: 96, height: 96)
                    Text("TAHA VPN 5G")
                        .font(.system(size: 24, weight: .bold)).foregroundColor(.white)

                    TextField("auth_email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding().background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    SecureField("auth_password", text: $password)
                        .padding().background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if isSignup {
                        SecureField("auth_password_confirm", text: $confirmPassword)
                            .padding().background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let error {
                        Text(error).foregroundColor(.red).font(.callout)
                    }
                    if linkSent {
                        Text("auth_link_sent").foregroundColor(.green).font(.callout)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Text(isSignup ? "auth_signup" : "auth_login")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(red: 0, green: 0.9, blue: 0.8))
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(busy)

                    Button(isSignup ? "profile_sign_in" : "profile_sign_up") {
                        isSignup.toggle()
                        error = nil
                    }
                    .foregroundColor(Color(red: 0, green: 0.9, blue: 0.8))

                    if !isSignup {
                        Button("auth_forgot") { showRecovery = true }
                            .foregroundColor(.gray)
                    }
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel") { dismiss() }.foregroundColor(.white)
                }
            }
            .alert("auth_forgot", isPresented: $showRecovery) {
                Button("auth_send_link") {
                    Task {
                        do {
                            try await auth.sendRecoveryLink(email: email)
                            linkSent = true
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                Button("common_cancel", role: .cancel) {}
            } message: {
                Text("auth_email")
            }
        }
    }

    private func submit() async {
        error = nil
        guard password.count >= 6 else {
            error = NSLocalizedString("auth_password_short", comment: "")
            return
        }
        if isSignup && password != confirmPassword {
            error = NSLocalizedString("auth_password_mismatch", comment: "")
            return
        }
        busy = true
        defer { busy = false }
        do {
            if isSignup {
                try await auth.signUp(email: email, password: password)
            } else {
                try await auth.signIn(email: email, password: password)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
