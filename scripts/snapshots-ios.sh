#!/bin/bash
# Renders the iOS onboarding screens (iPhone 17 Pro, light and dark) offscreen on a headless Simulator and copies the
# PNGs to Design/snapshots/ios-onboarding-*.png. Never touches the Mac app.
#   scripts/snapshots-ios.sh [simulator name]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DEVICE="${1:-iPhone 17 Pro}"
UDID=$(xcrun simctl list devices available | grep -F "    $DEVICE (" | tail -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "No simulator named \"$DEVICE\""; exit 1; }
OUT="$ROOT/build/snapshots-ios-$$"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodegen generate --quiet
TEST_RUNNER_ITER_SNAPSHOTS=1 TEST_RUNNER_ITER_SNAPSHOT_DIR="$OUT" xcodebuild test -project Iter.xcodeproj -scheme "Iter iOS" \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "${ITER_IOS_DERIVED:-$ROOT/build/DerivedData-iOS}" \
  -only-testing:IterAppTests\ iOS/OnboardingIOSSnapshotTests 2>&1 | grep -E "error:|Test run with|failed|TEST (SUCCEEDED|FAILED)" || true
mkdir -p Design/snapshots
cp "$OUT"/*.png Design/snapshots/
ls "$OUT" | sed 's|^|Design/snapshots/|'
rm -rf "$OUT"
