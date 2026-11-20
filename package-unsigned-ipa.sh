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

APP="$DERIVED/Build/Products/Release-iphoneos/ApplePickupTracker.app"
[ -d "$APP" ] || { echo "Build succeeded but app product was not found: $APP" >&2; exit 1; }
[ -f "$APP/Info.plist" ] || { echo "Missing app Info.plist" >&2; exit 1; }
[ -f "$APP/ApplePickupTracker" ] || { echo "Missing app executable" >&2; exit 1; }

PAYLOAD="$ROOT/build/Payload"
rm -rf "$PAYLOAD" "$ROOT/build/ApplePickupTracker-unsigned.ipa"
mkdir -p "$PAYLOAD"
cp -R "$APP" "$PAYLOAD/"

# Use Apple's macOS archive utility to create a conventional IPA (ZIP with Payload at root).
(cd "$ROOT/build" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent Payload ApplePickupTracker-unsigned.ipa)

# Validate the archive and its required bundle layout before publishing the artifact.
unzip -t "$ROOT/build/ApplePickupTracker-unsigned.ipa"
unzip -Z1 "$ROOT/build/ApplePickupTracker-unsigned.ipa" | grep -q '^Payload/ApplePickupTracker.app/Info.plist$'
unzip -Z1 "$ROOT/build/ApplePickupTracker-unsigned.ipa" | grep -q '^Payload/ApplePickupTracker.app/ApplePickupTracker$'
echo "Created and validated: $ROOT/build/ApplePickupTracker-unsigned.ipa"
