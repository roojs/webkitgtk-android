# Android build

Pixiewood APKs for this repo. Reuse OLLMchat’s SDK at `/home/alan/gitlive/OLLMchat/.android-sdk` when present.

## Prerequisites

- Linux host with `gcc`, `g++`, `git`, `python3`, `curl`, Java **17+**
- Network for first-time SDK / gtk-android-builder / subproject downloads
- Device unlock / screen on for a useful launch (apps stop immediately while dozing)

## Consumer library (pkg-config / VAPI)

Default Meson (no hello/browser options) builds and installs:

| Artifact | Role |
|----------|------|
| `libwebkitgtk-android-1.so` | Shared library (Vala widget + JNI host) |
| `webkitgtk-android-1.pc` | pkg-config (`dependency('webkitgtk-android-1')`) |
| `webkitgtk-android-1.vapi` | Vala API (WebKit-shaped + host a11y at file scope — not on `WebView`) |
| `webkitgtk-android-host-api.h` | Host C API (a11y / cookies / downloads) |

```vala
#if ANDROID
using WebKitGtkAndroid;
#endif

var web = new WebView ();
web.load_uri ("https://roojs.com/");
```

**Java host (required in the consumer APK):**

```bash
./scripts/android/install-webview-java.sh /path/to/app/src/main/java
```

That copies `org.roojs.webkitgtk.android.WebViewHost` (+ a11y / download / freeze helpers) into the app. JNI loads them from the same APK ClassLoader as `libwebkitgtk-android-1.so`.

**Subproject / wrap (preferred for OLLMchat):** add this tree as a Meson subproject and `dependency('webkitgtk-android-1')` — this project calls `meson.override_dependency`, so the build-tree VAPI is wired automatically without a prefix install.

**Pin a release tarball** (not `HEAD`) — see [`docs/releasing.md`](releasing.md). The GitHub Release notes include a `wrap-file` snippet with `source_url` + `source_hash`. GitHub auto-generated “Source code” archives are not stable hashes; use the attached `webkitgtk-android-*.tar.gz`.

**Prefix install:** `meson install` also stages `webkitgtk-android-1.pc`, `vapi/webkitgtk-android-1.vapi`, and `webkitgtk-android-host-api.h`. Pixiewood APK builds often install **runtime `.so` only**; use a subproject (or a full prefix + `PKG_CONFIG_PATH`) for compiling consumers.

## Pixie package

A version tag also publishes one prebuilt Android library, so a consumer can install it instead of compiling this tree:

```text
webkitgtk-android-arm-v31-<version>.pixie
```

The archive contains `libwebkitgtk-android-1.so`, `webkitgtk-android-1.pc`, the VAPI, the host headers, and the Java sources under `share/pixiewood/webkitgtk-android-java`. Build it locally with:

```bash
./scripts/android/build-pixie.sh
```

That fetches the published GTK stack (GTK itself is the IME package in `android/pixie-gtk.pins`), compiles this library, and writes `pixie-artifacts/`. Host tools required: `valac`, `ninja`, `pkg-config`, `jq`, and the Vala bindings from `libgtk-4-dev`, `libsoup-3.0-dev`, and `libglib2.0-dev`.

After a tag, the pin list is `release.pins` on `main` and at `https://roojs.github.io/webkitgtk-android/release.pins`. The `repo` field is the GTK checkout URL, so the row survives a pin list merged with [pixiewood-pkgs](https://roojs.github.io/pixiewood-pkgs/release.pins). OLLMchat unpacks that row into the same sysroot and drops the `webkitgtk-android` wrap. Copy Java from `share/pixiewood/webkitgtk-android-java` into the app Java tree (same files as `install-webview-java.sh`).

**Valadoc (Linux, no Android):**

```bash
meson setup build-docs -Ddocs=true   # use scripts/android/ensure-meson.sh if host meson < 1.8
ninja -C build-docs docs/valadoc
```

Hello-only builds (`-Dandroid_hello=true`) skip the shared library (that Pixiewood manifest has no libsoup).

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

The browser APK must contain both `libwebkitgtk-android-browser.so` and `libwebkitgtk-android-1.so`.

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
| `examples/browser/main.vala` | Phase 2/3 chrome linking the library |
| `lib/host/` | JNI C + `WebViewHost.java` + `WebViewA11y.java` |
| `lib/webkitgtkandroid/WebView.vala` | `WebKitGtkAndroid.WebView` |
| `lib/webkitgtkandroid/namespace.vala` | enums / `NetworkError` |
| `android/pixiewood-hello.xml` | Phase 1 Pixiewood manifest |
| `android/pixiewood-browser.xml` | Phase 2 Pixiewood manifest |
| `meson.build` | shared lib `webkitgtk-android-1`; optional `-Dandroid_hello` / `-Dandroid_browser` |

## SDK override

```bash
export ANDROID_SDK_ROOT=/path/to/android-sdk
./scripts/android/build-browser-apk.sh
```

If unset, the script uses `$REPO/.android-sdk`, else OLLMchat’s `.android-sdk`, else installs into `$REPO/.android-sdk`.
