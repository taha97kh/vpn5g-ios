#!/bin/sh
# بررسی نمادهای libbox که کد سوئیفت افزونه‌ی تونل استفاده می‌کند، در سربرگ
# Objective-C تولیدشده (Libbox.h). بعد از build-libbox.sh اجرا می‌شود؛ اگر
# نمادی نباشد، بیلد متوقف می‌شود تا نام‌ها با سربرگ واقعی تطبیق داده شوند.
# توجه: سربرگ Objective-C است؛ نام پروتکل‌ها در سوئیفت پسوند Protocol
# می‌گیرند (مثلاً LibboxPlatformInterface در ObjC همان
# LibboxPlatformInterfaceProtocol در سوئیفت است).
# استفاده: ./core/scripts/verify-libbox-api.sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HEADER="$(find "$ROOT/core/Libbox.xcframework" -name 'Libbox.h' | head -n 1)"
if [ -z "$HEADER" ]; then
    HEADER="$(find "$ROOT/core/Libbox.xcframework" -name '*.h' | head -n 1)"
fi

if [ -z "$HEADER" ]; then
    echo "FAIL: no header found under core/Libbox.xcframework — run build-libbox.sh first"
    exit 1
fi
echo "Header: $HEADER"

# نمادها به شکل Objective-C (بدون پسوند Protocol سوئیفت).
SYMBOLS="
LibboxSetup
LibboxNewService
LibboxBoxService
LibboxPlatformInterface
LibboxTunOptions
LibboxLocalDNSTransport
LibboxStringIterator
LibboxNetworkInterfaceIterator
LibboxNetworkInterface
LibboxWIFIState
LibboxConnectionOwner
LibboxNotification
LibboxInterfaceUpdateListener
openTun
getAutoRoute
getMTU
getDNSServerAddress
getInet4Address
isHTTPProxyEnabled
getHTTPProxyServer
getHTTPProxyServerPort
hasNext
"

MISSING=0
for sym in $SYMBOLS; do
    if grep -q "$sym" "$HEADER"; then
        echo "OK   $sym"
    else
        echo "MISS $sym"
        MISSING=1
    fi
done

if [ "$MISSING" -ne 0 ]; then
    echo "FAIL: some symbols are missing from the generated header."
    echo "Update LibboxPlatformInterface.swift / PacketTunnelProvider.swift"
    echo "to match the header, then re-run this script."
    exit 1
fi
echo "PASS: all expected libbox symbols found."
