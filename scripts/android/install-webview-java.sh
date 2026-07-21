#!/usr/bin/env bash
# Copy WebViewHost Java into a consumer Android app source tree.
#
# Usage:
#   ./scripts/android/install-webview-java.sh <java-src-root>
#
# <java-src-root> is the app Java root that already contains (or will contain)
# package directories, e.g.:
#   .pixiewood/android/app/src/main/java
#
# Installs:
#   <java-src-root>/org/roojs/webkitgtk/android/*.java
#
# Consumers must ship these classes in the same APK as libwebkitgtk-android-1.so
# (JNI looks them up via the activity ClassLoader).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT_DIR/lib/host/java/org/roojs/webkitgtk/android"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <java-src-root>" >&2
  exit 2
fi

JAVA_ROOT="$(cd "$1" && pwd)"
DEST="$JAVA_ROOT/org/roojs/webkitgtk/android"

if [ ! -d "$SRC" ]; then
  echo "Missing host Java: $SRC" >&2
  exit 1
fi

mkdir -p "$DEST"
# Drop obsolete WakeA11yService if a prior build left it in the tree.
rm -f "$DEST/WakeA11yService.java"
cp -a "$SRC"/*.java "$DEST/"
echo "Installed WebViewHost Java into $DEST"
