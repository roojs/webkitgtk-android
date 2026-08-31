#!/usr/bin/env bash
# Verify the tree is ready, then tag + push. GitHub Actions publishes the tarball.
#
# 1. Read latest ## [X.Y.Z] - Unreleased from CHANGELOG.md
# 2. Require meson.build project version == X.Y.Z
# 3. Exit if tag vX.Y.Z already exists (local or origin)
#    unless --retry: delete that tag locally and on origin, then continue
# 4. Verify: clean tree, non-empty notes
# 5. git tag -a + git push (branch + tag) → GitHub Actions publishes the release
#
# AGENTS ARE BANNED from running this script. The human runs it in a normal terminal.
set -euo pipefail

if [[ "${CURSOR_AGENT:-}" == "1" ]]; then
	cat >&2 <<'EOF'
error: agents are banned from running scripts/release.sh.

Do not work around this. The human must run scripts/release.sh in a normal
terminal.
EOF
	exit 1
fi

retry=0
for arg in "$@"; do
	case "${arg}" in
		--retry)
			retry=1
			;;
		-h|--help)
			cat <<'EOF'
Usage: scripts/release.sh [--retry]

Create an annotated tag from CHANGELOG.md and push it to origin.

  --retry   Delete the existing version tag locally and on origin, then
            retag HEAD and push (use after a failed release CI run).
EOF
			exit 0
			;;
		*)
			echo "error: unknown option: ${arg}" >&2
			echo "Usage: scripts/release.sh [--retry]" >&2
			exit 1
			;;
	esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root}"

if [[ ! -f CHANGELOG.md ]]; then
	echo "error: missing CHANGELOG.md" >&2
	exit 1
fi

chmod +x scripts/release/changelog.sh
ver="$(scripts/release/changelog.sh version)"
tag="v${ver}"
notes="$(scripts/release/changelog.sh notes)"
meson_ver="$(sed -n "s/^[[:space:]]*version: '\\([^']*\\)'.*/\\1/p" meson.build | head -1)"

echo "CHANGELOG.md latest: ${ver}"
echo "meson.build version: ${meson_ver}"
echo "Tag: ${tag}"
echo "---- notes ----"
echo "${notes}"
echo "---------------"

if [[ -z "${meson_ver}" ]]; then
	echo "error: could not read project version from meson.build" >&2
	exit 1
fi
if [[ "${meson_ver}" != "${ver}" ]]; then
	echo "error: meson.build version ${meson_ver} != CHANGELOG ${ver}" >&2
	exit 1
fi

if [[ -z "${notes//[[:space:]]/}" ]]; then
	echo "error: empty notes for ${ver} — fill CHANGELOG.md first" >&2
	exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
	echo "error: working tree not clean — commit or stash before releasing" >&2
	git status --short >&2
	exit 1
fi

git fetch --tags origin 2>/dev/null || true

if [[ "${retry}" -eq 1 ]]; then
	if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
		echo "Deleting local tag ${tag}..."
		git tag -d "${tag}"
	fi
	if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
		echo "Deleting origin tag ${tag}..."
		git push origin --delete "refs/tags/${tag}"
	fi
fi

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
	echo "Tag ${tag} already exists locally — nothing to do."
	echo "Re-run with --retry to delete it and retag HEAD." >&2
	exit 0
fi

if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
	echo "Tag ${tag} already exists on origin — nothing to do."
	echo "Re-run with --retry to delete it and retag HEAD." >&2
	exit 0
fi

echo "Creating annotated tag ${tag}..."
git tag -a "${tag}" -m "${tag}"

branch="$(git rev-parse --abbrev-ref HEAD)"
echo "Pushing ${branch} and ${tag} to origin..."
git push -u origin "${branch}"
git push origin "${tag}"

echo "Released ${tag}. GitHub Actions will attach webkitgtk-android-${ver}.tar.gz and publish the GitHub Release."
echo "After that lands, date the changelog section (${ver}) and add ## [next] - Unreleased (bump meson.build)."
