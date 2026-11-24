import Foundation
import Security

/// احراز هویت سوپابیس — REST مستقیم GoTrue (بدون SDK).
/// فقط رمز عبور؛ کد یکبارمصرف وجود ندارد. یک حساب برای هر IP و هر ایمیل.
final class SupabaseAuth: ObservableObject {
    static let shared = SupabaseAuth()

    @Published private(set) var session: AuthSession?
    @Published private(set) var email: String?

    private let keychainService = "com.taha97kh.vpn5g.auth"

    struct AuthSession: Codable {
        var accessToken: String
        var refreshToken: String?
        var userID: String
        var email: String
    }

    enum AuthError: LocalizedError {
        case network
        case invalidCredentials
        case emailRegistered
        case ipRegistered
        case weakPassword
        case emailNotConfirmed
        case rateLimited
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .network: return NSLocalizedString("auth_network", comment: "")
            case .invalidCredentials: return NSLocalizedString("auth_invalid", comment: "")
            case .emailRegistered: return NSLocalizedString("auth_email_registered", comment: "")
            case .ipRegistered: return NSLocalizedString("auth_ip_registered", comment: "")
            case .weakPassword: return NSLocalizedString("auth_password_short", comment: "")
            case .emailNotConfirmed: return NSLocalizedString("auth_network", comment: "")
            case .rateLimited: return NSLocalizedString("auth_network", comment: "")
            case .unknown(let m): return m
            }
        }
    }

    private init() { loadSession() }

    // MARK: - جلسه

    var isSignedIn: Bool { session != nil }

    func signOut() {
        session = nil
        email = nil
        deleteKeychain()
        SubscriptionStore.shared.clearLocal()
        NotificationCenter.default.post(name: .authChanged, object: nil)
    }

    // MARK: - ثبت‌نام (فقط رمز عبور)

    /// ثبت‌نام: IP عمومی → بررسی ثبت‌نام → signup → ثبت حساب.
    /// اگر IP یا ایمیل قبلاً ثبت شده باشد، خطای دقیق برمی‌گردد.
    func signUp(email: String, password: String) async throws {
        let ip = try await fetchPublicIP()
        let free = try await checkRegistration(email: email, ip: ip)
        guard free else { throw AuthError.ipRegistered }
        let body: [String: Any] = ["email": email, "password": password]
        let (data, status) = try await authRequest(path: "/auth/v1/signup", method: "POST", body: body)
        if status == 422 {
            throw AuthError.emailRegistered
        }
        guard status == 200 || status == 201 else {
            throw mapError(data: data, status: status)
        }
        guard let sess = parseSession(data: data, email: email) else {
            // کاربر ساخته شد ولی جلسه برنگشت (مثلاً تایید ایمیل روشن شده
            // باشد) — به صفحه‌ی ورود برمی‌گردیم.
            throw AuthError.emailNotConfirmed
        }
        saveSession(sess)
        // ثبت حساب در جدول — بهترین تلاش؛ UNIQUE(ip) پشتوانه‌ی مسابقه است.
        await registerAccount(email: email, ip: ip)
        await linkOwnUserID()
        NotificationCenter.default.post(name: .authChanged, object: nil)
    }

    func signIn(email: String, password: String) async throws {
        let body: [String: Any] = ["email": email, "password": password]
        let (data, status) = try await authRequest(
            path: "/auth/v1/token?grant_type=password", method: "POST", body: body)
        guard status == 200 else { throw mapError(data: data, status: status) }
        guard let sess = parseSession(data: data, email: email) else { throw AuthError.network }
        saveSession(sess)
        await linkOwnUserID()
        NotificationCenter.default.post(name: .authChanged, object: nil)
    }

    /// بازیابی رمز عبور با لینک (vpn5g://auth/callback).
    func sendRecoveryLink(email: String) async throws {
        let body: [String: Any] = ["email": email, "redirect_to": SupabaseConfig.recoveryRedirect]
        let (_, status) = try await authRequest(path: "/auth/v1/recover", method: "POST", body: body)
        guard status == 200 else { throw AuthError.network }
    }

    // MARK: - IP و RPCهای ثبت‌نام

    /// IP عمومی از تابع لبه‌ی سوپابیس (نه از سایت‌های دیگر).
    func fetchPublicIP() async throws -> String {
        let url = URL(string: SupabaseConfig.url + "/functions/v1/get-client-ip")!
        var req = URLRequest(url: url, timeoutInterval: AppConstants.networkTimeout)
        req.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = json["ip"] as? String, !ip.isEmpty else { throw AuthError.network }
        return ip
    }

    /// true یعنی ایمیل و IP هر دو آزادند.
    func checkRegistration(email: String, ip: String) async throws -> Bool {
        let (data, status) = try await rpc(name: "check_registration",
                                            params: ["p_email": email, "p_ip": ip])
        guard status == 200 else { throw AuthError.network }
        if let arr = try? JSONDecoder().decode([Bool].self, from: data), let first = arr.first {
            return first
        }
        return false
    }

    @discardableResult
    func registerAccount(email: String, ip: String) async -> Bool {
        let (data, status) = try? await rpc(name: "register_account",
                                             params: ["p_email": email, "p_ip": ip]) ?? (Data(), 0)
        guard status == 200 else { return false }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    /// اتصال شناسه‌ی کاربر به ردیف ثبت‌نام (بهترین تلاش).
    @discardableResult
    func linkOwnUserID() async -> Bool {
        guard session != nil else { return false }
        let (data, status) = try? await rpc(name: "set_own_user_id", params: [:], authed: true) ?? (Data(), 0)
        guard status == 200 else { return false }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    // MARK: - اعتبارسنجی کد از سمت سرور (قرارداد ۱٫۱٫۱۵)

    struct CodeValidation: Codable {
        var valid: Bool
        var type: String?
        var giftHours: Int?
        var giftDays: Int?
        var tier: String?
        var planID: String?
        var expiresAt: String?
        var message: String?

        enum CodingKeys: String, CodingKey {
            case valid, type
            case giftHours = "gift_hours"
            case giftDays = "gift_days"
            case tier
            case planID = "plan_id"
            case expiresAt = "expires_at"
            case message
        }
    }

    /// اعتبارسنجی + مصرف اتمی کد در سرور. در صورت در دسترس نبودن RPC،
    /// nil برمی‌گردد تا فراخواننده از فهرست پیکربندی استفاده کند.
    func validateAndRedeemCode(code: String) async -> CodeValidation? {
        guard let email = email ?? session?.email else { return nil }
        guard let (data, status) = try? await rpc(
            name: "validate_and_redeem_code",
            params: ["p_code": code, "p_email": email]) else { return nil }
        guard status == 200 else { return nil }
        return try? JSONDecoder().decode(CodeValidation.self, from: data)
    }

    /// ثبت ردیم کد (بهترین تلاش؛ هرگز ردیم را خراب نمی‌کند).
    @discardableResult
    func recordCodeRedemption(code: String) async -> Bool {
        guard let email = email ?? session?.email else { return false }
        guard let (data, status) = try? await rpc(
            name: "record_code_redemption",
            params: ["p_code": code, "p_email": email]) else { return false }
        guard status == 200 else { return false }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    /// ثبت مشاهده‌ی تبلیغ (تایید سمت سرور).
    @discardableResult
    func recordAdView(adID: String?, completed: Bool) async -> Bool {
        var params: [String: Any] = ["p_completed": completed]
        if let id = adID { params["p_ad_id"] = id }
        if let uid = session?.userID { params["p_user_id"] = uid }
        guard let (data, status) = try? await rpc(name: "record_ad_view", params: params) else { return false }
        guard status == 200 else { return false }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    // MARK: - درخواست‌های پایه

    private func authRequest(path: String, method: String, body: [String: Any]) async throws -> (Data, Int) {
        let url = URL(string: SupabaseConfig.url + path)!
        var req = URLRequest(url: url, timeoutInterval: AppConstants.networkTimeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
        } catch { throw AuthError.network }
    }

    private func rpc(name: String, params: [String: Any], authed: Bool = false) async throws -> (Data, Int) {
        let url = URL(string: SupabaseConfig.url + "/rest/v1/rpc/" + name)!
        var req = URLRequest(url: url, timeoutInterval: AppConstants.networkTimeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if authed, let token = session?.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            req.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: params)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
        } catch { throw AuthError.network }
    }

    private func parseSession(data: Data, email: String) -> AuthSession? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String,
              let user = json["user"] as? [String: Any],
              let uid = user["id"] as? String else { return nil }
        return AuthSession(accessToken: token,
                           refreshToken: json["refresh_token"] as? String,
                           userID: uid, email: email)
    }

    private func mapError(data: Data, status: Int) -> AuthError {
        if status == 400 || status == 401 { return .invalidCredentials }
        if status == 422 { return .emailRegistered }
        if status == 429 { return .rateLimited }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["msg"] as? String ?? json["message"] as? String {
            if msg.contains("already registered") { return .emailRegistered }
            if msg.contains("Password should be") { return .weakPassword }
            return .unknown(msg)
        }
        return .network
    }

    // MARK: - Keychain

    private func saveSession(_ sess: AuthSession) {
        session = sess
        email = sess.email
        guard let data = try? JSONEncoder().encode(sess) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "session",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "session",
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let sess = try? JSONDecoder().decode(AuthSession.self, from: data) else { return }
        session = sess
        email = sess.email
    }

    private func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "session",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension Notification.Name {
    static let authChanged = Notification.Name("vpn5g.authChanged")
}
