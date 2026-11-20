#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Run this script on macOS with Xcode installed." >&2
  exit 1
fi

xcodegen generate
xcodebuild -project ApplePickupTracker.xcodeproj \
  -scheme ApplePickupTracker \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
