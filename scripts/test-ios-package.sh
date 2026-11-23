#!/bin/zsh
# Runs one Packages/Iter test target on an iOS Simulator, headless: `xcodebuild build-for-testing` for the package scheme,
# then `simctl spawn … xctest` on a simulator that is already booted (or booted here with simctl, never Simulator.app).
# `xcodebuild test` hung before reaching the runner on this Mac, so this route is used instead.
#   scripts/test-ios-package.sh IterScreensTests                 run the whole target
#   scripts/test-ios-package.sh IterScreensTests Some.XCTestCase   an XCTest filter (Swift Testing runs the whole target)
# Env: ITER_IOS_UDID (default: the "Iter Rebuild" device on iOS 27.2, refused if on iOS 27.0), ITER_IOS_PKG_DERIVED (derived
# data, default build/DerivedData-ios-package), and any ITER_* variable is passed into the test process
# (e.g. ITER_SNAPSHOT_RECORD=1). Uses Xcode.app (iOS 27.2 SDK) unless DEVELOPER_DIR is set.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:?usage: test-ios-package.sh <TestTarget> [filter]}"
FILTER="${2:-}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED="${ITER_IOS_PKG_DERIVED:-$ROOT/build/DerivedData-ios-package}"
UDID="${ITER_IOS_UDID:-$(ITER_IOS_RUNTIME="${ITER_IOS_RUNTIME:-iOS 27.2}" "$ROOT/scripts/test-ios.sh" --print-device | awk '/^udid:/{print $2}')}"
case "$(xcrun simctl list devices -j | python3 -c '
import json,sys
for rid, ds in json.load(sys.stdin)["devices"].items():
    if any(d["udid"]==sys.argv[1] for d in ds): print(rid)' "$UDID")" in
  *iOS-27-0*) echo "Refusing $UDID: iOS 27.0 runtime" >&2; exit 1 ;;
esac
STATE="$(xcrun simctl list devices | grep "$UDID" | sed -E 's/.*\((Booted|Shutdown|[A-Za-z ]+)\) *$/\1/')"
if [ "$STATE" != "Booted" ]; then xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" >/dev/null; fi

cd "$ROOT/Packages/Iter"
echo "== build-for-testing ($TARGET, $UDID)"
xcodebuild build-for-testing -scheme Iter-Package -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED" -quiet 2>&1 \
  | grep -E "error:" | grep -v "exit code 0 but produced no further output" | head -20 || true
BUNDLE="$DERIVED/Build/Products/Debug-iphonesimulator/$TARGET.xctest"
[ -d "$BUNDLE" ] || { echo "No test bundle at $BUNDLE (build failed?)" >&2; exit 1; }
P="$(xcrun --sdk iphonesimulator --show-sdk-platform-path)/Developer"
export SIMCTL_CHILD_DYLD_FRAMEWORK_PATH="$P/Library/Frameworks:$P/Library/PrivateFrameworks:$P/usr/lib:$DERIVED/Build/Products/Debug-iphonesimulator/PackageFrameworks:$DERIVED/Build/Products/Debug-iphonesimulator"
export SIMCTL_CHILD_DYLD_LIBRARY_PATH="$P/usr/lib"
for v in ${(k)parameters[(I)ITER_*]}; do export "SIMCTL_CHILD_$v=${(P)v}"; done
LOG="$DERIVED/$TARGET-$$.log"
echo "== xctest (log: $LOG)"
cd /tmp
if [ -n "$FILTER" ]; then
  timeout 900 xcrun simctl spawn "$UDID" "$P/Library/Xcode/Agents/xctest" -XCTest "$FILTER" "$BUNDLE" > "$LOG" 2>&1 || true
else
  timeout 900 xcrun simctl spawn "$UDID" "$P/Library/Xcode/Agents/xctest" "$BUNDLE" > "$LOG" 2>&1 || true
fi
grep -E "Test run with|^✘|recorded an issue|error:|Executed" "$LOG" | cut -c1-240 | tail -40
grep -qE "Test run with .* passed|Executed .* with 0 failures" "$LOG"
