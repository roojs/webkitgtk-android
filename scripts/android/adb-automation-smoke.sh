#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APK="${1:-$ROOT_DIR/.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk}"
PKG=org.roojs.webkitgtk.androidautomation
TIMEOUT="${AUTOMATION_SMOKE_TIMEOUT:-45}"

if [ ! -f "$APK" ]; then
  echo "APK not found: $APK" >&2
  echo "Build first: scripts/android/build-automation-apk.sh" >&2
  exit 1
fi

adb install -r -d "$APK" || {
  adb uninstall "$PKG" 2>/dev/null || true
  adb install -r -d "$APK"
}
adb logcat -c
adb shell am force-stop "$PKG"
adb shell am start -n "$PKG/org.gtk.android.ToplevelActivity"

echo "Waiting up to ${TIMEOUT}s for AUTOMATION_SMOKE_PASS / FAIL..."
deadline=$((SECONDS + TIMEOUT))
while [ "$SECONDS" -lt "$deadline" ]; do
  if adb logcat -d 2>/dev/null | grep -q 'AUTOMATION_SMOKE_PASS'; then
    adb logcat -d -s print:I WebViewCdpBridge:I WebViewHost:I 2>/dev/null \
      | grep -E 'AUTOMATION_SMOKE|automation-started|a11y_nodes|inspector' || true
    echo "AUTOMATION_SMOKE_PASS"
    exit 0
  fi
  if adb logcat -d 2>/dev/null | grep -q 'AUTOMATION_SMOKE_FAIL'; then
    adb logcat -d -s print:I WebViewCdpBridge:I WebViewHost:I 2>/dev/null \
      | grep -E 'AUTOMATION_SMOKE|automation-started|a11y_nodes|inspector' || true
    echo "AUTOMATION_SMOKE_FAIL"
    exit 1
  fi
  sleep 2
done

echo "timeout waiting for automation smoke; recent logcat:" >&2
adb logcat -d -s print:I WebViewCdpBridge:I WebViewHost:I libc:F 2>/dev/null | tail -40 >&2
exit 1
