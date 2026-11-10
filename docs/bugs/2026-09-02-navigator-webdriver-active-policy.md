# Feature: `NavigatorWebDriverActivePolicy` API parity (hide `navigator.webdriver`)

**Status:** ✅ done — Vala API + vapi + host stub (no-op); hide unnecessary on stock WebView

**Started:** 2026-09-02

**Area:** `WebViewSettings.navigator_webdriver_active_policy` + host (optional)

**Related:**

- ℹ️ Windows twin (✅ shipped): [webview2-gtk `2026-09-02-disable-navigator-webdriver-blink.md`](file:///home/alan/git/webview2-gtk/docs/bugs/2026-09-02-disable-navigator-webdriver-blink.md)
- ℹ️ Windows docs: [webview2-gtk `docs/automation.md` — Hiding `navigator.webdriver`](file:///home/alan/git/webview2-gtk/docs/automation.md)
- ℹ️ Linux twin: [webkitgtk-automation README — Hiding `navigator.webdriver`](https://github.com/roojs/webkitgtk-automation#hiding-navigatorwebdriver-automation-flag)
- ℹ️ Upstream WebKit: [#165269](https://bugs.webkit.org/show_bug.cgi?id=165269)
- ℹ️ Automation setup already on Android: [`docs/plans/1.4-android-automation-parity.md`](../plans/1.4-android-automation-parity.md)

---

## Goal

- ✅ Match the **same Vala surface** as webview2-gtk / WebKit-shaped policy so OLLMchat (and other consumers) can set:

```vala
view.get_settings().navigator_webdriver_active_policy =
	NavigatorWebDriverActivePolicy.DISABLED;
```

  on Android without `#if` / missing-member errors.

- ✅ Default remains **AUTO** — enabling CDP / `is_controlled_by_automation` alone must **not** change the policy.
- ✅ Actually making page JS see `navigator.webdriver === false` — **already true** on stock System WebView (measured); host hide is no-op / unnecessary.

---

## Contract (same as Windows)

| Policy | Intended page JS | Windows host | Android host |
|--------|------------------|--------------|--------------|
| **AUTO** (default) | stock advertising | no blink flag | no change |
| **ENABLED** | always advertise when Chromium would | no blink flag | no change |
| **DISABLED** | always `false` | `--disable-blink-features=AutomationControlled` at env create | stored; no-op (already false) |

**Not** tied to `WEBKIT_INSPECTOR_SERVER` alone — opt-in via the setting.

---

## Problem / gap today

- ✅ `WebViewSettings` exposes `navigator_webdriver_active_policy`.
- ✅ `NavigatorWebDriverActivePolicy` enum in `namespace.vala`.
- ✅ Checked-in `vapi/webkitgtk-android-1.vapi` exposes enum + property.
- ℹ️ Consumer shared Vala that already targets Windows can compile on Android.

---

## Feasibility (Android System WebView)

Windows can pass Chromium boot args via WebView2 `AdditionalBrowserArguments`. Android **cannot** do that for a production embed:

- ℹ️ Host CDP path uses `WebView.setWebContentsDebuggingEnabled(true)` + loopback proxy (`WebViewCdpBridge`) — not a Chromium command line.
- ℹ️ There is **no** public `WebSettings` / WebView API equivalent to `--disable-blink-features=AutomationControlled`.
- ✅ **Measured 2026-09-02** on emulator `sdk_gphone16k_x86_64` (Android 17), package `org.roojs.webkitgtk.androidbrowser` (debuggable APK), Chrome WebView **151.0.7922.200**:
  - CDP available (`@webview_devtools_remote_<pid>` → `adb forward` → `/json/list`)
  - Active CDP session + `Runtime.evaluate`: **`navigator.webdriver === false`** (boolean; native getter on `Navigator.prototype`)
  - UA contains `; wv)` (System WebView). Mere DevTools/CDP attach does **not** flip the flag (unlike ChromeDriver / `--enable-automation`).
- 🚫 Do **not** rely on chrome command-line debug files or rooted device flags for the library API.
- ℹ️ Host hide path **not needed** for stock advertising: page JS already sees `false`. Optional script redefine only if a future path sets AutomationControlled (none known for production System WebView).
- ✅ Shipped: enum + setting + notify wiring that stores policy; host logs and no-ops when **DISABLED**.

---

## Fix landed

### `lib/webkitgtkandroid/namespace.vala` — enum

`NavigatorWebDriverActivePolicy` { AUTO, ENABLED, DISABLED }

### `lib/webkitgtkandroid/WebViewSettings.vala` — setting

`navigator_webdriver_active_policy` default **AUTO**

### `lib/webkitgtkandroid/WebView.vala` — push / notify

- `wka_host_set_navigator_webdriver_active_policy` from construct + settings notify
- Late change after attach: `warning` (stored only)

### Host

- `wka_host_set_navigator_webdriver_active_policy` in `webkitgtk-android-host-api.h` + `webkitgtk-android-cdp.c`
- Store `0=AUTO, 1=ENABLED, 2=DISABLED`; DISABLED logs no-op

### `vapi/webkitgtk-android-1.vapi` + docs

- Enum + property in checked-in vapi; README + CHANGELOG note

---

## Acceptance

- ✅ Default (**Auto**): no host hide side effects unless the app sets **Disabled**
- ✅ **Disabled** / **Enabled** / **Auto** compile and round-trip on `get_settings()` like webview2-gtk
- ✅ Shared consumer Vala can set the property under `#if ANDROID` without stubs
- ✅ Device/emulator: `navigator.webdriver === false` under CDP (hide already “free”; host no-op is correct)
- ✅ Late policy change after WebView/CDP start: warn “stored only”

---

## Next

1. ~~Land Vala enum + `WebViewSettings` property + vapi~~ — done.
2. ~~Measure `navigator.webdriver`~~ — done (emulator 2026-09-02): already `false` with CDP.
3. ~~Host stub/no-op~~ — done.
4. OLLMchat: use the same setting call on Android when the wrap pin moves.
