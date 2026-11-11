# 2026-07-23 — Off-screen / background a11y dump returns empty tree

**Status:** ✔️ agent fix — park-not-INVISIBLE; device A/B on Gemini parked dump = 74 nodes (non-empty). Awaiting user **✅**.

**Related:** [`docs/a11y.md`](../../a11y.md), plan § Research notes — *Background browse → 0×0 “screen”* / *CF / overlays vs a11y*  
([`docs/plans/1.0-ACTIVE-webkitgtk-android.md`](../../plans/1.0-ACTIVE-webkitgtk-android.md))

## Problem

- 🔷 In **OLLMchat / Llama chat**, the LLM drives the browser **in the background** (globe off / chat UI on top — WebView not shown).
- 🔷 It navigated to **Gemini** (web), then requested the **a11y power tree / markdown tree**.
- 🔷 The dump came back **empty** (or effectively empty — no usable page content for fill/press).
- 🔷 This matches the **known warning** from Phase 1 research: agent browse with WebView hidden/off-screen can leave layout and/or Chromium’s a11y provider in a state where the tree is empty or outer-shell-only.
- 🔷 Product requirement: dump / fill / press must work for **tool-only** browsing, same as when the page is on screen. TalkBack / AccessibilityService remain **🚫**.

## What already exists (not a full fix)

| Piece | Role |
|-------|------|
| `wka_host_a11y_ensure` / `WebViewA11y.ensure` | App-process force-on (DirectConnection + Chromium state notify) |
| `setVirtualSize` / `useDisplaySize` | Phone-sized fallback when GTK allocation is 0×0 |
| `host_area` map/unmap → `wka_host_put_is_visible` | Sets Android `View.VISIBLE` / `INVISIBLE` when GTK host maps/unmaps |
| Freeze `parkOffscreen` | Translation park — keeps `VISIBLE` (different path from globe-off) |

Globe-off / stack-hide uses **`INVISIBLE`**, not freeze park. That is the path under test.

## Hypotheses (ordered)

1. **`INVISIBLE` kills the provider tree** — Chromium / framework may withhold virtual children (or return null provider) when `getVisibility() != VISIBLE`, even with DirectConnection and non-zero layout.
2. **Obscured / z-order** — GTK SurfaceView on top (`setGtkSurfaceOnTop(true)` when hidden) may mark WebView content obscured → empty tree (same class of issue as freeze overlays; plan already notes provider null when obscured).
3. **0×0 or stale layout** — unmap stops the bounds tick; if virtual size was never applied (or was overwritten), measure/layout stays wrong and a11y bounds/children collapse.
4. **Ensure-once race** — `ensure` ran while visible; after hide + SPA navigation (Gemini), tree is not rebuilt until something re-wakes the provider while still invisible.
5. **SPA / heavy app shells** — Gemini may expose a thin a11y tree until interaction; less likely if the *same* page dumps richly when visible.

Do **not** jump to AccessibilityService. Exhaust visibility / layout / re-ensure first.

## Success criteria

- 🔷 After load settle with WebView **hidden** (`INVISIBLE` + SurfaceView on top), `wka_host_a11y_ensure` + walk yields a **non-empty** content tree (comparable order of magnitude to an on-screen dump of the same URL — not “1 outer WebView node”).
- 🔷 Bounds are phone-sized / non-zero (`w`/`h` > 0 on document / controls).
- 🔷 Fill/press still work on a known editable/button while hidden (smoke).
- 🔷 Re-show (map / `VISIBLE`) still works; no TalkBack required.

## Test mechanism

### A — Manual A/B in browser demo (do first)

Reproduce **without** OLLMchat so the library owns the failure.

1. Install/run `examples/browser`, load a **stable** page first (e.g. `https://roojs.com/` or a local `data:` HTML with a labeled button + text field). Keep Gemini as a second matrix row later.
2. **On-screen baseline:** tap **Dump a11y**. Record from logcat:
   - `WebViewA11y` `ensure:` / `walk: N nodes`
   - root child count, provider ok/null
3. **Hide WebView** without destroying it:
   - Prefer exercising the real path: put the WebView host in a `Gtk.Stack` (or temporarily unmap `host_area`) so `wka_host_put_is_visible(false)` runs — same as globe-off.
   - Or call host `setVisible(false)` from a temporary **“Hide WebView”** demo button.
4. Optionally navigate while hidden (or reload), wait for settle.
5. **Background dump:** Dump a11y again (ensure + walk). Compare node count and whether names/roles for page content appear.
6. **Restore** visibility; dump once more (sanity).

```bash
adb logcat -c
# … run A/B …
adb logcat -d -s WebViewA11y:I WebViewHost:I | rg "ensure:|walk:|setVisible|INVISIBLE|provider|rootChildren|contentView"
```

**Pass:** hidden dump `walk: N` with N roughly in the same ballpark as baseline (not 0–1).  
**Fail:** `provider=null`, `rootChildren=0`, or walk only outer shell — capture full ensure/walk lines + WebView `getWidth/Height/Visibility`.

### B — Demo harness button (recommended spike)

Add a single browser-demo control (throwaway OK until fixed):

**“Dump a11y (hidden)”** that:

1. Logs baseline walk count (optional).
2. Calls `wka_host_put_is_visible(false)` (or host `setVisible(false)`).
3. Waits ~500–1000 ms (or load-changed if it also reloads).
4. Runs `ensure` + `walk_foreach`; prints count + first ~12 lines.
5. Restores `setVisible(true)`.

This makes the bug one-tap and CI-scriptable via logcat.

### C — Matrix (after A fails or passes on static HTML)

| Case | Visible | URL | Expect |
|------|---------|-----|--------|
| Static form HTML | yes | local/data | rich tree |
| Static form HTML | **no** | same | rich tree ← **primary gate** |
| roojs.com | no | https | non-empty |
| gemini.google.com | no | https | non-empty (or document known SPA gaps) |
| After freeze park (translation) | parked | any | separate from INVISIBLE; note if dump works |

### D — Instrumentation to add while debugging

In `WebViewA11y.ensure` / `walk` (temporary `WebViewA11y` / `WkaA11yBg` tag):

- `wv.getVisibility()`, `getWidth()`, `getHeight()`, `getTranslationX()`, `getWindowToken()!=null`
- `provider == null?`, root `getChildCount()`, `forceOnDone`
- Whether `AccessibilityManager.isEnabled()` still true after hide

Correlate with `WebViewHost` visibility / z-order logs.

### E — Out of scope for this bug’s tests

- 🚫 Replacing a11y with DOM/JS scrape.
- 🚫 Requiring TalkBack or a production AccessibilityService.
- 🚫 OLLMchat markdown formatting bugs (empty **after** a rich host walk is a chat-side issue).

## Likely fix directions (after evidence)

Work top-down; pick based on A/D logs:

1. **Park like freeze, don’t `INVISIBLE`** — keep `VISIBLE`, translate off-screen (or alpha 0 if that still feeds a11y), keep phone-sized layout; SurfaceView on top for touches.
2. **Force measure/layout to virtual display size** on every hide and before ensure/walk when not mapped.
3. **Re-`ensure` after hide + after `onPageFinished`** while remaining hidden.
4. **If obscured is the gate** — adjust z-order / “not important for a11y” on the covering SurfaceView during tool-only mode (careful with freeze/dialogs).

## Decision log

| Date | Note |
|------|------|
| 2026-07-23 | Bug opened from Llama chat: Gemini loaded off-screen; a11y markdown tree empty. Aligns with plan warning on background browse / invisible WebView. |
| 2026-07-23 | Test plan: browser-demo A/B visible vs `INVISIBLE`; optional “Dump a11y (hidden)” harness; logcat ensure/walk + geometry. |
| 2026-07-23 | **Fix spike (dir 1):** `setVisible(false)` no longer uses `INVISIBLE` — parks with freeze translation + stays `VISIBLE`; `setBounds` / freeze exit respect `contentVisible`. Demo **Dump hidden** button exercises the path. |
| 2026-07-23 | Device: roojs parked dump **394 nodes**; Gemini (`gemini.google.com/app`) parked dump **74 nodes** (provider ok). Bounds subtract `translationX` so markdown `{x,y}` stay phone-relative. |
| 2026-07-23 | OLLMchat must pick up updated host Java (`install-webview-java.sh` / subproject) for globe-off browse. |

## Next agent action

1. Rebuild OLLMchat Android with this host Java; re-run Llama background browse → Gemini → a11y dump.
2. User **✅** this bug if markdown is non-empty off-screen.
