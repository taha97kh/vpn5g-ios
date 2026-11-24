import Foundation

/// یک سرور پروکسی پارس‌شده از URI (vmess / vless / trojan / ss).
/// فقط فیلدهای لازم برای ساخت پیکربندی هسته نگه داشته می‌شود؛ هیچ
/// URI کاملی در لاگ یا حافظه‌ی دائمی نوشته نمی‌شود.
struct ServerConfig: Identifiable, Equatable {
    let id = UUID()
    let scheme: String            // "vmess" | "vless" | "trojan" | "ss"
    let host: String
    let port: Int
    let remark: String
    let country: String           // نام نمایشی کشور (فارسی)
    let countryCode: String       // کد دوحرفی (مثل "FR") یا "XX"
    let uuid: String?             // vmess / vless
    let password: String?         // trojan / ss
    let security: String?         // vmess: aes-128-gcm و غیره
    let network: String?          // ws / tcp / grpc / http
    let tls: Bool
    let sni: String?
    let path: String?
    let hostHeader: String?
    let flow: String?
    let alterID: Int?
    let method: String?           // ss: روش رمزنگاری (مثل aes-256-gcm)
    let realityPublicKey: String? // vless reality: pbk
    let realityShortID: String?   // vless reality: sid
    /// پینگ TCP اندازه‌گیری‌شده (میلی‌ثانیه)؛ nil یعنی پینگ نشده.
    var pingMs: Int?
    /// کلید یکتاسازی: scheme://host:port:identity
    var dedupeKey: String { "\(scheme)://\(host):\(port):\(uuid ?? password ?? "")" }

    var displayName: String { remark.isEmpty ? host : remark }

    // MARK: - پارس URI

    static func parse(uri: String) -> ServerConfig? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hash = trimmed.range(of: "://") else { return nil }
        let scheme = String(trimmed[..<hash.lowerBound]).lowercased()
        guard ["vmess", "vless", "trojan", "ss"].contains(scheme) else { return nil }
        switch scheme {
        case "vmess": return parseVMess(trimmed)
        case "vless": return parseVLESS(trimmed)
        case "trojan": return parseTrojan(trimmed)
        case "ss": return parseShadowsocks(trimmed)
        default: return nil
        }
    }

    private static func remarkAndQuery(_ s: String) -> (String, [String: String]) {
        var remark = ""
        var rest = s
        if let frag = rest.range(of: "#") {
            remark = String(rest[frag.upperBound...])
                .removingPercentEncoding ?? String(rest[frag.upperBound...])
            rest = String(rest[..<frag.lowerBound])
        }
        var query: [String: String] = [:]
        if let q = rest.range(of: "?") {
            let qs = String(rest[q.upperBound...])
            rest = String(rest[..<q.lowerBound])
            for pair in qs.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    query[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                }
            }
        }
        return (remark, query)
    }

    private static func parseVMess(_ s: String) -> ServerConfig? {
        let b64 = String(s.dropFirst("vmess://".count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: paddedBase64(b64)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = json["add"] as? String, !host.isEmpty,
              let portRaw = json["port"],
              let port = Int("\(portRaw)"),
              let id = json["id"] as? String else { return nil }
        let remark = (json["ps"] as? String) ?? ""
        let (country, code) = countryFromRemark(remark)
        return ServerConfig(
            scheme: "vmess", host: host, port: port, remark: remark,
            country: country, countryCode: code, uuid: id, password: nil,
            security: json["scy"] as? String, network: json["net"] as? String,
            tls: (json["tls"] as? String)?.lowercased() == "tls",
            sni: json["sni"] as? String, path: json["path"] as? String,
            hostHeader: json["host"] as? String, flow: nil,
            alterID: Int("\(json["aid"] as? Int ?? 0)"),
            method: nil, realityPublicKey: nil, realityShortID: nil)
    }

    private static func parseVLESS(_ s: String) -> ServerConfig? {
        let body = String(s.dropFirst("vless://".count))
        let (remark, query) = remarkAndQuery(body)
        guard let at = body.range(of: "@") else { return nil }
        let uuid = String(body[..<at.lowerBound])
        let hostPort = String(body[at.upperBound...]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let hp = hostPort.split(separator: ":")
        guard hp.count == 2, let port = Int(hp[1]) else { return nil }
        let host = String(hp[0])
        let (country, code) = countryFromRemark(remark)
        return ServerConfig(
            scheme: "vless", host: host, port: port, remark: remark,
            country: country, countryCode: code, uuid: uuid, password: nil,
            security: query["security"], network: query["type"],
            tls: ["tls", "reality"].contains(query["security"]?.lowercased() ?? ""),
            sni: query["sni"], path: query["path"],
            hostHeader: query["host"], flow: query["flow"], alterID: nil,
            method: nil, realityPublicKey: query["pbk"], realityShortID: query["sid"])
    }

    private static func parseTrojan(_ s: String) -> ServerConfig? {
        let body = String(s.dropFirst("trojan://".count))
        let (remark, query) = remarkAndQuery(body)
        guard let at = body.range(of: "@") else { return nil }
        let password = String(body[..<at.lowerBound]).removingPercentEncoding ?? String(body[..<at.lowerBound])
        let hostPort = String(body[at.upperBound...]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let hp = hostPort.split(separator: ":")
        guard hp.count == 2, let port = Int(hp[1]) else { return nil }
        let host = String(hp[0])
        let (country, code) = countryFromRemark(remark)
        return ServerConfig(
            scheme: "trojan", host: host, port: port, remark: remark,
            country: country, countryCode: code, uuid: nil, password: password,
            security: nil, network: query["type"], tls: true,
            sni: query["sni"], path: query["path"],
            hostHeader: query["host"], flow: query["flow"], alterID: nil,
            method: nil, realityPublicKey: nil, realityShortID: nil)
    }

    private static func parseShadowsocks(_ s: String) -> ServerConfig? {
        // ss://base64(method:password)@host:port#remark  یا  ss://base64(method:password@host:port)
        var body = String(s.dropFirst("ss://".count))
        let (remark, _) = remarkAndQuery(body)
        if let frag = body.range(of: "#") { body = String(body[..<frag.lowerBound]) }
        if let q = body.range(of: "?") { body = String(body[..<q.lowerBound]) }
        var decoded = body
        if !body.contains("@") {
            let b64 = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            guard let data = Data(base64Encoded: paddedBase64(b64)),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            decoded = text
        } else if let at = body.range(of: "@") {
            let head = String(body[..<at.lowerBound])
            let b64 = head.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            if let data = Data(base64Encoded: paddedBase64(b64)),
               let text = String(data: data, encoding: .utf8) {
                decoded = text + "@" + String(body[at.upperBound...])
            }
        }
        guard let at = decoded.range(of: "@") else { return nil }
        let userinfo = String(decoded[..<at.lowerBound])
        let hostPort = String(decoded[at.upperBound...])
        let hp = hostPort.split(separator: ":")
        guard hp.count == 2, let port = Int(hp[1]) else { return nil }
        let password: String
        let method: String
        if let colon = userinfo.range(of: ":") {
            method = String(userinfo[..<colon.lowerBound])
            password = String(userinfo[colon.upperBound...])
        } else { method = "aes-256-gcm"; password = userinfo }
        let host = String(hp[0])
        let (country, code) = countryFromRemark(remark)
        return ServerConfig(
            scheme: "ss", host: host, port: port, remark: remark,
            country: country, countryCode: code, uuid: nil, password: password,
            security: nil, network: "tcp", tls: false,
            sni: nil, path: nil, hostHeader: nil, flow: nil, alterID: nil,
            method: method, realityPublicKey: nil, realityShortID: nil)
    }

    private static func paddedBase64(_ s: String) -> String {
        var out = s
        while out.count % 4 != 0 { out += "=" }
        return out
    }

    // MARK: - کشور از روی برچسب

    /// پرچم ایموجی و نام کشور در برچسب را به (نام فارسی، کد) تبدیل می‌کند.
    /// اگر برچسب کشور نداشته باشد، «بین‌الملل» برمی‌گردد — هرگز کشور
    /// حدس زده نمی‌شود.
    static func countryFromRemark(_ remark: String) -> (String, String) {
        let flags: [(String, String, String)] = [
            ("🇫🇷", "فرانسه", "FR"), ("🇩🇪", "آلمان", "DE"), ("🇬🇧", "انگلیس", "GB"),
            ("🇺🇸", "آمریکا", "US"), ("🇨🇦", "کانادا", "CA"), ("🇳🇱", "هلند", "NL"),
            ("🇹🇷", "ترکیه", "TR"), ("🇦🇪", "امارات", "AE"), ("🇮🇷", "ایران", "IR"),
            ("🇯🇵", "ژاپن", "JP"), ("🇰🇷", "کره جنوبی", "KR"), ("🇸🇬", "سنگاپور", "SG"),
            ("🇦🇺", "استرالیا", "AU"), ("🇨🇭", "سوئیس", "CH"), ("🇸🇪", "سوئد", "SE"),
            ("🇳🇴", "نروژ", "NO"), ("🇫🇮", "فنلاند", "FI"), ("🇵🇱", "لهستان", "PL"),
            ("🇮🇹", "ایتالیا", "IT"), ("🇪🇸", "اسپانیا", "ES"), ("🇷🇺", "روسیه", "RU"),
            ("🇮🇳", "هند", "IN"), ("🇧🇷", "برزیل", "BR"), ("🇦🇹", "اتریش", "AT"),
            ("🇧🇪", "بلژیک", "BE"), ("🇩🇰", "دانمارک", "DK"), ("🇮🇪", "ایرلند", "IE"),
            ("🇵🇹", "پرتغال", "PT"), ("🇷🇴", "رومانی", "RO"), ("🇺🇦", "اوکراین", "UA"),
            ("🇹🇼", "تایوان", "TW"), ("🇭🇰", "هنگ‌کنگ", "HK"), ("🇮🇱", "اسرائیل", "IL"),
            ("🇿🇦", "آفریقای جنوبی", "ZA"), ("🇲🇽", "مکزیک", "MX"), ("🇦🇷", "آرژانتین", "AR"),
        ]
        for (flag, name, code) in flags where remark.contains(flag) {
            return (name, code)
        }
        let lowered = remark.lowercased()
        let names: [(String, String, String)] = [
            ("france", "فرانسه", "FR"), ("germany", "آلمان", "DE"), ("netherlands", "هلند", "NL"),
            ("usa", "آمریکا", "US"), ("united states", "آمریکا", "US"), ("canada", "کانادا", "CA"),
            ("turkey", "ترکیه", "TR"), ("japan", "ژاپن", "JP"), ("singapore", "سنگاپور", "SG"),
            ("فرانسه", "فرانسه", "FR"), ("آلمان", "آلمان", "DE"), ("هلند", "هلند", "NL"),
            ("آمریکا", "آمریکا", "US"), ("کانادا", "کانادا", "CA"), ("ترکیه", "ترکیه", "TR"),
            ("انگلیس", "انگلیس", "GB"), ("ژاپن", "ژاپن", "JP"),
        ]
        for (needle, name, code) in names where lowered.contains(needle.lowercased()) {
            return (name, code)
        }
        return ("بین‌الملل", "XX")
    }
}
