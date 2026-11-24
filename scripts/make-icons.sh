#!/bin/sh
# ساخت دوباره‌ی آیکون‌های اپ از لوگوی شفاف ۵۱۲ (فقط روی macOS، با sips).
# خروجی: VPN5G/Resources/Assets.xcassets/AppIcon.appiconset
# آیکون‌های iOS باید مات باشند؛ پس لوگو روی پس‌زمینه‌ی مشکی قرار می‌گیرد.
# لوگوی داخل اپ (Logo.imageset) شفاف می‌ماند.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/VPN5G/Resources/Assets.xcassets/Logo.imageset/logo-512.png"
DEST="$ROOT/VPN5G/Resources/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SRC" ]; then
    echo "FAIL: logo not found at $SRC"
    exit 1
fi

# پس‌زمینه‌ی مشکی ۱۰۲۴ و ترکیب لوگو روی آن
TMP="$(mktemp -d)"
sips -z 1024 1024 -s format png "$SRC" --out "$TMP/logo-1024.png" >/dev/null
# ساخت یک تصویر مشکی و ترکیب: با sips مستقیم ترکیب ممکن نیست، پس از
# AppleScript-free روش ImageMagick استفاده می‌شود اگر نصب باشد؛ در غیر
# این صورت فقط تغییر اندازه انجام می‌شود و پس‌زمینه‌ی شفاف حفظ می‌شود.
for size in 40 58 60 80 87 120 180 1024; do
    if command -v magick >/dev/null 2>&1; then
        magick -size 1024x1024 xc:black "$TMP/logo-1024.png" -composite \
            -resize "${size}x${size}" "$DEST/icon-${size}.png"
    else
        sips -z "$size" "$size" "$TMP/logo-1024.png" --out "$DEST/icon-${size}.png" >/dev/null
    fi
    echo "icon-${size}.png"
done
rm -rf "$TMP"
echo "Done. If magick was missing, icons keep transparency — re-run on a Mac with ImageMagick for the black background."
