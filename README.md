# webkitgtk-android

**GTK 4** widget embedding **Android System WebView** — the Android counterpart to webview2-gtk (Windows WebView2).

Goal: Vala apps (especially **OLLMchat** on Android) can use a **WebKitGTK-shaped** `WebView` API, with **accessibility dump / fill / press** for the browser tool — not screenshots.

```vala
#if ANDROID
using WebKitGtkAndroid;
#elif WINDOWS
using WebView2Gtk;
#else
using WebKit;
#endif

var web = new WebView ();
web.load_uri ("https://roojs.com/");
```

## Status

- **Phase 1 ✅** — GTK Hello World APK
- **Phase 2 ✅** — WebView embed + display
- **Phase 3 ✔️** — a11y dump / fill / press (await device **✅**). Caller threads: [`docs/a11y.md`](docs/a11y.md) (async from GLib/GTK).
- **Downloads ✔️** — engine API (see [`docs/plans/1.1-downloads.md`](docs/plans/1.1-downloads.md))
- **Packaging ✔️** — `libwebkitgtk-android-1` + pkg-config / VAPI (see [`docs/android-build.md`](docs/android-build.md))

| Doc | |
|-----|--|
| [Changelog](CHANGELOG.md) | Notable changes per release |
| [Android build](docs/android-build.md) | Pixiewood APKs + consumer wrap |
| [Releasing](docs/releasing.md) | Tag + source tarball GitHub Release |

### Valadoc (Linux)

```bash
./scripts/android/ensure-meson.sh   # if host meson < 1.8
meson setup build-docs -Ddocs=true
ninja -C build-docs docs/valadoc
# → build-docs/valadoc/index.html
```

## Related

- `/home/alan/git/webview2-gtk` — Windows embed pattern to mirror
- `/home/alan/gitlive/OLLMchat` `libocwebkit` — browser tool + a11y markdown consumer
- OLLMchat `docs/plans/done/5.0.2-DONE-android-webkit-control.md` — chat-side Android wire-up

## Out of scope

- Snapshot / PDF / capture APIs
- Full WebKitGTK feature surface
- Linux/Windows builds of this library

## Artificial Intelligence Usage

This project was developed with the assistance of artificial intelligence.
