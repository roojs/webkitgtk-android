# 2026-07-23 — A11y walk on GTK thread deadlocks Android main (ANR)

**Status:** ✔️ async walk applied in library; OLLMchat wire ✔️ (`libocwebkit/A11y.vala`) — await device ✅

**Related:** [`docs/a11y.md`](../a11y.md) (caller contract), plan Phase 3 a11y; sibling symptom [`2026-07-23-offscreen-a11y-empty-tree.md`](2026-07-23-offscreen-a11y-empty-tree.md); OLLMchat [`docs/bugs/2026-07-23-android-a11y-refresh-async.md`](../../../docs/bugs/2026-07-23-android-a11y-refresh-async.md)

## Problem

- 🔷 Consumer app (OLLMchat Android POC) hung while testing the browser tool (Gemini page load + a11y dumps / presses).
- 🔷 Android reported ANR: input dispatch timed out on `ToplevelActivity` (~10s wait for `MotionEvent`).
- 🔷 Expected: a11y `walk` / page dump returns; UI stays responsive (IME / taps).
- 🔷 Actual: app freezes; ANR dropbox entry written.

## Evidence

- ✔️ Dropbox `data_app_anr` **2026-07-23 07:00:15** — process `org.roojs.ollmchat.androidpoc` (embeds this library’s `WebViewA11y`).
- ℹ️ Local extract: `/tmp/ollm-anr-0700.txt` (from `dumpsys dropbox --print`).
- ✔️ Subject:

```
Input dispatching timed out (... ToplevelActivity is not responding.
Waited 10001ms for MotionEvent).
```

- ✔️ **Android `main`** (tid=1) Waiting:

```
CountDownLatch.await
→ org.gtk.android.GlibContext.blockForMain (GlibContext.java:49)
→ ToplevelActivity$ToplevelView$Surface.onCreateInputConnection (…:290)
```

- ✔️ **`GTK Thread`** (tid=14) TimedWaiting — holding `WebViewA11y` class lock:

```
FutureTask.get
→ WV.c53.b / WebViewChromiumFactoryProvider
→ WebViewChromium.getAccessibilityNodeProvider
→ android.webkit.WebView.getAccessibilityNodeProvider
→ ViewGroup / WebView.onInitializeAccessibilityNodeInfoInternal
→ org.roojs.webkitgtk.android.WebViewA11y.linkDirectConnection (WebViewA11y.java:140)
→ WebViewA11y.ensure (WebViewA11y.java:82)
→ WebViewA11y.walk (WebViewA11y.java:202)
  - locked (Class<WebViewA11y>)
```

- ✔️ WebView sandboxed process was active (~17% CPU in ANR sample); GTK thread had accumulated ~400s user CPU by dump time (long busy a11y/page work earlier in the session).
- ℹ️ Same night: earlier ANR **2026-07-22 23:50** on the same package was **pango layout** on GTK main (huge chat) — separate failure mode; not this deadlock.
- ℹ️ Session context: OLLMchat history `…/22-50-40.json` — repeated `browser` `fetch` / `help` against `gemini.google.com` around 06:59–07:00.

## Root cause

- ✔️ `wka_host_a11y_walk` (JNI) calls `WebViewA11y.walk()` **synchronously on the GTK thread**.
- ✔️ `walk()` → `ensure()` → `linkDirectConnection()` calls `WebView.onInitializeAccessibilityNodeInfo` / `getAccessibilityNodeProvider` on that same thread.
- ✔️ System WebView implements provider access via work that must complete on the **Android UI thread** (`FutureTask.get` from Chromium). While Android `main` is inside `GlibContext.blockForMain` (IME `onCreateInputConnection`), it cannot run that work.
- ✔️ Classic cross-thread deadlock:

  1. Android `main` waits for GTK (`blockForMain`).
  2. GTK waits for WebView/`FutureTask` (needs Android `main`).

- ℹ️ Linux OLLMchat already offsloads AT-SPI dump/fill/press to a **GLib worker thread** (main-thread AT-SPI deadlocks). That does **not** fix Android: WebView a11y must run on **Android main**, not a random GLib worker. Posting from a worker and blocking on UI recreates the same ANR when `blockForMain` is active.
- 🚫 Not “Gemini-specific”; any sync walk during IME / other `blockForMain` can trip this.

## Decision (🔷 locked)

- ✔️ **Keep** AT-SPI-shaped surface (`AndroidAtspi` / same roles as Linux `Atspi` / Windows `Win32Atspi`). **🚫** No DOM scrape, TalkBack, or custom non-ATSPI protocol.
- ✔️ **Product path:** async walk — schedule collect on Android UI; complete via GLib idle / Vala `async`. **Do not** GTK-sync-wait on that UI work.
- ✔️ Sync `wka_host_a11y_walk` / `walk()` from GTK **refuses** (empty + log) to prevent ANR — demo / OLLMchat must use async.
- 🚫 Infinite `FutureTask.get` / latch wait as the “fix”.
- 🚫 Treating Linux-style GLib worker alone as sufficient on Android.

## Applied in this repo (✔️)

| Piece | Change |
|-------|--------|
| `WebViewA11y.java` | `walk()` UI-only; `walkAsync(cookie)` posts to WebView looper; actions post to UI |
| `webkitgtk-android-a11y.c` / host API | `wka_host_a11y_walk_foreach_async` + `nativeWalkDone` → `g_idle_add` |
| `AndroidAtspi.vala` | `refresh_async()` — preferred entry; sync `ensure_tree` still refuses off-UI |
| `docs/a11y.md` | Caller contract (async from GLib/GTK) |
| Browser demo | Dump / Dump hidden use async foreach |

## Attempts / changelog

| Date | Note |
|------|------|
| 2026-07-23 | Diagnosed from OLLMchat device dropbox ANR; bug filed. |
| 2026-07-23 | Direction locked: async walk, keep ATSPI facade; not Linux worker-only. Host/Java/docs + demo applied. |
| 2026-07-23 | OLLMchat `A11y.vala`: Android dump/fill/press yield `refresh_async()` before sync facade body. |

## Next

- ✔️ OLLMchat `libocwebkit` Android `A11y.dump` / `fill` / `press` — `yield refresh_async()` then sync facade walk (see OLLMchat bug log).
- ⏳ Verify: Dump a11y + IME focus (entry) without ANR; OLLMchat browser fetch while keyboard up.
- ⏳ Invoke/setValue/focus: Java posts to UI (best-effort sync return); full async action API only if press/fill still race.

---

## Report for OLLMchat (read this in the other project)

**Hand this section to the OLLMchat / `libocwebkit` agent.** Library: `webkitgtk-android` bug `2026-07-23-a11y-walk-gtk-thread-anr`.

### What broke

Android ANR when browser tool dumped a11y: GTK thread called sync `WebViewA11y.walk` → Chromium needs Android UI thread → Android UI was in `GlibContext.blockForMain` (IME) waiting on GTK.

### What did *not* change

- Still **AT-SPI-shaped** (`AndroidAtspi`, same as Linux `Atspi` / Windows `Win32Atspi`).
- Markdown / `^press:N` stay in OLLMchat.
- **🚫** Do not switch to DOM/JS scrape for this bug.

### Why Linux’s worker thread is not enough on Android

`A11y.vala` already does:

```vala
#if ANDROID || WINDOWS
		return this.dump_sync(url, title);
#else
		new GLib.Thread<bool>("ocwebkit-a11y-dump", () => { ... });
#endif
```

Linux worker avoids **AT-SPI ↔ GTK main** deadlock. Android needs collect on **Android main**, and GTK must **not** block waiting for it while Android main may be in `blockForMain`. Use the same *async yield* pattern as Linux, but complete via host async → GLib idle (not a plain GLib worker calling sync JNI walk).

### Required OLLMchat changes

1. **`libocwebkit/A11y.vala` (Android)** — stop `return dump_sync(...)` on the GLib/GTK thread.
2. Before walking the facade tree, **`yield AndroidAtspi.refresh_async()`** (or equivalent that calls `wka_host_a11y_walk_foreach_async`), then run the existing parse/`dump_sync` body against the refreshed tree.
3. Same idea for **`fill` / `press`**: do not call sync host invoke/set_value from GTK while assuming boolean completion on that thread; after refresh, prefer UI-posted actions (library posts today) or a follow-up async action API if races show up.
4. Update the class comment: Android is **not** “stay on UI thread (JNI)” for dump — it is **async handoff to Android UI**, like Linux is async handoff off GTK main.

### Caller API (library)

Documented in [`docs/a11y.md`](../a11y.md):

- **From GLib/GTK:** `wka_host_a11y_walk_foreach_async` or `AndroidAtspi.refresh_async()` only.
- **Sync** `wka_host_a11y_walk` / `walk_foreach` / `AndroidAtspi.ensure_tree`: safe only on Android UI; from GTK they refuse / empty (ANR guard).

### Verify

- Dump / agent browse while an entry has IME focus → no ANR, non-empty tree when page has content.
- Logcat: `WebViewA11y` should show `walkAsync` / UI collect, **not** `walk: called off UI thread — refusing`.
