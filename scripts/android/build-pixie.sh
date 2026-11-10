#!/usr/bin/env bash
# Cross-compile libwebkitgtk-android-1 against the published pixie sysroot
# and pack webkitgtk-android-arm-v31-<version>.pixie.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIXIEWOOD_BASE="${WEBKITGTK_ANDROID_PIXIEWOOD:-$ROOT_DIR/.pixiewood}"
BUILD_DIR="$PIXIEWOOD_BASE/pixie-build"
ABI=arm64-v8a
API=31
NDK_VERSION="${ANDROID_NDK_VERSION:-28.2.13676358}"

need_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing host tool: $1" >&2
    exit 1
  fi
}

need_vapi() {
  local name=$1 package=$2
  if [ ! -f "/usr/share/vala/vapi/${name}" ] && [ ! -f "/usr/share/vala-0.56/vapi/${name}" ]; then
    if ! find /usr/share -path "*/vapi/${name}" -print -quit 2>/dev/null | grep -q .; then
      echo "Missing Vala binding ${name} (package ${package})" >&2
      exit 1
    fi
  fi
}

need_tool ninja
need_tool pkg-config
need_tool valac
need_tool jq
need_tool python3
need_vapi gtk4.vapi libgtk-4-dev
need_vapi libsoup-3.0.vapi libsoup-3.0-dev
need_vapi glib-2.0.vapi libglib2.0-dev

if [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  if [ -d "$ROOT_DIR/.android-sdk" ]; then
    ANDROID_SDK_ROOT="$ROOT_DIR/.android-sdk"
  elif [ -d /home/alan/gitlive/OLLMchat/.android-sdk ]; then
    ANDROID_SDK_ROOT=/home/alan/gitlive/OLLMchat/.android-sdk
  else
    ANDROID_SDK_ROOT="$ROOT_DIR/.android-sdk"
  fi
fi
export ANDROID_SDK_ROOT
if [ ! -d "$ANDROID_SDK_ROOT/ndk/$NDK_VERSION" ]; then
  "$ROOT_DIR/scripts/android/install-sdk.sh"
fi

NDK="$ANDROID_SDK_ROOT/ndk/$NDK_VERSION"
prebuilt="$(find "$NDK/toolchains/llvm/prebuilt" -mindepth 1 -maxdepth 1 -type d | head -n1)"
if [ -z "$prebuilt" ]; then
  echo "NDK LLVM prebuilt directory missing under $NDK" >&2
  exit 1
fi

PIXIEWOOD_PIXIE="$("$ROOT_DIR/scripts/android/fetch-pixie-deps.sh")"
export PIXIEWOOD_PIXIE
if [ ! -f "$PIXIEWOOD_PIXIE/share/pixiewood/pixie.cross" ]; then
  echo "Pixie cross file missing: $PIXIEWOOD_PIXIE" >&2
  exit 1
fi

cross="$PIXIEWOOD_BASE/pixie-toolchain.cross"
cat > "$cross" << EOF
[constants]
toolchain = '$prebuilt/'
arch = 'aarch64'
abi = '$ABI'
platform = 'android'

[binaries]
c = toolchain / 'bin' / arch+'-linux-'+platform+'${API}-clang'
cpp = toolchain / 'bin' / arch+'-linux-'+platform+'${API}-clang++'
ar = toolchain / 'bin/llvm-ar'
strip = toolchain / 'bin/llvm-strip'

[built-in options]
c_link_args = ['-Wl,--build-id=sha1']
prefix = '/'
libdir = 'lib' / abi

[properties]
sys_root = toolchain / 'sysroot/'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

meson="$("$ROOT_DIR/scripts/android/ensure-meson.sh")"
if [ -f "$BUILD_DIR/build.ninja" ] &&
   ! grep -q 'pkg-config-wrapper' "$BUILD_DIR/meson-logs/meson-log.txt" 2>/dev/null; then
  echo "Removing the previous library build so Meson loads the pixie cross file."
  rm -rf "$BUILD_DIR"
fi
if [ ! -f "$BUILD_DIR/build.ninja" ]; then
  "$meson" setup \
    --cross-file "$cross" \
    --cross-file "$PIXIEWOOD_PIXIE/share/pixiewood/pixie.cross" \
    --buildtype debug \
    "$BUILD_DIR" \
    "$ROOT_DIR"
fi
ninja -C "$BUILD_DIR"
PIXIE_BUILD_DIR="$BUILD_DIR" "$ROOT_DIR/scripts/android/pack-pixie.sh"
