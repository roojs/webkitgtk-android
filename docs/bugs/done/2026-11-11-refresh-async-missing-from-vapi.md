# 2026-11-11 — `AndroidAtspi.refresh_async` missing from the consumer VAPI

**Status:** ✔️ `refresh_async` is in `vapi/webkitgtk-android-1.vapi`. Pixie republish is release 0.1.7.

**Related:** [`docs/a11y.md`](../../a11y.md); [`2026-07-23-a11y-walk-gtk-thread-anr.md`](2026-07-23-a11y-walk-gtk-thread-anr.md); OLLMchat `libocwebkit/A11y.vala` (`yield refresh_async()` on Android).

## Problem

- 🔷 OLLMchat Android a11y dump calls `AndroidAtspi.refresh_async()` before `get_desktop()`, which is the caller contract from the ANR fix.
- 🔷 Expected: valac against the published pixie accepts that call. The 0.1.6 library already implements it.
- 🔷 Actual: Release `v1.4.10` Android job compiled the pixie sysroot, then valac stopped:

```text
../../libocwebkit/A11y.vala:95.9-95.21: error: The name `refresh_async' does not exist in the context of `OLLMwebkit.A11y.dump'
   95 | 		yield refresh_async();
```

- 🔷 CI: [OLLMchat 42798264736](https://github.com/roojs/OLLMchat/actions/runs/42798264736) job `129768894849` (Build chat APK). Pixie setup and meson configure had already succeeded (`webkitgtk-android-1` 0.1.6).

## Evidence

- ✔️ `lib/webkitgtkandroid/AndroidAtspi.vala` defines namespace function `public async void refresh_async () throws GLib.Error`.
- ✔️ Published `webkitgtk-android-arm-v31-0.1.6.pixie` (`release.pins` track `0.1.6`, resolved `631dc47125837f91d9dac56231457b055ff072fd`) installs `share/vala/vapi/webkitgtk-android-1.vapi`. That file declares `init`, `get_desktop`, `register_webview`, and `generate_keyboard_event`. It does not declare `refresh_async`.
- ✔️ The same archive's `include/webkitgtk-android.h` (valac 0.56.18) declares:

```c
void android_atspi_refresh_async (GAsyncReadyCallback _callback_, gpointer _user_data_);
void android_atspi_refresh_finish (GAsyncResult* _res_, GError** error);
```

- ✔️ `libwebkitgtk-android-1.so` in that archive exports `android_atspi_refresh_async` and `android_atspi_refresh_finish`.
- ℹ️ `meson.build` installs the checked-in `vapi/webkitgtk-android-1.vapi` with `install_data`. `scripts/android/pack-pixie.sh` packs that installed file. The generated library VAPI is not what consumers compile against.
- ✔️ Local valac 0.56.18, given this declaration, emits the same two calls as the header:

```vala
public static async void refresh_async () throws GLib.Error;
```

## Root cause

- ✔️ `refresh_async` was added to `AndroidAtspi.vala` for the ANR fix and is in the generated header and the `.so`. The checked-in consumer VAPI was not updated, and that file is what the pixie publishes.

## Proposed fix

- 🔷 Add the declaration to `vapi/webkitgtk-android-1.vapi`, next to `get_desktop`.
- 🔷 Republish the pixie so `https://roojs.github.io/webkitgtk-android/release.pins` serves a VAPI that contains the line. The current 0.1.6 asset will keep failing OLLMchat until that pin changes.
- 🚫 Do not patch the downloaded VAPI inside OLLMchat.

### `vapi/webkitgtk-android-1.vapi`

**Where:** `namespace AndroidAtspi`, after `get_desktop`.

#### Add
```vala
	public static async void refresh_async () throws GLib.Error;
```

## Attempts / changelog

- ✔️ 2026-11-11. Confirmed from the v1.4.10 log, the 0.1.6 pixie VAPI, its header, and `nm` on `libwebkitgtk-android-1.so`. No library change applied.
- ✔️ 2026-11-11. Declared `refresh_async` in `vapi/webkitgtk-android-1.vapi`. Project version is 0.1.7 (Unreleased).

## Next

- ⏳ Human runs `scripts/release.sh` so `release.pins` serves 0.1.7.
- ⏳ Re-run OLLMchat Release - Android and confirm `libocwebkit` compiles (`refresh_async` resolved).
