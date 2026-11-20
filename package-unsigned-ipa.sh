#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
command -v xcodegen >/dev/null 2>&1 || { echo "Install XcodeGen: brew install xcodegen" >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "This script requires macOS and Xcode." >&2; exit 1; }

xcodegen generate
DERIVED="$ROOT/build/DerivedData"
xcodebuild -project ApplePickupTracker.xcodeproj \
  -scheme ApplePickupTracker \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED/Build/Products/Release-iphoneos/Pickup Tracker.app"
[ -d "$APP" ] || { echo "Build succeeded but app product was not found: $APP" >&2; exit 1; }
PAYLOAD="$ROOT/build/Payload"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
cp -R "$APP" "$PAYLOAD/"
rm -f "$ROOT/build/ApplePickupTracker-unsigned.ipa"
(cd "$ROOT/build" && /usr/bin/zip -qr ApplePickupTracker-unsigned.ipa Payload)
echo "Created: $ROOT/build/ApplePickupTracker-unsigned.ipa"
echo "Import this unsigned IPA into AltStore/Sideloadly and sign it with your Apple Personal Team."
