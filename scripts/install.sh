#!/usr/bin/env bash
# Builds a signed Release copy of Cofre and installs it in /Applications.
#
# Needs Config/Local.xcconfig with your DEVELOPMENT_TEAM (see Config/Local.xcconfig.example).
# With a free Personal Team the provisioning profile lasts 7 days: when Cofre stops opening,
# run this again. Your secrets stay in the Keychain across reinstalls (same team + bundle ID).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f Config/Local.xcconfig ]]; then
  echo "Config/Local.xcconfig is missing: copy Config/Local.xcconfig.example and set DEVELOPMENT_TEAM." >&2
  exit 1
fi

DERIVED=build/InstallDerivedData
APP="$DERIVED/Build/Products/Release/Cofre.app"
DEST=/Applications/Cofre.app

echo "▸ Building a signed Release copy…"
xcodebuild \
  -project Cofre.xcodeproj \
  -scheme Cofre \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -quiet \
  build

echo "▸ Checking the signature…"
codesign --verify --strict "$APP"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "keychain-access-groups" || {
  echo "The build has no keychain group entitlement; it won't be able to use the Keychain." >&2
  exit 1
}

if pgrep -xq Cofre; then
  echo "▸ Quitting the running Cofre…"
  osascript -e 'quit app "Cofre"' || true
  sleep 1
fi

echo "▸ Installing to ${DEST}…"
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "✔ Installed. Open it from Applications or Spotlight (⌘Space, \"Cofre\")."
