# Releasing

This repo's release flow is **tag-driven**. The artifact is a **source tarball** (Meson wrap-file), not a prebuilt `.so`.

## What `scripts/release.sh` does

- reads the first `CHANGELOG.md` section and expects `## [X.Y.Z] - Unreleased`
- requires `meson.build` project version to match `X.Y.Z`
- prints the notes that will become the GitHub Release body
- refuses to run on a dirty working tree
- refuses to reuse an existing local or remote tag unless you pass `--retry`
- creates annotated tag `vX.Y.Z`
- pushes the current branch and the tag to `origin`

`--retry` deletes the existing `vX.Y.Z` tag locally and on `origin`, then retags `HEAD`. Use that only after a failed release CI run.

## GitHub Actions

Pushing `vX.Y.Z` triggers [`.github/workflows/release.yml`](../.github/workflows/release.yml), which:

- builds `dist/webkitgtk-android-X.Y.Z.tar.gz` via `git archive` (gzip `-n` so the SHA-256 is stable)
- writes a matching `.sha256` sidecar
- renders `release-notes.md` from the matching `CHANGELOG.md` section
- appends a Meson `wrap-file` pin (`source_url` + `source_hash`) to the notes
- publishes the tarball, checksum, and notes as the GitHub Release

`workflow_dispatch` builds the tarball without publishing.

GitHub's auto-generated “Source code” archives are **not** the pin — their hashes are not stable. Use the attached `webkitgtk-android-*.tar.gz`.

## Changelog format

Before releasing, the first section in `CHANGELOG.md` must look like:

```md
## [0.1.3] - Unreleased
```

After the tag lands, convert that section to a dated entry and add a fresh `## [next] - Unreleased` section (bump `meson.build` to match).

## Consumer pin

Copy the **Wrap pin** block from the GitHub Release notes (CI fills in the hash):

```ini
[wrap-file]
directory = webkitgtk-android-0.1.3
source_url = https://github.com/roojs/webkitgtk-android/releases/download/v0.1.3/webkitgtk-android-0.1.3.tar.gz
source_filename = webkitgtk-android-0.1.3.tar.gz
source_hash = <sha256 from the release>

[provide]
dependency_names = webkitgtk-android-1
```

`wrap-git` with `revision = v0.1.3` also works; the tarball hash is the reproducible option.
