#!/usr/bin/env bash
# Builds and (optionally) uploads the Mac App Store package.
#
# Needs values from the Apple Developer account (see docs/RELEASE.md):
#   TEAM_ID                   10-character team ID, e.g. ABCDE12345
#   APP_SIGN_IDENTITY         "Apple Distribution: <Name> (<TEAM_ID>)"
#   INSTALLER_SIGN_IDENTITY   "3rd Party Mac Developer Installer: <Name> (<TEAM_ID>)"
#   PROVISIONING_PROFILE      path to the "Mac App Store Connect" provisioning profile
#   BUILD_NUMBER              CFBundleVersion: 1 for the first upload, then 2, 3 …
#                             Every upload needs a higher number than any earlier
#                             one, also when the app version changes (macOS rule).
# Optional:
#   APPLE_API_KEY_ID, APPLE_API_ISSUER   upload with an App Store Connect API key
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"

: "${TEAM_ID:?set TEAM_ID}"
: "${APP_SIGN_IDENTITY:?set APP_SIGN_IDENTITY}"
: "${INSTALLER_SIGN_IDENTITY:?set INSTALLER_SIGN_IDENTITY}"
: "${PROVISIONING_PROFILE:?set PROVISIONING_PROFILE}"
: "${BUILD_NUMBER:?set BUILD_NUMBER (1 for the first upload, then higher every time)}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "BUILD_NUMBER must be a whole number" >&2; exit 2; }

rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
sed "s/__TEAM_ID__/${TEAM_ID}/g" src-tauri/Entitlements.appstore.plist.template > src-tauri/Entitlements.appstore.plist
cp "$PROVISIONING_PROFILE" src-tauri/embedded.provisionprofile
cat > src-tauri/tauri.appstore.conf.json <<JSON
{
  "bundle": {
    "macOS": {
      "entitlements": "./Entitlements.appstore.plist",
      "signingIdentity": "${APP_SIGN_IDENTITY}",
      "bundleVersion": "${BUILD_NUMBER}",
      "files": { "embedded.provisionprofile": "./embedded.provisionprofile" }
    }
  }
}
JSON

npm ci
npm run tauri -- build --bundles app --target universal-apple-darwin --config src-tauri/tauri.appstore.conf.json

APP="src-tauri/target/universal-apple-darwin/release/bundle/macos/MemoBuddy.app"
codesign --verify --deep --strict "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "com.apple.security.app-sandbox"
# The submitted binary itself: no private WebKit keys, and the license notices inside.
./scripts/check-private-api.sh "$APP"
test -s "$APP/Contents/Resources/THIRD_PARTY_LICENSES.md"

mkdir -p dist-mas
xcrun productbuild --sign "$INSTALLER_SIGN_IDENTITY" --component "$APP" /Applications dist-mas/MemoBuddy.pkg
echo "Built dist-mas/MemoBuddy.pkg"

if [[ -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER:-}" ]]; then
  xcrun altool --upload-app --type macos --file dist-mas/MemoBuddy.pkg --apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER"
fi
