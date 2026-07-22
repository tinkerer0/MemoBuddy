#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="${1:-release}"

if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
  echo "Usage: $0 [release|debug]" >&2
  exit 64
fi

swift build --package-path "$PROJECT_ROOT" -c "$CONFIGURATION"
BIN_DIRECTORY="$(swift build --package-path "$PROJECT_ROOT" -c "$CONFIGURATION" --show-bin-path)"

APP_PATH="$PROJECT_ROOT/dist/MemoPet.app"
CONTENTS_PATH="$APP_PATH/Contents"

if [[ -e "$APP_PATH" ]]; then
  rm -rf "$APP_PATH"
fi

mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"
install -m 755 "$BIN_DIRECTORY/MemoPet" "$CONTENTS_PATH/MacOS/MemoPet"
install -m 644 "$PROJECT_ROOT/Support/Info.plist" "$CONTENTS_PATH/Info.plist"
install -m 644 \
  "$PROJECT_ROOT/Sources/MemoPet/Resources/default-character.gif" \
  "$CONTENTS_PATH/Resources/default-character.gif"

plutil -lint "$CONTENTS_PATH/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP_PATH" >/dev/null

echo "Built $APP_PATH"
