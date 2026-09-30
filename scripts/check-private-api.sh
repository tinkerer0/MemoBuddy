#!/usr/bin/env bash
# Fails if the built macOS binary still contains private WebKit KVC keys or
# Tauri's private-API code paths. Usage: scripts/check-private-api.sh [path/to/MemoPet.app]
set -euo pipefail
APP="${1:-src-tauri/target/universal-apple-darwin/release/bundle/macos/MemoPet.app}"
BIN="$APP/Contents/MacOS/memopet"
[[ -f "$BIN" ]] || { echo "binary not found: $BIN" >&2; exit 2; }
# The private keys wry uses: three it always set (patched out in vendor/wry) and
# the web inspector ones behind debug builds / the `devtools` feature.
KEYS='allowsPictureInPictureMediaPlayback|drawsBackground|fullScreenEnabled|proxyConfigurations|_setDrawsBackground|setDrawsBackground|developerExtrasEnabled|_inspector'
# Read the strings once; a failing `strings` must not look like a clean binary.
STRINGS="$(strings -a "$BIN")" || { echo "strings failed on $BIN" >&2; exit 2; }
if grep -E "$KEYS" <<<"$STRINGS"; then
  echo "FAIL: private API strings found in $BIN" >&2
  exit 1
fi
echo "PASS: no private WebKit KVC keys in $BIN"
# Not a call into Apple's private API: tao (Tauri's window library) overrides
# this NSView method in its own view class. Shown so it is not a surprise.
if grep -qx '_wantsKeyDownForEvent:' <<<"$STRINGS"; then
  echo "note: contains tao's override of _wantsKeyDownForEvent: (method name only)"
fi
