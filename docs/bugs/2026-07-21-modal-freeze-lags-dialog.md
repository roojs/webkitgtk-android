# 2026-07-21 — Modal freeze lags behind dialog paint

**Status:** ✅ fixed — PixelCopy + nav-bottom crop + 2px top trim; debug probes removed.

**Related:** [`docs/freeze.md`](../freeze.md), plan § Modal freeze

## Problem

- 🔷 Auto freeze still lags on device. **What the user sees (be specific):**
  1. Dialog appears, but **most of it is hidden underneath the still-on-top WebView**.
  2. After a short wait, z-order/freeze catches up and the dialog shows properly.
- 🔷 So this is primarily **WebView still covering the GTK SurfaceView** (park / `setZOrderOnTop`) arriving late relative to dialog paint — not merely a missing snapshot picture.
- 🔷 Apps must **not** call freeze manually — monitor only.

## Measure results (2026-07-21 Dump a11y)

### Before (PNG + capture-before-park)

| logcat time | step | note |
|-------------|------|------|
| …39.908 | `enterUi capture start` | Still on-screen WebView |
| …40.771 | capture done / park / zOrder | **~860 ms** PNG path before park |

### After (RGBA MemoryTexture + park-before-capture) — 23:03:57

| logcat time | step | note |
|-------------|------|------|
| …57.592 | park + `setZOrderOnTop(true)` | **Before** capture |
| …57.592 | capture start | |
| …57.696 | `drawMs=93 copyMs=10` 1440×2824 | **~103 ms** total vs ~860 ms |
| …57.763 | freeze_frame cb done | Texture applied |

**Root cause (confirmed):** PNG encode+disk dominated; park-after-capture left dialog under WebView for that whole window.

**Status:** ✔️ park-first + memory texture shipped; re-check colors (R/B swap → try `B8G8R8A8` if wrong). `parent-set` still absent for AdwAlertDialog (map-only) — optional follow-up.

## What we already tried

| Approach | Result |
|----------|--------|
| Explicit `freeze()` before `present()` in Dump a11y | Rejected — apps won’t do that; wrong model |
| `runOnUiThread` always | Deferred enter until after `present` — made lag worse |
| Sync enter when already on main looper | Helps host side; lag remains |
| Sync freeze-frame callback on GLib owner thread | Picture applies sooner; lag remains |
| Hook `Gtk.Widget::map` | Too late — dialog already mapping/painting |
| Hook `parent-set` + type name `AdwDialog` | Earlier than map; **still** lag on device |
| Park WebView off-screen + raise SurfaceView | Fixes z-order / touches; not the first-frame race |

## Likely race (hypothesis)

1. Adw `present()` parents / maps / queues a frame for the dialog.
2. Our hook runs and calls `wka_host_freeze()` → Java capture + park + `nativeFreezeFrame` → GTK `Picture`.
3. Even when “synchronous,” **GTK may already have committed or be about to paint** one frame with the dialog over the **still-live** WebView (or WebView still on top until park completes).
4. User sees: dialog up → brief live page → frozen snapshot.

Need **evidence** (log timestamps) before jumping to last resort:

```bash
adb logcat -s WebViewFreeze:I
# Correlate: parent-set / enter / parkOffscreen / frame path vs when dialog is first visible
```

Optional GTK side: temporary `GLib.debug` at start/end of `refresh_freeze` / freeze hook with monotonic time.

## Strategy — exhaust in order

Work top-down. Stop when lag is gone. **Last resorts only with user approval.**

### A — Measure (do first)

1. ✔️ Log tag `WkaFreezeLag` on hook / refresh_freeze / host_freeze / enterUi capture·park·zOrder / nativeFreezeFrame.
2. ✔️ One Dump a11y run captured — see **Measure results** above.
3. ✔️ Lag = ~860 ms PNG capture **before** park/z-order; no `parent-set` on AdwAlertDialog.

### B — Faster / earlier freeze (still auto-only)

1. ⏳ **Park + raise SurfaceView before PNG** — on enter: park + `setGtkSurfaceOnTop` first (stops live WebView under finger/eye immediately), then capture for Picture (may be blank/stale one tick — refresh 1s dirty already exists). *Hypothesis: user cares more about live page vanishing than perfect first snapshot.*
2. ⏳ **Capture without PNG file** — if I/O dominates, pass bitmap bytes / shared mem instead of compress-to-cache (only if A shows capture cost).
3. ⏳ **Hook earlier than `parent-set`** — spike Adw present path: is there a GObject signal/property notify we can emission-hook without linking Adw (type-name + signal lookup on `AdwDialog` at runtime)? e.g. notify before map. Document findings; no Adw compile dep.
4. ⏳ **`Gtk.Window` transient** — same timing rules for non-Adw dialogs; verify separately.

### C — Visual cover without touching dialog (better than hide dialog)

1. ⏳ **Instant opaque cover in GTK** — on first overlay detection, immediately show a solid/`Picture` (even empty/last frame) over the WebView allocation **before** waiting on Java capture; replace when PNG arrives. Dialog stays as Adw presented it. *Background “disappears” briefly then snapshot fills in — matches user’s “worst case background disappear” idea without hiding the dialog.*
2. ⏳ Pre-warm / keep last snapshot around so cover isn’t blank.

### D — Last resorts (user must OK)

1. 🚫 **Hide dialog → freeze → show dialog** — suppress dialog visibility until freeze completes, then restore. User named this last resort; do not implement until A–C fail or user chooses it.
2. 🚫 **Block/`present` rewrite** — intercept present (fragile, Adw-specific). Avoid unless no other path.

## Out of scope / rejected

- 🚫 Manual `freeze()` / `freeze_manual` for app dialogs (monitor only).
- 🚫 Requiring OLLMchat to order freeze vs present.
- 🚫 AccessibilityService / TalkBack for this bug.

## Freeze frame capture/display debug

When Dump a11y freezes, log + dump what was taken vs where it is shown.

```bash
adb logcat -c
# scroll the page, tap Dump a11y, then:
adb logcat -d -s WkaFreezeDbg:I WkaFreezeLag:I | rg "CAPTURE|DISPLAY"

# Inspect the exact bitmap Java captured (after a freeze):
adb shell "run-as org.roojs.webkitgtk.androidbrowser cat cache/wka-freeze-debug.jpg" > /tmp/wka-freeze-debug.jpg
# or if run-as fails:
adb exec-out run-as org.roojs.webkitgtk.androidbrowser cat /data/data/org.roojs.webkitgtk.androidbrowser/cache/wka-freeze-debug.jpg > /tmp/wka-freeze-debug.jpg
```

**CAPTURE** (Java): WebView `wh`, `scroll`, `translationX`, `screenXY`, corner/center pixels, opaque sample count, JPEG dump path.  
**DISPLAY** (Vala): texture `wh` vs `host_area` / `picture` allocation and scale factor.  
**GEOM** (both): on-screen WebView vs SurfaceView (`WkaFreezeDbg GEOM`); GTK `host_bounds` / `pic_bounds` / `pic_alloc` after apply and +50ms (`WkaFreezeLag GEOM`).

```bash
adb logcat -d -s WkaFreezeDbg:I WkaFreezeLag:I | rg 'GEOM|CAPTURE|DISPLAY'
adb exec-out screencap -p > /tmp/wka-freeze-screen.png
adb exec-out run-as org.roojs.webkitgtk.androidbrowser cat cache/wka-freeze-debug.jpg > /tmp/wka-freeze-debug.jpg
```

Compare: JPEG (what was captured) vs screencap (what was shown) vs GEOM numbers (where each thinks it lives).

## Decision log

| Date | Note |
|------|------|
| 2026-07-21 | Bug opened; hide/show dialog parked as last resort; strategy A→C first. |
| 2026-07-21 | User: auto-trigger only; no manual freeze API. |
| 2026-07-21 | User clarifies: dialog mostly **under** WebView, then OK. |
| 2026-07-21 | Measure: ~860 ms capture-before-park; no AdwAlertDialog `parent-set`; next = B1. |
| 2026-07-21 | Drop PNG → RGBA `Gdk.MemoryTexture`; park before capture (B1). |
| 2026-07-21 | User: squash / blank after scroll — stop guessing; add CAPTURE/DISPLAY debug + JPEG dump. |
| 2026-07-21 | Evidence: scrolled capture solid white via `draw()`; PixelCopy path; aspect = scale 4 vs density 3.75. |
| 2026-07-21 | PixelCopy OK (~20–50ms); dirty re-copy disabled (flicker); scrolled JPEG has content. |

## Capture/display evidence (2026-07-21 23:24)

| Case | JPEG | non-white | Verdict |
|------|------|-----------|---------|
| scroll=0,0 | ~333 KB | (corners white; page mostly light) | `draw()` had *some* content |
| scroll=0,5464 | **~25 KB solid white** | 0 | **`WebView.draw()` blank after scroll** |

DISPLAY: texture `1440×2824` into host_area `384×708` at GTK `scale=4.00` while Android density=`3.75` (WebView clamped to screen). `tex_ar≈0.51` vs `host_ar≈0.54` → squash.

**Fix:** `PixelCopy` of window rect (~20–50 ms). Dirty re-copy disabled (z-order flicker). Aspect/scale mismatch still logged (`tex_ar` vs `host_ar`).

Verified scrolled: `scroll=0,5589`, JPEG ~340 KB with page content; `nonWhiteSamples~2889`.

## Next agent action

**Horizontal + system nav (user):** ImageView under SurfaceView cannot win `setZOrderOnTop`. Do what was asked: measure WebView vs SurfaceView bottom overlap (~system nav) and **chop that many rows off** the freeze bitmap before GTK FILL.
