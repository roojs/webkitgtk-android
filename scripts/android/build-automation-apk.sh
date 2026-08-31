#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PIXIEWOOD_MANIFEST="${PIXIEWOOD_MANIFEST:-$ROOT_DIR/android/pixiewood-automation.xml}"
# New app id / target vs browser/hello — refresh Pixiewood prepare metadata.
if [ -f "$ROOT_DIR/.pixiewood/pixiewood.ini" ] &&
   ! grep -q 'pixiewood-automation.xml' "$ROOT_DIR/.pixiewood/pixiewood.ini" 2>/dev/null; then
  rm -f "$ROOT_DIR/.pixiewood/pixiewood.ini"
fi
exec "$ROOT_DIR/scripts/android/build-hello-apk.sh"
