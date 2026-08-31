#!/usr/bin/env bash
# Phase 0 CDP spike smoke test on device/emulator.
#
# Build spike APK first (Android has no argv — use meson option):
#   export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
#   export PATH="$ANDROID_SDK_ROOT/ndk/*/shader-tools/linux-x86_64:$JAVA_HOME/bin:$PATH"
#   meson setup --reconfigure ... -Dandroid_cdp_spike=true .pixiewood/bin-aarch64 .
#   ninja -C .pixiewood/bin-aarch64 && ./scripts/android/build-browser-apk.sh
#
# Requires arm64-v8a device or arm64 system image (not x86_64 + arm64 translation).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APK="${1:-$ROOT_DIR/.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk}"
PKG=org.roojs.webkitgtk.androidbrowser
ACTIVITY=org.gtk.android.ToplevelActivity
TIMEOUT="${CDP_SPIKE_TIMEOUT:-30}"

if [ ! -f "$APK" ]; then
  echo "APK not found: $APK" >&2
  echo "Build with -Dandroid_cdp_spike=true (see scripts/android/build-browser-apk.sh)" >&2
  exit 1
fi

ABI="$(adb shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')"
if [ "$ABI" = "x86_64" ] || [ "$ABI" = "x86" ]; then
  echo "warning: primary ABI is $ABI — arm64-v8a APK may crash under native bridge; use an arm64 image/device" >&2
fi

adb install -r -d "$APK"
adb logcat -c
adb shell am force-stop "$PKG"
adb shell am start -n "$PKG/$ACTIVITY"

echo "Waiting up to ${TIMEOUT}s for CDP_SPIKE_PASS / CDP_SPIKE_FAIL..."
deadline=$((SECONDS + TIMEOUT))
while [ "$SECONDS" -lt "$deadline" ]; do
  if adb logcat -d 2>/dev/null | grep -q 'CDP_SPIKE_PASS'; then
    adb logcat -d -s print:I WebViewCdpBridge:I WebViewCdp:I WebViewHost:I 2>/dev/null | grep -E 'CDP_SPIKE|cdp-spike|WebViewCdp' || true
    echo "CDP_SPIKE_PASS"
    exit 0
  fi
  if adb logcat -d 2>/dev/null | grep -q 'CDP_SPIKE_FAIL'; then
    adb logcat -d -s print:I WebViewCdpBridge:I WebViewCdp:I WebViewHost:I 2>/dev/null | grep -E 'CDP_SPIKE|cdp-spike|WebViewCdp' || true
    echo "CDP_SPIKE_FAIL"
    exit 1
  fi
  sleep 2
done

echo "timeout waiting for CDP spike result; recent logcat:" >&2
adb logcat -d -s print:I WebViewCdpBridge:I WebViewCdp:I WebViewHost:I AndroidRuntime:E libc:F 2>/dev/null | tail -40 >&2
exit 1
