# Contracts — TAHA VPN 5G iOS (v1.0.0)

The iOS app talks to exactly the same backends as the Android app. Nothing
here invents a new endpoint: every URL, RPC, and JSON field below is the
Android contract (see `../vpn5g-app/vpn5g-android/docs/app_config.md` and
`Vpn5gAuthConfig.kt` / `Vpn5gConstants.kt`). The iOS-only additions are the
`ads` block and the server-side validation RPCs, which the Android 1.1.15
work defines with the same names.

## 1. Remote config — `app_config.json`

Fetched from `https://taha97kh-vpn5g-app.static.hf.space/app_config.json`
on every app start, every 5 minutes while open, and on manual refresh.
Missing/malformed file → cached copy, otherwise built-in defaults; never a
crash, never invented data.

| Field | Type | Meaning |
|---|---|---|
| `notice` | string \| null | Short notice on home. |
| `announcement` | object \| null | Home announcement card (see §2). |
| `config_sources` | [string] | Extra config sources (in addition to the 8 built-ins). |
| `codes` | [object] \| null | Gift/discount codes (see §3). |
| `plans` | [object] \| null | Subscription plans (see §3). |
| `payment_gateway` | object \| null | Bank gateway; `enabled:false` → coming soon, route to bot. |
| `trial_enabled` / `trial_hours` | bool / int | 24h free trial flag (display only; granting is bot-side). |
| `ads` | object \| null | Ad system (see §4). |

### Built-in config sources (same 8 as Android)

1. `https://taha97kh-vpn5g-app.static.hf.space/live_configs.json` (41 entries, fully ping-tested)
2. `https://taha97kh-vpn5g-app.static.hf.space/sub.txt` (base64-wrapped)
3. `https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/verified/configs.txt`
4. `https://raw.githubusercontent.com/barry-far/V2ray-Config/main/All_Configs_Sub.txt`
5. `https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/iran.txt`
6. `https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/best.txt`
7. `https://raw.githubusercontent.com/Alirewa/V2ray-Configs/main/config.txt`
8. `https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/super-sub.txt`

Cap: 300 lines per GitHub source per refresh (evenly-spaced spread); the HF
lists are fully tested. HARD RULE: a config with no measured ping is never
shown. Free tier = 20 fastest-pinging configs; gift tier = top 50; VIP =
full pool.

## 2. Announcement / ads (`announcement` + `ads`)

`announcement`: `{ enabled, text, image_url, id }` — dismissible home card.
**iOS addition (1.1.15 contract):** optional `link_url` (string, HTTPS) —
tapping the card text or image opens the link in the browser. A non-HTTPS
or empty link is ignored.

`ads.interstitial` (full-screen ad shown before a reconnect):

```json
{
  "ads": {
    "interstitial": {
      "enabled": true,
      "duration_seconds": 10,
      "skip_for_subscribers": true,
      "content": { "text": "…", "image_url": "https://…", "link_url": "https://…" }
    },
    "prices": {
      "once": 50000,
      "ten_times": 300000,
      "hourly": 200000,
      "monthly": 1500000
    }
  }
}
```

- `duration_seconds`: admin-set, allowed range **1–20**. Out-of-range values
  are clamped to that range; absent → 10.
- Rule: the FIRST connect of an app session shows NO interstitial. From the
  SECOND connect onward (each after a disconnect), the interstitial shows
  before the VPN starts; the VPN starts only after the countdown reaches
  zero. Closing early = incomplete view = no connect.
- `skip_for_subscribers`: when true (default), active subscribers never see
  the interstitial. The admin can turn it off from the bot panel.
- `prices`: ad-order prices in Toman, read from the server — never hardcoded
  in the app. Models: `once` (1 display), `ten_times` (10 displays at
  different hours), `hourly` (hourly windows), `monthly` (5 displays/day).
  The user submits an ad order in the bot's user panel; the admin approves
  or rejects it there. The app only displays approved ads, never more
  impressions than purchased.

## 3. Plans and codes

Plans: `{ id, days, name_fa, price_toman }`. Bot ids: `sub_1` (30d),
`sub_3` (90d), `sub_6` (180d), `sub_12` (360d). A plan without id, known
duration, or price is ignored.

Codes: `{ code, type, discount_percent?, gift_hours?, gift_days?,
tier?, max_uses?, remaining_uses? }`. `type` is `"discount"` or `"gift"`.
`gift_hours` is 1 / 5 / 24 / 168 and wins over `gift_days`. `tier` is
`"gift"` (middle tier: top 50 servers, no 30-minute cutoff while the gift
lasts) or a plan id such as `"sub_12"` (full subscription). `max_uses` is
the admin people-limit; the bot decrements `remaining_uses` on publish.

**Server-side validation (1.1.15 contract, same as Android):** the app
validates a code by calling the Supabase RPC
`validate_and_redeem_code(p_code, p_email)` (SECURITY DEFINER, GRANT
EXECUTE to anon). It returns `{ valid, type, gift_hours, tier, plan_id,
expires_at, message }` and marks a single-use code used atomically. The
published config list is only a fallback when the RPC is unavailable, and
the fallback is reported as such in the UI log — never silently trusted
for a single-use code. The app also calls `record_code_redemption(p_code,
p_email)` best-effort after every successful redeem (never fails a redeem).

## 4. Supabase — project `atvcpfnnmwguhjvhbbfj`

Base URL `https://atvcpfnnmwguhjvhbbfj.supabase.co`. The anon key is the
public client key (same value as Android's `Vpn5gAuthConfig.kt`); the
service-role key and DB password must NEVER be in the app.

- `POST /auth/v1/signup { email, password }` — direct signup (Confirm
  email OFF) returns a session immediately; 422 already-registered →
  switch to password login.
- `POST /auth/v1/token?grant_type=password { email, password }` — login.
- `POST /auth/v1/recover { email, redirect_to: "vpn5g://auth/callback" }`
  + `PUT /auth/v1/user` with the link token — password recovery (link
  flow only; OTP removed in Android 1.1.9 and never existed on iOS).
- `GET /functions/v1/get-client-ip` (anon key) — public IP for the
  one-account-per-IP rule. ipify/api.ip.sb are NOT used.
- `POST /rest/v1/rpc/check_registration { p_email, p_ip }` → `[bool]`
  (email free AND ip free). `POST /rest/v1/rpc/register_account
  { p_email, p_ip }` after a successful signup (best-effort; UNIQUE(ip)
  is the race backstop). One account per IP + one per email.
- `POST /rest/v1/rpc/set_own_user_id` — links the auth user id to the
  registrations row after sign-in (best-effort).
- `GET /rest/v1/vpn5g_registrations?select=subscription_status,
  subscription_expires_at,subscription_plan&user_id=eq.<uuid>` with the
  user's access token (RLS `auth.uid() = user_id`) — own subscription row.
  Anon access returns 401 by design.
- `POST /rest/v1/rpc/record_code_redemption { p_code, p_email }` → bool.
- `POST /rest/v1/rpc/record_ad_view { p_ad_id, p_user_id?, p_completed }`
  → bool — records an interstitial view; `p_completed` is true only when
  the countdown finished. Used by the server-side ad verification (§5).

## 5. Ad-view verification (1.1.15 contract)

The interstitial countdown is measured with a monotonic clock
(`DispatchTime` / `ContinuousClock`), never the wall clock, so changing
the phone's time cannot bypass it. On countdown completion the app calls
`record_ad_view` with `p_completed=true` and starts the VPN. If the
server is unreachable, the local countdown completion is the fallback
(the app never hangs and never crashes on a dead ad server); the fallback
is logged. Views and clicks are recorded server-side by the bot.

## 6. Bot deep links

- Buy: `https://t.me/VPN5G_IRBot?start=buy_<plan_id>` — the bot generates
  the UNIQUE payable amount for that order (every payment has a unique
  non-round amount so the bot can auto-confirm it when the admin is
  unavailable). The app never shows a round plan price as the amount to
  pay; the payable amount comes from the bot.
- Support: `https://t.me/VPN5G_IRBot?start=support`
- Redeem: `https://t.me/VPN5G_IRBot?start=redeem_<CODE>`

## 7. What iOS cannot do (platform limits, stated plainly)

- Per-app VPN bypass (Android's per-app proxy) has no iOS equivalent for
  third-party VPN apps — not implemented, not faked.
- No home-screen widget / quick tile equivalent of Android's QS tile.
- The 30-minute free-session timer is enforced inside the tunnel
  extension (the app cannot reliably run a background timer on iOS).
- A VPN tunnel cannot run in the Simulator; a physical iPhone is required
  for any tunnel test.
