# Modal freeze (Android)

GTK dialogs paint into the `SurfaceView`. The System WebView is a separate Android `View` **above** that surface, so dialogs appear under the page.

## Behaviour

1. **Watch GTK** (same toplevel): GObject type name `AdwDialog` (type-name walk, no Adwaita link) or a transient `Gtk.Window` → enter freeze; unparent / unmap → resume. Hooks `parent-set` / `map` / `unmap`.
2. **Freeze:**
   - `PixelCopy` of the on-screen WebView.
   - If the WebView extends past the GTK `SurfaceView` (behind system nav), crop only that overlap — not the full nav inset (that over-crops once margins use density and matches `host_area`, which made FILL stretch).
   - Park WebView, raise SurfaceView, RGBA → `Gdk.MemoryTexture` → `Gtk.Picture` FILL in `host_area`.
3. **Resume:** clear picture, lower SurfaceView, unpark WebView.

WebView margins come from `wka_widget_bounds_xywh` using **float** `gdk_surface_get_scale()` (Android density), not integer `scale_factor`, so the overlay matches `host_area`.

**Auto only** — apps present dialogs; the WebView monitor freezes.

Related history: [`docs/bugs/2026-07-21-modal-freeze-lags-dialog.md`](bugs/2026-07-21-modal-freeze-lags-dialog.md).
