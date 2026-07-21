# Android build

Pixiewood APKs for this repo. Reuse OLLMchat’s SDK at `/home/alan/gitlive/OLLMchat/.android-sdk` when present.

## Prerequisites

- Linux host with `gcc`, `g++`, `git`, `python3`, `curl`, Java **17+**
- Network for first-time SDK / gtk-android-builder / subproject downloads
- Device unlock / screen on for a useful launch (apps stop immediately while dozing)

## Phase 1 — GTK Hello World (no WebView)

```bash
cd /home/alan/git/webkitgtk-android
./scripts/android/build-hello-apk.sh
./scripts/android/adb-install-hello.sh
```

Package: `org.roojs.webkitgtk.androidhello`

## Phase 2 — browser (System WebView embed)

```bash
cd /home/alan/git/webkitgtk-android
./scripts/android/build-browser-apk.sh
./scripts/android/adb-install-browser.sh
```

Package: `org.roojs.webkitgtk.androidbrowser`  
Default URL: **https://roojs.com/**

Phases:

```bash
PIXIEWOOD_PHASE=setup ./scripts/android/build-browser-apk.sh   # prepare only
PIXIEWOOD_PHASE=build ./scripts/android/build-browser-apk.sh   # compile + APK
```

Output:

```text
.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
```

Useful logcat filter after launch:

```bash
adb logcat -s WebViewHost:I WebViewA11y:I GTK\ Runtime:D Gdk:D *:E
```

Phase 3: tap **Dump a11y** in the toolbar; dump lines also go to stdout / logcat.
Force-on is in-app (`setQueryFromAppProcessEnabled` + provider wake) — no TalkBack / no wake service. See [`docs/a11y.md`](a11y.md).

```bash
adb logcat -s WebViewHost:I WebViewA11y:I print:I *:E
```

## Layout

| Path | Role |
|------|------|
| `examples/hello/main.vala` | Phase 1 Adw Hello World |
| `examples/browser/main.vala` | Phase 2/3 chrome + WebView + Dump a11y |
| `lib/host/` | JNI C + `WebViewHost.java` + `WebViewA11y.java` |
| `lib/webkitgtkandroid/webview.vala` | `WebKitGtkAndroid.WebView` |
| `android/pixiewood-hello.xml` | Phase 1 Pixiewood manifest |
| `android/pixiewood-browser.xml` | Phase 2 Pixiewood manifest |
| `meson.build` | `-Dandroid_hello` / `-Dandroid_browser` (exclusive) |

## SDK override

```bash
export ANDROID_SDK_ROOT=/path/to/android-sdk
./scripts/android/build-browser-apk.sh
```

If unset, the script uses `$REPO/.android-sdk`, else OLLMchat’s `.android-sdk`, else installs into `$REPO/.android-sdk`.
