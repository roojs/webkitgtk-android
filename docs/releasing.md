# Releasing

This repo’s release flow is **tag-driven** (same idea as webview2-gtk). Android
does not ship a prebuilt APK or pacman package from CI — the downloadable asset
is a **source tarball** for Meson / Pixiewood consumers.

## What `scripts/release.sh` does

- reads the first `CHANGELOG.md` section and expects `## [X.Y.Z] - Unreleased`
- prints the notes that will become the GitHub Release body
- refuses to run on a dirty working tree
- refuses to reuse an existing local or remote tag unless you pass `--retry`
- creates annotated tag `vX.Y.Z`
- pushes the current branch and the tag to `origin`

`--retry` deletes the existing `vX.Y.Z` tag locally and on `origin`, then retags
`HEAD`. Use that after a failed release CI run, or to replace an informal early
tag with the first official changelog-backed release.

**Agents must not run `scripts/release.sh`.** The human runs it in a normal
terminal.

## GitHub Actions

Pushing `vX.Y.Z` triggers [`.github/workflows/release.yml`](.github/workflows/release.yml), which:

- builds `webkitgtk-android-X.Y.Z.tar.gz` via `git archive`
- renders `release-notes.md` from the matching `CHANGELOG.md` section
- publishes the tarball and changelog text as a GitHub Release

## Changelog format

Before releasing, the first section in `CHANGELOG.md` must look like:

```md
## [0.1.0] - Unreleased
```

After the tag lands, convert that section to a dated entry and add a fresh
`## [Unreleased]` (or `## [next] - Unreleased`) section for the next cycle.

Keep `meson.build` `project(... version: ...)` in sync with the tag you cut.

## First official 0.1.0

Informal tags `v0.1.0`–`v0.1.2` existed before this process (no Release assets).
For the first GitHub + CHANGELOG release of the full tree:

1. Land / commit everything that belongs in 0.1.0 (clean `git status`).
2. Ensure `CHANGELOG.md` starts with `## [0.1.0] - Unreleased` and `meson.build`
   has `version: '0.1.0'`.
3. Run `scripts/release.sh --retry` so `v0.1.0` points at that commit and CI
   publishes the `.tar.gz`.

If you prefer to leave the old tags alone, bump the changelog (and meson) to
`0.1.3` or `0.2.0` and run `scripts/release.sh` without `--retry`.
