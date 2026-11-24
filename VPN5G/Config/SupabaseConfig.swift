import Foundation

/// پیکربندی سوپابیس — همان پروژه‌ی نسخه اندروید.
///
/// پروژه‌ی «vpn5g.irbot@gmail.com's Project» (eu-west-1)، شناسه‌ی
/// atvcpfnnmwguhjvhbbfj. احراز هویت با ایمیل فعال و «Confirm email»
/// خاموش است؛ ثبت‌نام مستقیم بلافاصله جلسه برمی‌گرداند. کد یکبارمصرف
/// حذف شده است (اندروید ۱٫۱٫۹).
///
/// کلید زیر، کلید عمومی (anon) سوپابیس است — کلید سمت کاربر که به‌صورت
/// طراحی‌شده در کد اپ قرار می‌گیرد (همان مقدار در نسخه اندروید).
/// کلید service-role و رمز دیتابیس هرگز نباید اینجا قرار بگیرد.
enum SupabaseConfig {
    static let url = "https://atvcpfnnmwguhjvhbbfj.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF0dmNwZm5ubXdndWhqdmhiYmZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU0MzQ1MjUsImV4cCI6MjExMTAxMDUyNX0.4Xm5jUrfVP3rkGBFbWaaY6xJ9BBBONaWzevUNbFg6J4"
    /// نشانی بازگشت لینک بازیابی رمز عبور (در پنل سوپابیس ثبت شده است).
    static let recoveryRedirect = "vpn5g://auth/callback"
}
