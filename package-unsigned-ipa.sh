#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
command -v xcodegen >/dev/null 2>&1 || { echo "Install XcodeGen: brew install xcodegen" >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "This script requires macOS and Xcode." >&2; exit 1; }

xcodegen generate
DERIVED="$ROOT/build/DerivedData"
mkdir -p "$ROOT/build"
LOG="$ROOT/build/xcodebuild.log"
xcodebuild -project ApplePickupTracker.xcodeproj \
  -scheme ApplePickupTracker \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "$LOG"

APP="$DERIVED/Build/Products/Release-iphoneos/ApplePickupTracker.app"
[ -d "$APP" ] || { echo "Build succeeded but app product was not found: $APP" >&2; exit 1; }
[ -f "$APP/Info.plist" ] || { echo "Missing app Info.plist" >&2; exit 1; }
[ -f "$APP/ApplePickupTracker" ] || { echo "Missing app executable" >&2; exit 1; }

echo "---- Built Info.plist (launch screen, orientations, icon) ----"
/usr/libexec/PlistBuddy -c 'Print' "$APP/Info.plist" || true

launch_name="$(/usr/libexec/PlistBuddy -c 'Print :UILaunchStoryboardName' "$APP/Info.plist" 2>/dev/null || true)"
if [ "$launch_name" != "LaunchScreen" ]; then
  echo "Built Info.plist UILaunchStoryboardName is '${launch_name}', expected LaunchScreen." >&2
  exit 1
fi
if ! /usr/libexec/PlistBuddy -c 'Print :UILaunchScreen:UIImageRespectsSafeAreaInsets' "$APP/Info.plist" >/dev/null 2>&1; then
  echo "Built Info.plist is missing a non-empty UILaunchScreen dictionary." >&2
  exit 1
fi
schemes="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' "$APP/Info.plist" 2>/dev/null || true)"
if ! printf '%s\n' "$schemes" | grep -q 'msauth.com.example.ApplePickupTracker'; then
  echo "Built Info.plist lost the Outlook URL scheme." >&2
  exit 1
fi
if ! /usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes' "$APP/Info.plist" 2>/dev/null | grep -q fetch; then
  echo "Built Info.plist is missing UIBackgroundModes fetch." >&2
  exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null || true)"
if [ -z "$version" ] || [ "$version" = "null" ]; then
  echo "Built Info.plist CFBundleVersion is empty." >&2
  exit 1
fi
for key in UISupportedInterfaceOrientations "UISupportedInterfaceOrientations~iphone" "UISupportedInterfaceOrientations~ipad"; do
  orientations="$(/usr/libexec/PlistBuddy -c "Print :${key}" "$APP/Info.plist")"
  for orientation in \
    UIInterfaceOrientationPortrait \
    UIInterfaceOrientationPortraitUpsideDown \
    UIInterfaceOrientationLandscapeLeft \
    UIInterfaceOrientationLandscapeRight
  do
    if ! printf '%s\n' "$orientations" | grep -q "$orientation"; then
      echo "Built Info.plist ${key} is missing ${orientation}." >&2
      exit 1
    fi
  done
done
if [ ! -d "$APP/LaunchScreen.storyboardc" ] && [ ! -d "$APP/Base.lproj/LaunchScreen.storyboardc" ]; then
  echo "Compiled LaunchScreen.storyboardc is missing from the app bundle." >&2
  find "$APP" -name 'LaunchScreen*' -o -name '*.storyboardc' >&2 || true
  exit 1
fi
if [ ! -s "$APP/Assets.car" ]; then
  echo "Assets.car is missing; the app icon was not compiled." >&2
  exit 1
fi
if ! /usr/libexec/PlistBuddy -c 'Print :CFBundleIcons' "$APP/Info.plist" 2>/dev/null | grep -q 'AppIcon' \
  && ! /usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP/Info.plist" 2>/dev/null | grep -q 'AppIcon'; then
  echo "Built Info.plist does not name the AppIcon asset." >&2
  exit 1
fi
if command -v assetutil >/dev/null 2>&1; then
  if ! assetutil --info "$APP/Assets.car" | grep -q 'AppIcon'; then
    echo "Assets.car does not contain AppIcon." >&2
    assetutil --info "$APP/Assets.car" >&2 || true
    exit 1
  fi
fi

if grep -E 'A launch configuration or launch storyboard|All interface orientations must be supported' "$LOG"; then
  echo "App is still missing a native launch screen or full interface orientations; iOS would scale it." >&2
  exit 1
fi

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
unzip -Z1 "$ROOT/build/ApplePickupTracker-unsigned.ipa" | grep -q 'Payload/ApplePickupTracker.app/LaunchScreen.storyboardc'
unzip -Z1 "$ROOT/build/ApplePickupTracker-unsigned.ipa" | grep -q 'Payload/ApplePickupTracker.app/Assets.car'
echo "Created and validated: $ROOT/build/ApplePickupTracker-unsigned.ipa"
