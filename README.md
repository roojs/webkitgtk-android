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

**Phase 1 ✔️** — GTK Hello World APK builds (await device **✅**). Next: Phase 2 embed.

See [`docs/plans/1.0-ACTIVE-webkitgtk-android.md`](docs/plans/1.0-ACTIVE-webkitgtk-android.md) and [`docs/android-build.md`](docs/android-build.md).

## Related

- `/home/alan/git/webview2-gtk` — Windows embed pattern to mirror
- `/home/alan/gitlive/OLLMchat` `libocwebkit` — browser tool + a11y markdown consumer
- OLLMchat `docs/plans/5.0.2-android-webkit-control.md` — chat-side Android wire-up

## Out of scope

- Snapshot / PDF / capture APIs (Snappr product)
- Full WebKitGTK feature surface
- Linux/Windows builds of this library
