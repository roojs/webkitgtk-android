# 2026-08-22 — `WebView.network_session` property missing (getter only)

**Status:** ✔️ library property applied; OLLMchat wrap bump ⏳ — await user ✅

**Related:** plan [`1.1-downloads.md`](../plans/1.1-downloads.md); webview2-gtk `WebView.network_session { get; construct; }`; OLLMchat `libocwebkit/Browser.vala` currently calls the getter so Android valac compiles against this wrap.

## Problem

- 🔷 Consumer (OLLMchat `libocwebkit/Browser.vala`) uses WebKitGTK-shaped **property** `web_view.network_session` for cookies and `download_started`.
- 🔷 Expected: same Vala as Linux `webkitgtk-6.0` and Windows `webview2gtk-1`.
- 🔷 Actual: this library only exposes a **method** `get_network_session()`. OLLMchat Android valac fails:

```text
error: The name `network_session' does not exist in the context of `WebKitGtkAndroid.WebView'
```

- 🔷 CI: [OLLMchat 32552806663](https://github.com/roojs/OLLMchat/actions/runs/32552806663)

## Evidence

- ℹ️ `lib/webkitgtkandroid/WebView.vala` has a **private field** `network_session` plus handwritten `get_network_session()`.
- ℹ️ Checked-in `vapi/webkitgtk-android-1.vapi`: `public NetworkSession get_network_session ();` — no property.
- ℹ️ Linux `webkitgtk-6.0.vapi`: `public WebKit.NetworkSession network_session { get; construct; }` (also generates `get_network_session()`).
- ℹ️ Windows `webview2-gtk` `webview.vala`: `public NetworkSession network_session { get; construct; }` — example uses `web.network_session`.
- ℹ️ OLLMchat 5.0.2: extend this library when the WebKit-shaped API is missing — do not keep a parallel getter-only surface.

## Root cause

- ✔️ Downloads (1.1) copied a `get_*` method instead of the GObject **property** Linux/Windows use.
- ✔️ Vala property syntax (`.network_session`) does not bind to a method of that name. A property named `network_session` **does** generate `get_network_session()` in C/vapi.

## Proposed fix

- ✔️ Replace the private field + handwritten getter with a WebKit-shaped property (same as webview2-gtk).
- ✔️ Keep a default session when the construct property is unset.
- ✔️ Drop `get_network_session()` — the property supplies it.
- ✔️ Demo + checked-in vapi use `.network_session`.
- 🚫 Do not leave OLLMchat on getter syntax as the long-term API. Consumer getter is a workaround until this wrap pin moves.

### `lib/webkitgtkandroid/WebView.vala` — field → property

**Where:** class fields, next to the other public WebKit-shaped properties. Drop the private field.

#### Remove
```vala
		private NetworkSession network_session = new NetworkSession ();
```

#### Add
After `estimated_load_progress`, WebKit-shaped session (webview2-gtk / WebKitGTK 2.40).

```vala
		/** WebKitGTK-shaped — network session for this view. */
		public NetworkSession network_session { get; construct; }
```

### `lib/webkitgtkandroid/WebView.vala` — default session in `construct`

**Where:** new `construct` block on `WebView` (none today). Same null-default as webview2-gtk.

#### Add
Immediately before `public WebView ()`.

```vala
		construct {
			if (this.network_session == null) {
				this.network_session = new NetworkSession ();
			}
		}
```

### `lib/webkitgtkandroid/WebView.vala` — drop handwritten getter

**Where:** method `get_network_session()`. Internal `download_uri` already uses `this.network_session` — that becomes the property.

#### Remove
```vala
		/**
		 * WebKitGTK-shaped network session (cookies + downloads).
		 */
		public NetworkSession get_network_session ()
		{
			return this.network_session;
		}
```

### `examples/browser/main.vala` — property on demo WebView

#### Remove
```vala
		web.get_network_session ().download_started.connect ((download) => {
```

#### Replace with
```vala
		web.network_session.download_started.connect ((download) => {
```

### `vapi/webkitgtk-android-1.vapi` — match generated API

#### Remove
```vala
		public NetworkSession get_network_session ();
```

#### Replace with
```vala
		public NetworkSession network_session { get; construct; }
```

## Attempts / changelog

- ℹ️ 2026-08-22 — OLLMchat compiled by calling `get_network_session()` (workaround). This log is the library-side fix.
- ✔️ 2026-08-22 — Library: `{ get; construct; }` property + default in `construct`; demo + checked-in vapi use `.network_session`.

## Next

- ⏳ OLLMchat: bump `android/pixiewood-wraps/webkitgtk-android/webkitgtk-android.wrap` revision, restore `.network_session` in `Browser.vala`, drop/replace R18 (that test currently forbids the property).
