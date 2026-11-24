import Foundation

/// ساخت پیکربندی JSON هسته‌ی sing-box از یک سرور انتخاب‌شده.
/// خروجی همان ساختاری است که libbox با `NewService` می‌خواند:
/// ورودی TUN سیستمی + خروجی پروکسی + DNS + قوانین مسیریابی +
/// رابط Clash برای آمار ترافیک زنده.
enum SingBoxConfigBuilder {

    /// پورت محلی رابط Clash (فقط روی 127.0.0.1) برای خواندن سرعت.
    static let clashPort = 9090

    static func buildJSON(server: ServerConfig) -> String? {
        guard let outbound = outboundJSON(server: server) else { return nil }
        let config: [String: Any] = [
            "log": ["level": "warn", "disabled": false],
            "dns": [
                "servers": [
                    ["tag": "proxy-dns", "address": "8.8.8.8", "detour": "proxy"],
                    ["tag": "local-dns", "address": "223.5.5.5", "detour": "direct"],
                ],
                "rules": [
                    ["geosite": "category-ads-all", "server": "block"],
                ],
                "final": "proxy-dns",
                "strategy": "ipv4_only",
            ],
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "interface_name": "utun9",
                "address": ["172.19.0.1/30"],
                "mtu": 9000,
                "auto_route": true,
                "strict_route": true,
                "endpoint_independent_nat": true,
                "stack": "system",
            ]],
            "outbounds": [
                outbound,
                ["type": "direct", "tag": "direct"],
                ["type": "block", "tag": "block"],
                ["type": "dns", "tag": "dns-out"],
            ],
            "route": [
                "rules": [
                    ["action": "sniff"],
                    ["protocol": "dns", "action": "hijack-dns"],
                    ["ip_is_private": true, "outbound": "direct"],
                    ["geosite": "category-ads-all", "action": "reject"],
                ],
                "final": "proxy",
                "auto_detect_interface": true,
            ],
            "experimental": [
                "clash_api": [
                    "external_controller": "127.0.0.1:\(clashPort)",
                    "external_ui": "",
                    "secret": "",
                    "default_mode": "global",
                ],
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private static func outboundJSON(server: ServerConfig) -> [String: Any]? {
        var out: [String: Any] = ["tag": "proxy", "server": server.host, "server_port": server.port]
        switch server.scheme {
        case "vless":
            guard let uuid = server.uuid else { return nil }
            out["type"] = "vless"
            out["uuid"] = uuid
            if let flow = server.flow, !flow.isEmpty { out["flow"] = flow }
            addTLS(&out, server: server)
            addTransport(&out, server: server)
        case "vmess":
            guard let uuid = server.uuid else { return nil }
            out["type"] = "vmess"
            out["uuid"] = uuid
            out["alter_id"] = server.alterID ?? 0
            out["security"] = server.security ?? "auto"
            addTLS(&out, server: server)
            addTransport(&out, server: server)
        case "trojan":
            guard let password = server.password else { return nil }
            out["type"] = "trojan"
            out["password"] = password
            addTLS(&out, server: server, forceTLS: true)
            addTransport(&out, server: server)
        case "ss":
            guard let password = server.password else { return nil }
            out["type"] = "shadowsocks"
            out["method"] = server.method ?? "aes-256-gcm"
            out["password"] = password
        default:
            return nil
        }
        return out
    }

    private static func addTLS(_ out: inout [String: Any], server: ServerConfig, forceTLS: Bool = false) {
        guard forceTLS || server.tls else { return }
        var tls: [String: Any] = ["enabled": true]
        if let sni = server.sni, !sni.isEmpty { tls["server_name"] = sni }
        if server.security?.lowercased() == "reality" {
            var reality: [String: Any] = ["enabled": true]
            if let key = server.realityPublicKey, !key.isEmpty { reality["public_key"] = key }
            if let sid = server.realityShortID, !sid.isEmpty { reality["short_id"] = sid }
            tls["reality"] = reality
        }
        // uTLS برای عبور از فیلترینگ؛ هسته در صورت عدم پشتیبانی نادیده می‌گیرد.
        tls["utls"] = ["enabled": true, "fingerprint": "chrome"]
        out["tls"] = tls
    }

    private static func addTransport(_ out: inout [String: Any], server: ServerConfig) {
        guard let network = server.network?.lowercased(), network != "tcp" else { return }
        switch network {
        case "ws":
            var ws: [String: Any] = [:]
            if let path = server.path, !path.isEmpty { ws["path"] = path }
            if let host = server.hostHeader, !host.isEmpty {
                ws["headers"] = ["Host": host]
            }
            out["transport"] = ["type": "ws"] + ws
        case "grpc":
            out["transport"] = ["type": "grpc", "service_name": server.path ?? ""]
        case "http":
            out["transport"] = ["type": "http", "path": server.path ?? "/"]
        default:
            break
        }
    }
}

// جمع دو دیکشنری برای ساخت transport در یک خط.
private func + (lhs: [String: Any], rhs: [String: Any]) -> [String: Any] {
    var out = lhs
    for (k, v) in rhs { out[k] = v }
    return out
}
