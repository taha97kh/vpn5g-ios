import Foundation

/// TAHA VPN 5G — ثابت‌های سراسری اپ (همان قرارداد نسخه اندروید).
/// هیچ مقدار تجاری اینجا ثابت نشده است؛ طرح‌ها، قیمت‌ها و کدها فقط از
/// پیکربندی از راه دور خوانده می‌شوند.
enum AppConstants {
    /// گروه اشتراکی بین اپ و افزونه‌ی تونل (سرعت زنده، وضعیت اتصال).
    static let appGroupID = "group.com.taha97kh.vpn5g"
    /// شناسه‌ی باندل افزونه‌ی تونل.
    static let tunnelBundleID = "com.taha97kh.vpn5g.PacketTunnel"

    static let liveJSON = "https://taha97kh-vpn5g-app.static.hf.space/live_configs.json"
    static let subTxt = "https://taha97kh-vpn5g-app.static.hf.space/sub.txt"
    static let appConfigURL = "https://taha97kh-vpn5g-app.static.hf.space/app_config.json"

    static let githubSource1 = "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/verified/configs.txt"
    static let githubSource2 = "https://raw.githubusercontent.com/barry-far/V2ray-Config/main/All_Configs_Sub.txt"
    static let githubSource3 = "https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/iran.txt"
    static let githubSource4 = "https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/best.txt"
    static let githubSource5 = "https://raw.githubusercontent.com/Alirewa/V2ray-Configs/main/config.txt"
    static let githubSource6 = "https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/super-sub.txt"

    static let defaultConfigSources: [String] = [
        liveJSON, subTxt,
        githubSource1, githubSource2, githubSource3,
        githubSource4, githubSource5, githubSource6,
    ]
    /// منابع بزرگ فقط همین تعداد خط در هر بروزرسانی پینگ می‌شوند.
    static let githubSourcePingCap = 300

    static let botURL = "https://t.me/VPN5G_IRBot"
    static let channelURL = "https://t.me/VPNCRACKNET"
    static let supportBotURL = "https://t.me/VPN5G_IRBot?start=support"

    /// آدرس خرید یک طرح؛ ربات مبلغ یکتای قابل پرداخت را برای همان سفارش می‌سازد.
    static func buyURL(planID: String) -> String { "\(botURL)?start=buy_\(planID)" }
    static func redeemURL(code: String) -> String { "\(botURL)?start=redeem_\(code)" }

    /// تعداد سرورهای رایگان: سریع‌ترین‌ها بر اساس پینگ واقعی.
    static let freeServerCount = 20
    /// سطح هدیه: ۵۰ سرور سریع.
    static let giftServerCount = 50
    /// محدودیت جلسه‌ی رایگان (دقیقه)؛ مشترک و هدیه محدودیت ندارند.
    static let sessionLimitMinutes = 30
    /// فاصله‌ی بروزرسانی پیکربندی (ثانیه).
    static let configRefreshInterval: TimeInterval = 300
    /// مهلت درخواست‌های شبکه (ثانیه).
    static let networkTimeout: TimeInterval = 15
}
