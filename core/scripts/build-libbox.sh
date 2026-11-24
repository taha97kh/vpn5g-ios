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
    echo "== Installing SagerNet gomobile fork (PINNED v0.1.13) =="
    # Pinned, not @latest: the generated header's nullability annotations
    # decide whether Swift imports LibboxSetup/LibboxNewService as `throws`
    # (annotated NSError**) or as multi-argument calls. @latest drifted
    # and broke the Swift build (CI run 45336311652: "missing argument
    # for parameter #2/#3"). v0.1.13 is the version the Swift code was
    # verified against (local gobind, same module version).
    go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.13
    gomobile init
fi

echo "== Building Libbox.xcframework (sing-box v1.11.8, ios) =="
gomobile bind \
    -target=ios \
    -o "$ROOT/core/Libbox.xcframework" \
    github.com/sagernet/sing-box/experimental/libbox

echo "== Done: $ROOT/core/Libbox.xcframework =="
ls -d "$ROOT/core/Libbox.xcframework"
