#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_ROOT/dist/MemoPet.app"
ARCHIVE_PATH="$PROJECT_ROOT/dist/MemoPet.zip"

"$SCRIPT_DIR/build-app.sh" release

if [[ -e "$ARCHIVE_PATH" ]]; then
  rm -f "$ARCHIVE_PATH"
fi

DITTONORSRC=1 ditto \
  -c \
  -k \
  --norsrc \
  --noextattr \
  --noqtn \
  --noacl \
  --keepParent \
  "$APP_PATH" \
  "$ARCHIVE_PATH"

unzip -t "$ARCHIVE_PATH" >/dev/null
if zipinfo -1 "$ARCHIVE_PATH" | grep -q '^__MACOSX/'; then
  echo "Archive unexpectedly contains __MACOSX metadata" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP_PATH"
echo "Packaged $ARCHIVE_PATH"
