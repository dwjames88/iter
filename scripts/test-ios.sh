#!/bin/bash
# Builds the iPhone and iPad app and runs its tests on a Simulator, headless (no Simulator.app window).
#   scripts/test-ios.sh                         iPhone 17 Pro on the newest installed iOS runtime
#   ITER_IOS_DEVICE="iPad Pro 11-inch (M5)" scripts/test-ios.sh
#   ITER_IOS_UDID=<udid> scripts/test-ios.sh    a specific simulator
# Also runs the IterKit package tests (swift test), which the iOS app shares. It never runs or quits the Mac app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED="${ITER_IOS_DERIVED:-$ROOT/build/DerivedData-iOS}"
DEVICE="${ITER_IOS_DEVICE:-iPhone 17 Pro}"

if [ -z "${ITER_IOS_UDID:-}" ]; then
  # The last matching device in `simctl list` is on the newest runtime.
  ITER_IOS_UDID=$(xcrun simctl list devices available | grep -F "    $DEVICE (" | tail -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
fi
[ -n "$ITER_IOS_UDID" ] || { echo "No simulator named \"$DEVICE\"; list them with: xcrun simctl list devices available"; exit 1; }

echo "== IterKit package (swift test)"
( cd Packages/IterKit && swift test 2>&1 | grep -E "Test run with|error:|recorded an issue" )
echo "== iOS app (xcodebuild test on $DEVICE, $ITER_IOS_UDID)"
xcodegen generate --quiet
xcodebuild test -project Iter.xcodeproj -scheme "Iter iOS" -destination "platform=iOS Simulator,id=$ITER_IOS_UDID" \
  -derivedDataPath "$DERIVED" 2>&1 | grep -E "error:|Test run with|failed|passed after|TEST (SUCCEEDED|FAILED)" | tail -20
