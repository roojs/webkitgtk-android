# Releasing

This repo's release flow is **tag-driven**. The artifacts are a **source tarball** (Meson wrap-file) and a prebuilt Android **`.pixie`** library.

## What `scripts/release.sh` does

- reads the first `CHANGELOG.md` section and expects `## [X.Y.Z] - Unreleased`
- requires `meson.build` project version to match `X.Y.Z`
- prints the notes that will become the GitHub Release body
- refuses to run on a dirty working tree
- refuses to reuse an existing local or remote tag unless you pass `--retry`
- creates annotated tag `vX.Y.Z`
- pushes the current branch and the tag to `origin`

`--retry` deletes the existing `vX.Y.Z` tag locally and on `origin`, then retags `HEAD`. Use that only after a failed release CI run.

**Agents must not run `scripts/release.sh`.** The human runs it in a normal terminal.

## GitHub Actions

Pushing `vX.Y.Z` triggers [`.github/workflows/release.yml`](../.github/workflows/release.yml), which:

- builds `dist/webkitgtk-android-X.Y.Z.tar.gz` via `git archive` (gzip `-n` so the SHA-256 is stable)
- writes a matching `.sha256` sidecar
- renders `release-notes.md` from the matching `CHANGELOG.md` section
- appends a Meson `wrap-file` pin (`source_url` + `source_hash`) to the notes
- publishes the tarball, checksum, and notes as the GitHub Release
- cross-compiles `libwebkitgtk-android-1` against the published pixie sysroot ([`scripts/android/build-pixie.sh`](../scripts/android/build-pixie.sh))
- attaches `webkitgtk-android-arm-v31-X.Y.Z.pixie` and `release.pins` to that release
- commits `release.pins` on `main`. That push runs [`.github/workflows/pages.yml`](../.github/workflows/pages.yml), which deploys `https://roojs.github.io/webkitgtk-android/release.pins`. The tag job does not deploy: the `github-pages` environment only allows `main`.

`workflow_dispatch` builds the tarball and the `.pixie` without publishing.

GitHub's auto-generated “Source code” archives are **not** the pin — their hashes are not stable. Use the attached `webkitgtk-android-*.tar.gz`.

## Changelog format

Before releasing, the first section in `CHANGELOG.md` must look like:

```md
## [0.1.4] - Unreleased
```

After the tag lands, convert that section to a dated entry and add a fresh `## [next] - Unreleased` section (bump `meson.build` to match).

## Consumer pin

Copy the **Wrap pin** block from the GitHub Release notes (CI fills in the hash):

```ini
[wrap-file]
directory = webkitgtk-android-0.1.4
source_url = https://github.com/roojs/webkitgtk-android/releases/download/v0.1.4/webkitgtk-android-0.1.4.tar.gz
source_filename = webkitgtk-android-0.1.4.tar.gz
source_hash = <sha256 from the release>

[provide]
dependency_names = webkitgtk-android-1
```

`wrap-git` with `revision = v0.1.4` also works; the tarball hash is the reproducible option.
