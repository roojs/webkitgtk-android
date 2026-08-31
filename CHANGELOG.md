# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Informal git tags `v0.1.0`–`v0.1.2` predated this file and had no GitHub Release
assets. The first official release is **0.1.0** (retag with
`scripts/release.sh --retry` after landing, or bump the heading if you prefer to
keep those tags untouched).

## [0.1.0] - Unreleased

First public snapshot of **webkitgtk-android** — GTK 4 + Android System WebView
with a WebKitGTK-shaped Vala API (Android sibling of webview2-gtk).

### Added

- `libwebkitgtk-android-1` shared library: `WebView` embed, load/navigation,
  freeze frame, cookies / `NetworkSession`, downloads (`download_uri` /
  `download_started`).
- Host JNI + Java (`WebViewHost`, a11y, cookies, downloads) for Pixiewood /
  consumer APKs; `scripts/android/install-webview-java.sh`.
- `AndroidAtspi` facade over host a11y (Win32Atspi parallel) — dump / fill /
  press path for OLLMchat-style tools.
- `main_document_response` and settle-oriented load APIs for browser hosts.
- Consumer packaging: checked-in `vapi/webkitgtk-android-1.vapi`, pkg-config,
  `meson.override_dependency('webkitgtk-android-1')` ([plan 1.2](docs/plans/1.2-consumer-packaging.md)).
- Automation setup API (layer B only): `WebContext`, `AutomationSession`,
  `ApplicationInfo`, `WebViewSettings`; construct props
  `web_context` / `network_session` / `is_controlled_by_automation`
  ([plan 1.3](docs/plans/1.3-android-automation-parity.md)).
- CDP host bridge: `WEBKIT_INSPECTOR_SERVER` → loopback TCP →
  `@webview_devtools_remote_<pid>` (`WebViewCdpBridge`, Phase 0 spike).
- Examples: hello, browser, automation setup smoke; Android build/smoke scripts
  under `scripts/android/`.
- Tag-driven GitHub Releases with source `.tar.gz` ([docs/releasing.md](docs/releasing.md)).

### Notes

- **One** System WebView host per process on Android (not Windows multi-host).
- Public click/type stay out of this library — CDP fill/press is the consumer
  (`WebDriverCdp` in OLLMchat).
- Example APKs are build artifacts, not release assets; consumers build against
  the tagged source / Meson subproject.
