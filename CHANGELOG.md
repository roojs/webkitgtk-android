# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [0.1.4] - Unreleased

### Added

- Automation setup API (layer B only): `WebContext`, `AutomationSession`,
  `ApplicationInfo`, `WebViewSettings`; construct props
  `web_context` / `network_session` / `is_controlled_by_automation`
  ([plan 1.4](docs/plans/1.4-android-automation-parity.md)).
- CDP host bridge: `WEBKIT_INSPECTOR_SERVER` → loopback TCP →
  `@webview_devtools_remote_<pid>` (`WebViewCdpBridge`).
- `examples/automation/` setup smoke + Android build/smoke scripts.

## [0.1.3] - 2026-08-22

### Added

- AssistStructure HTML `name` / `id` / `tag` on a11y walk nodes (`AndroidAtspi` attrs, same keys as WebKitGTK) ([plan 1.3](docs/plans/1.3-a11y-html-name-attribute.md)).
- GitHub source-tarball releases (tag via `scripts/release.sh`; [`.github/workflows/release.yml`](.github/workflows/release.yml) publishes the asset).

### Fixed

- `WebView.network_session` is a WebKitGTK-shaped `{ get; construct; }` property (handwritten `get_network_session()` only broke `.network_session` in consumers) ([bug](docs/bugs/2026-08-22-network-session-property.md)).
- A11y walk on the GTK thread deadlocked Android `main` (ANR); walk is async ([bug](docs/bugs/2026-07-23-a11y-walk-gtk-thread-anr.md)).
- Off-screen / unfocused WebView a11y tree was empty until force-on ([bug](docs/bugs/2026-07-23-offscreen-a11y-empty-tree.md)).

## [0.1.2] - 2026-07-22

### Added

- `WebView.main_document_response` — main-frame HTTP status + `Soup.MessageHeaders` (Cloudflare / OLLMchat).

## [0.1.1] - 2026-07-22

### Added

- `AndroidAtspi` facade over host a11y (Win32Atspi parallel).
- WebKitGTK-shaped settle APIs: `is_loading`, `estimated_load_progress`, `load_failed`, `reload_bypass_cache`, stub `evaluate_javascript`.

### Changed

- Dropped deprecated `WebView.loading`; keep `is_loading` only.

## [0.1.0] - 2026-07-22

First tagged library: GTK 4 widget embedding Android System WebView (`libwebkitgtk-android-1` + VAPI / pkg-config), host a11y dump/fill/press, downloads, freeze frame, hello/browser example APKs.
