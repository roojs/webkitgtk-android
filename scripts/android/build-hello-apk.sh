#!/usr/bin/env bash
# Phase 1: build the GTK Hello World debug APK via Pixiewood (no WebView).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OLLMCHAT_ROOT="${OLLMCHAT_ROOT:-/home/alan/gitlive/OLLMchat}"
# Prefer a local SDK; otherwise reuse OLLMchat's installed Android SDK/NDK.
if [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  if [ -d "$ROOT_DIR/.android-sdk" ]; then
    ANDROID_SDK_ROOT="$ROOT_DIR/.android-sdk"
  elif [ -d "$OLLMCHAT_ROOT/.android-sdk" ]; then
    ANDROID_SDK_ROOT="$OLLMCHAT_ROOT/.android-sdk"
  else
    ANDROID_SDK_ROOT="$ROOT_DIR/.android-sdk"
  fi
fi

PIXIEWOOD_MANIFEST="${PIXIEWOOD_MANIFEST:-$ROOT_DIR/android/pixiewood-hello.xml}"
PIXIEWOOD_DIR="${PIXIEWOOD_DIR:-$ROOT_DIR/.android-tools/gtk-android-builder}"
if [ ! -x "$PIXIEWOOD_DIR/pixiewood" ] &&
   [ -x "$OLLMCHAT_ROOT/.android-tools/gtk-android-builder/pixiewood" ]; then
  PIXIEWOOD_DIR="$OLLMCHAT_ROOT/.android-tools/gtk-android-builder"
fi

PIXIEWOOD_ARCH="${PIXIEWOOD_ARCH:-aarch64}"
PIXIEWOOD_BUILD_DIR="$ROOT_DIR/.pixiewood/bin-$PIXIEWOOD_ARCH"
PIXIEWOOD="${PIXIEWOOD:-}"
PIXIEWOOD_PHASE="${PIXIEWOOD_PHASE:-all}"
GTK_ANDROID_BUILDER_REVISION="${GTK_ANDROID_BUILDER_REVISION:-}"

# shellcheck source=android-meson-path.sh
source "$ROOT_DIR/scripts/android/android-meson-path.sh"

read_gtk_android_builder_revision() {
  local revision_file="$ROOT_DIR/scripts/android/gtk-android-builder.revision"
  if [ -z "$GTK_ANDROID_BUILDER_REVISION" ] && [ -f "$revision_file" ]; then
    GTK_ANDROID_BUILDER_REVISION="$(
      grep -v '^[[:space:]]*#' "$revision_file" | grep -v '^[[:space:]]*$' | head -n1 | tr -d '[:space:]'
    )"
  fi
}

ensure_android_meson() {
  MESON_FOR_ANDROID="$ROOT_DIR/scripts/android/meson-for-pixiewood.sh"
  "$ROOT_DIR/scripts/android/ensure-meson.sh" >/dev/null
}

ensure_gtk_android_builder() {
  if [ -n "$PIXIEWOOD" ]; then
    return
  fi
  if command -v pixiewood >/dev/null 2>&1; then
    PIXIEWOOD="$(command -v pixiewood)"
    return
  fi

  read_gtk_android_builder_revision

  if [ ! -x "$PIXIEWOOD_DIR/pixiewood" ]; then
    mkdir -p "$(dirname "$PIXIEWOOD_DIR")"
    rm -rf "$PIXIEWOOD_DIR"
    git clone https://github.com/sp1ritCS/gtk-android-builder.git "$PIXIEWOOD_DIR"
    if [ -n "$GTK_ANDROID_BUILDER_REVISION" ]; then
      git -C "$PIXIEWOOD_DIR" checkout "$GTK_ANDROID_BUILDER_REVISION"
    fi
  fi
  PIXIEWOOD="$PIXIEWOOD_DIR/pixiewood"
}

pixiewood_configure_options() {
  if [ ! -f "$PIXIEWOOD_MANIFEST" ]; then
    echo "Pixiewood manifest not found: $PIXIEWOOD_MANIFEST" >&2
    exit 1
  fi
  python3 - "$PIXIEWOOD_MANIFEST" <<'PY'
import sys
import xml.etree.ElementTree as ET

NS = {"pw": "https://sp1rit.arpa/pixiewood/"}
root = ET.parse(sys.argv[1]).getroot()
for option in root.findall(".//pw:build/pw:configure-options/pw:option", NS):
    text = (option.text or "").strip()
    if text:
        print(text)
PY
}

pixiewood_toolchain_ready() {
  [ -f "$PIXIEWOOD_BUILD_DIR/build.ninja" ] &&
    [ -f "$ROOT_DIR/.pixiewood/pixiewood.ini" ] &&
    [ -f "$ROOT_DIR/.pixiewood/toolchain.cross" ]
}

install_pixiewood_extra_wraps() {
  local extra="$ROOT_DIR/android/pixiewood-wraps"
  if [ ! -d "$extra" ]; then
    return
  fi

  mkdir -p "$ROOT_DIR/subprojects"

  local dep_dir dep dest wrap
  for dep_dir in "$extra"/*/; do
    [ -d "$dep_dir" ] || continue
    dep="$(basename "$dep_dir")"
    dest="$PIXIEWOOD_DIR/prepare/wraps/$dep"
    if mkdir -p "$dest" 2>/dev/null; then
      cp -a "$dep_dir"/* "$dest/" 2>/dev/null || true
    fi

    for wrap in "$dep_dir"/*.wrap; do
      if [ -f "$wrap" ]; then
        cp -a "$wrap" "$ROOT_DIR/subprojects/"
      fi
    done

    if [ -d "$dep_dir/packagefiles" ]; then
      mkdir -p "$ROOT_DIR/subprojects/packagefiles"
      cp -a "$dep_dir/packagefiles/." "$ROOT_DIR/subprojects/packagefiles/"
    fi
  done
}

init_pixiewood_env() {
  if [ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ] ||
     [ ! -d "$ANDROID_SDK_ROOT/ndk" ]; then
    echo "Android SDK incomplete at $ANDROID_SDK_ROOT — running install-sdk.sh" >&2
    ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" "$ROOT_DIR/scripts/android/install-sdk.sh"
  fi

  ensure_gtk_android_builder
  install_pixiewood_extra_wraps
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
  export ANDROID_SDK_ROOT
  export CC="${CC:-gcc}"
  export CXX="${CXX:-g++}"
  export CC_FOR_BUILD="${CC_FOR_BUILD:-gcc}"
  export CXX_FOR_BUILD="${CXX_FOR_BUILD:-g++}"
  ensure_android_meson
  mapfile -t PIXIEWOOD_CONFIGURE_OPTIONS < <(pixiewood_configure_options)
}

run_pixiewood() {
  with_android_meson_path "$PIXIEWOOD" -C "$ROOT_DIR" "$@"
}

reconfigure_pixiewood_build() {
  local meson="$1"
  shift
  local -a configure_options=("$@")
  local -a cross_files=(
    --cross-file "$ROOT_DIR/.pixiewood/toolchain.cross"
    --cross-file "$PIXIEWOOD_DIR/prepare/arch/$PIXIEWOOD_ARCH.cross"
    --cross-file "$PIXIEWOOD_DIR/prepare/android.cross"
  )
  local -a setup_args=(setup)
  if [ -f "$PIXIEWOOD_BUILD_DIR/build.ninja" ]; then
    setup_args+=(--reconfigure)
  fi

  with_android_meson_path "$meson" "${setup_args[@]}" \
    "${cross_files[@]}" \
    --buildtype debug \
    -Dstrip=false \
    "${configure_options[@]}" \
    "$PIXIEWOOD_BUILD_DIR" \
    "$ROOT_DIR"
}

patch_pixiewood_gradle_native_libs() {
  local gradle="$ROOT_DIR/.pixiewood/android/app/build.gradle"
  if [ ! -f "$gradle" ] || grep -q 'useLegacyPackaging' "$gradle"; then
    return 0
  fi
  sed -i '/enableKotlin = false/a\
\
    packaging {\
        jniLibs {\
            useLegacyPackaging = true\
        }\
    }' "$gradle"
}

install_webview_java() {
  local dest="$ROOT_DIR/.pixiewood/android/app/src/main/java/org/roojs/webkitgtk/android"
  local src="$ROOT_DIR/lib/host/java/org/roojs/webkitgtk/android"

  if [ ! -d "$src" ]; then
    return 0
  fi
  mkdir -p "$dest"
  # Drop obsolete WakeA11yService if a prior build left it in the tree.
  rm -f "$dest/WakeA11yService.java"
  cp -a "$src"/*.java "$dest/"
  echo "Installed WebViewHost Java into $dest"
}

strip_wake_a11y_service_from_manifest() {
  local manifest="$ROOT_DIR/.pixiewood/android/app/src/main/AndroidManifest.xml"
  if [ ! -f "$manifest" ]; then
    return 0
  fi
  if ! grep -q 'WakeA11yService' "$manifest"; then
    return 0
  fi
  python3 - "$manifest" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
text2, n = re.subn(
    r'\s*<service\b[^>]*WakeA11yService[\s\S]*?</service>\s*',
    '\n',
    text,
    count=1,
)
if n:
    path.write_text(text2)
    print('Removed WakeA11yService from AndroidManifest')
PY
  # Also drop leftover wake a11y resources if present
  rm -f "$ROOT_DIR/.pixiewood/android/app/src/main/res/xml/wake_a11y_service.xml"
  rm -f "$ROOT_DIR/.pixiewood/android/app/src/main/res/values/wake_a11y_strings.xml"
}

patch_android_manifest_launch_mode() {
  local manifest="$ROOT_DIR/.pixiewood/android/app/src/main/AndroidManifest.xml"
  if [ ! -f "$manifest" ]; then
    echo "AndroidManifest missing: $manifest" >&2
    exit 1
  fi
  if grep -q 'android:launchMode="standard"' "$manifest"; then
    sed -i 's/android:launchMode="standard"/android:launchMode="singleTask"/' "$manifest"
  fi
}

materialize_pixiewood_jni_libs() {
  local jni="$ROOT_DIR/.pixiewood/android/app/src/main/jniLibs"
  local root_lib="$ROOT_DIR/.pixiewood/root/lib"
  if [ ! -d "$root_lib" ]; then
    echo "Pixiewood install tree missing: $root_lib" >&2
    exit 1
  fi
  rm -f "$jni"
  rm -rf "$jni"
  mkdir -p "$jni"
  cp -a "$root_lib/." "$jni/"
}

run_pixiewood_gradle_assemble() {
  (
    cd "$ROOT_DIR/.pixiewood/android"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    ./gradlew --no-daemon assembleDebug
  )
}

verify_apk() {
  local apk="$ROOT_DIR/.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk"
  local so_name="libwebkitgtk-android-hello.so"
  local listing

  if [[ "$PIXIEWOOD_MANIFEST" == *pixiewood-browser.xml ]]; then
    so_name="libwebkitgtk-android-browser.so"
  fi

  if [ ! -f "$apk" ]; then
    echo "APK not found: $apk" >&2
    exit 1
  fi
  listing="$(unzip -l "$apk")"
  if ! grep -q "lib/arm64-v8a/$so_name" <<<"$listing"; then
    echo "APK missing $so_name" >&2
    grep 'lib/arm64-v8a/' <<<"$listing" >&2 || true
    exit 1
  fi
  echo "Verified $apk contains $so_name"
}

run_pixiewood_setup() {
  init_pixiewood_env
  if ! pixiewood_toolchain_ready; then
    run_pixiewood prepare \
      --sdk "$ANDROID_SDK_ROOT" \
      --meson "$MESON_FOR_ANDROID" \
      "$PIXIEWOOD_MANIFEST"
  fi
}

run_pixiewood_build() {
  init_pixiewood_env
  echo "Reconfiguring Pixiewood Meson build."
  reconfigure_pixiewood_build "$MESON_FOR_ANDROID" "${PIXIEWOOD_CONFIGURE_OPTIONS[@]}"
  # Prior builds materialize jniLibs as a real dir; pixiewood generate needs a symlink.
  rm -rf "$ROOT_DIR/.pixiewood/android/app/src/main/jniLibs"
  run_pixiewood generate
  patch_pixiewood_gradle_native_libs
  install_webview_java
  run_pixiewood build --skip-gradle
  materialize_pixiewood_jni_libs
  # generate may wipe app Java — re-copy after meson install / generate
  install_webview_java
  patch_android_manifest_launch_mode
  strip_wake_a11y_service_from_manifest
  run_pixiewood_gradle_assemble
  verify_apk
  echo "Generated Android artifacts under $ROOT_DIR/.pixiewood/android/app/build/outputs"
}

case "$PIXIEWOOD_PHASE" in
  setup)
    run_pixiewood_setup
    ;;
  build)
    run_pixiewood_build
    ;;
  all)
    run_pixiewood_setup
    run_pixiewood_build
    ;;
  *)
    echo "Unknown PIXIEWOOD_PHASE: $PIXIEWOOD_PHASE (expected setup, build, or all)" >&2
    exit 2
    ;;
esac
