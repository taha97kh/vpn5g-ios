#!/bin/sh
# ساخت Libbox.xcframework از sing-box v1.11.8 با gomobile (انشعاب SagerNet).
# فقط روی macOS اجرا می‌شود؛ در CI روی macos-latest اجرا می‌شود.
# خروجی: core/Libbox.xcframework (پروژه‌ی Xcode همین مسیر را ارجاع می‌دهد).
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/core"

export GOTOOLCHAIN=local
export GOFLAGS=-mod=mod

echo "== Go version =="
go version

if ! command -v gomobile >/dev/null 2>&1; then
    echo "== Installing SagerNet gomobile fork =="
    go install github.com/sagernet/gomobile/cmd/gomobile@latest
    gomobile init
fi

echo "== Building Libbox.xcframework (sing-box v1.11.8, ios) =="
gomobile bind \
    -target=ios \
    -o "$ROOT/core/Libbox.xcframework" \
    github.com/sagernet/sing-box/experimental/libbox

echo "== Done: $ROOT/core/Libbox.xcframework =="
ls -d "$ROOT/core/Libbox.xcframework"
