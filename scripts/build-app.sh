#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="${1:-release}"

if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
  echo "Usage: $0 [release|debug]" >&2
  exit 64
fi

BUILD_ARGUMENTS=(--package-path "$PROJECT_ROOT" -c "$CONFIGURATION")
if [[ "$CONFIGURATION" == "release" ]]; then
  BUILD_ARGUMENTS+=(--arch arm64 --arch x86_64)
fi

swift build "${BUILD_ARGUMENTS[@]}"
BIN_DIRECTORY="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"

APP_PATH="$PROJECT_ROOT/dist/MemoPet.app"
CONTENTS_PATH="$APP_PATH/Contents"
ICON_SOURCE_PATH="$PROJECT_ROOT/Support/AppIcon.png"

if [[ -e "$APP_PATH" ]]; then
  rm -rf "$APP_PATH"
fi

mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"
install -m 755 "$BIN_DIRECTORY/MemoPet" "$CONTENTS_PATH/MacOS/MemoPet"
install -m 644 "$PROJECT_ROOT/Support/Info.plist" "$CONTENTS_PATH/Info.plist"
ditto "$PROJECT_ROOT/Sources/MemoPet/Resources" "$CONTENTS_PATH/Resources"

ICON_WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/memopet-icon.XXXXXX")"
trap 'rm -rf "$ICON_WORK_DIRECTORY"' EXIT
ICONSET_PATH="$ICON_WORK_DIRECTORY/AppIcon.iconset"
mkdir -p "$ICONSET_PATH"

ICON_SPECS=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)
for spec in "${ICON_SPECS[@]}"; do
  size="${spec%%:*}"
  filename="${spec#*:}"
  sips \
    -z "$size" "$size" \
    "$ICON_SOURCE_PATH" \
    --out "$ICONSET_PATH/$filename" \
    >/dev/null
done
iconutil \
  -c icns \
  "$ICONSET_PATH" \
  -o "$CONTENTS_PATH/Resources/AppIcon.icns"

plutil -lint "$CONTENTS_PATH/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP_PATH" >/dev/null

echo "Built $APP_PATH"
