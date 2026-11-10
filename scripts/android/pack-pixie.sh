#!/usr/bin/env bash
# Pack the Android library this build installed into one .pixie file and
# write release.pins for it. A version tag uploads the file and publishes
# the pin list.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIXIEWOOD_BASE="${WEBKITGTK_ANDROID_PIXIEWOOD:-$ROOT_DIR/.pixiewood}"
BUILD_DIR="${PIXIE_BUILD_DIR:-$PIXIEWOOD_BASE/pixie-build}"
OUT="$ROOT_DIR/pixie-artifacts"
ABI=arm64-v8a
API=31
NAME=webkitgtk-android
PC_NAME=webkitgtk-android-1
TOKEN='@PIXIEWOOD_SYSROOT@'
# Same repo string as the GTK stack pins. pixie-pkg keeps every row whose
# repo matches the gtk checkout, so a merged pin list still installs this file.
GTK_REPO="https://gitlab.gnome.org/GNOME/gtk.git"

if [ ! -f "$BUILD_DIR/build.ninja" ]; then
  echo "Android build directory missing: $BUILD_DIR" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "pack-pixie needs jq" >&2
  exit 1
fi

version="$(sed -n "s/.*version: '\\([0-9][0-9.]*\\)'.*/\\1/p" "$ROOT_DIR/meson.build" | head -n1)"
if [ -z "$version" ]; then
  echo "Could not read the version from meson.build" >&2
  exit 1
fi
tag="${PIXIE_RELEASE_TAG:-}"
if [ -z "$tag" ] && [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
  tag="${GITHUB_REF_NAME}"
fi
if [ -z "$tag" ]; then
  tag="v$version"
fi
repo="${GITHUB_REPOSITORY:-roojs/webkitgtk-android}"
resolved="$(git -C "$ROOT_DIR" rev-parse HEAD)"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
meson="$("$ROOT_DIR/scripts/android/ensure-meson.sh")"
"$meson" install -C "$BUILD_DIR" --destdir "$stage/all" --no-rebuild

libdir="$stage/all/lib/$ABI"
so="$(find "$libdir" -maxdepth 1 -name "lib${PC_NAME}.so" -print -quit)"
if [ -z "$so" ]; then
  echo "Installed library missing: $libdir/lib${PC_NAME}.so" >&2
  exit 1
fi

one="$stage/one"
mkdir -p "$one/lib/$ABI/pkgconfig" "$one/include" "$one/share/vala/vapi"
find "$libdir" -maxdepth 1 -name "lib${PC_NAME}.so*" -exec cp -a {} "$one/lib/$ABI/" \;

if [ -f "$stage/all/include/webkitgtk-android.h" ]; then
  cp -a "$stage/all/include/webkitgtk-android.h" "$one/include/"
elif [ -f "$BUILD_DIR/webkitgtk-android.h" ]; then
  # Meson installs the checked-in VAPI and the host header. The generated
  # Vala header stays in the build directory; consumers' valac output includes it.
  cp -a "$BUILD_DIR/webkitgtk-android.h" "$one/include/"
fi
if [ ! -f "$one/include/webkitgtk-android.h" ]; then
  echo "Generated header missing: webkitgtk-android.h" >&2
  exit 1
fi
if [ -f "$stage/all/include/webkitgtk-android-host-api.h" ]; then
  cp -a "$stage/all/include/webkitgtk-android-host-api.h" "$one/include/"
fi
if [ -f "$stage/all/share/vala/vapi/${PC_NAME}.vapi" ]; then
  cp -a "$stage/all/share/vala/vapi/${PC_NAME}.vapi" "$one/share/vala/vapi/"
elif [ -f "$ROOT_DIR/vapi/${PC_NAME}.vapi" ]; then
  cp -a "$ROOT_DIR/vapi/${PC_NAME}.vapi" "$one/share/vala/vapi/"
fi

pc_src="$stage/all/lib/$ABI/pkgconfig/${PC_NAME}.pc"
if [ ! -f "$pc_src" ]; then
  echo "Installed pkg-config file missing: $pc_src" >&2
  exit 1
fi
awk -v token="$TOKEN" '
  $0 == "prefix=/" { print "prefix=" token; next }
  { print }
' "$pc_src" > "$one/lib/$ABI/pkgconfig/${PC_NAME}.pc"

java_src="$ROOT_DIR/lib/host/java"
java_dest="$one/share/pixiewood/webkitgtk-android-java"
if [ ! -d "$java_src/org/roojs/webkitgtk/android" ]; then
  echo "Host Java missing: $java_src" >&2
  exit 1
fi
mkdir -p "$java_dest"
cp -a "$java_src/org" "$java_dest/"

asset="${NAME}-arm-v${API}-${version}.pixie"
rm -rf "$OUT"
mkdir -p "$OUT"
tar -C "$one" -cJf "$OUT/$asset" .
inputs="$(sha256sum "$OUT/$asset" | awk '{ print $1 }')"
url="https://github.com/${repo}/releases/download/${tag}/${asset}"
jq -n \
  --arg abi "$ABI" \
  --arg repo_url "$GTK_REPO" \
  --arg name "$NAME" \
  --arg track "$version" \
  --arg resolved "$resolved" \
  --arg inputs "$inputs" \
  --arg url "$url" \
  '{packages: [{abi:$abi, repo:$repo_url, name:$name, track:$track, resolved:$resolved, inputs:$inputs, url:$url}]}' \
  > "$OUT/release.pins"
echo "Packed $asset"
echo "Wrote $OUT/release.pins"
