#!/usr/bin/env bash
# Fails if the built macOS binary still contains private WebKit KVC keys, the
# private NSView override tao had, or Tauri's private-API code paths. Usage: scripts/check-private-api.sh [path/to/MemoBuddy.app]
set -euo pipefail
APP="${1:-src-tauri/target/universal-apple-darwin/release/bundle/macos/MemoBuddy.app}"
BIN="$APP/Contents/MacOS/memopet"
[[ -f "$BIN" ]] || { echo "binary not found: $BIN" >&2; exit 2; }
# The private keys wry uses: three it always set (patched out in vendor/wry) and
# the web inspector ones behind debug builds / the `devtools` feature. And the
# private NSView method tao overrode (patched out in vendor/tao).
KEYS='allowsPictureInPictureMediaPlayback|drawsBackground|fullScreenEnabled|proxyConfigurations|_setDrawsBackground|setDrawsBackground|developerExtrasEnabled|_inspector|_wantsKeyDownForEvent'
# Read the strings once; a failing `strings` must not look like a clean binary.
STRINGS="$(strings -a "$BIN")" || { echo "strings failed on $BIN" >&2; exit 2; }
if grep -E "$KEYS" <<<"$STRINGS"; then
  echo "FAIL: private API strings found in $BIN" >&2
  exit 1
fi
echo "PASS: no private WebKit KVC keys or private NSView overrides in $BIN"
