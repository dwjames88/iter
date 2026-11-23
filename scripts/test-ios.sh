#!/bin/bash
# Builds the iPhone and iPad app and runs its tests on a Simulator, headless (no Simulator.app window).
# Pinned to the iOS 27.2 runtime BY NAME (never "newest": the iOS 27.0 beta runtime crash-loops PosterBoard).
#   scripts/test-ios.sh                         the "Iter Rebuild" device on iOS 27.2 (created, not booted, if missing)
#   ITER_IOS_DEVICE="My Sim" scripts/test-ios.sh
#   ITER_IOS_UDID=<udid> scripts/test-ios.sh    a specific simulator (still refused if it is on iOS 27.0)
#   ITER_IOS_RUNTIME="iOS 26.5" scripts/test-ios.sh   documented fallback if 27.2 misbehaves
#   scripts/test-ios.sh --print-device          print the chosen runtime, name and udid, then stop
# Also runs the Packages/Iter tests (swift test). It never runs or quits the Mac app and never opens Simulator.app.
# The app-hosted bundle (IterAppTests iOS) is built with `xcodebuild build-for-testing` and run with `simctl spawn ... xctest`:
# `xcodebuild test` hangs before reaching the runner on this Mac. The bundle links Iter.debug.dylib (inside Iter.app) for
# `@testable import Iter`, so spawning xctest with that folder on DYLD_*_PATH is enough; the app is never installed or launched.
#   ITER_SNAPSHOT_RECORD=1 scripts/test-ios.sh       also writes Design/snapshots/rebuild/go/*-ios-*.png
#   ITER_IOS_SKIP_PACKAGE=1 scripts/test-ios.sh      only the app-hosted bundle
#   ITER_IOS_FILTER="GoPresentationTests" ...        an XCTest filter (Swift Testing always runs the whole bundle)
# Uses Xcode.app (the iOS 27.2 SDK) unless DEVELOPER_DIR is set; the default xcodebuild on this Mac is a beta with the 27.0 SDK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED="${ITER_IOS_DERIVED:-$ROOT/build/DerivedData-rebuild-ios}"
RUNTIME_NAME="${ITER_IOS_RUNTIME:-iOS 27.2}"
DEVICE="${ITER_IOS_DEVICE:-Iter Rebuild}"

RUNTIMES_JSON="$(xcrun simctl list runtimes -j)"
RUNTIME_ID="$(printf '%s' "$RUNTIMES_JSON" | python3 -c '
import json, sys
name = sys.argv[1]
for r in json.load(sys.stdin)["runtimes"]:
    if r.get("name") == name and r.get("isAvailable", True):
        print(r["identifier"]); break
' "$RUNTIME_NAME")"
[ -n "$RUNTIME_ID" ] || { echo "No available runtime named \"$RUNTIME_NAME\"; list them with: xcrun simctl list runtimes" >&2; exit 1; }

if [ -z "${ITER_IOS_UDID:-}" ]; then
  find_device() {
    xcrun simctl list devices -j | python3 -c '
import json, sys
rid, name = sys.argv[1], sys.argv[2]
for d in json.load(sys.stdin)["devices"].get(rid, []):
    if d["name"] == name and d.get("isAvailable", True):
        print(d["udid"]); break
' "$RUNTIME_ID" "$DEVICE"
  }
  ITER_IOS_UDID="$(find_device)"
  if [ -z "$ITER_IOS_UDID" ]; then
    # First device type the runtime supports (creating a device does not boot it).
    TYPE_ID="$(printf '%s' "$RUNTIMES_JSON" | python3 -c '
import json, sys
for r in json.load(sys.stdin)["runtimes"]:
    if r["identifier"] == sys.argv[1]:
        print(r["supportedDeviceTypes"][0]["identifier"]); break
' "$RUNTIME_ID")"
    [ -n "$TYPE_ID" ] || { echo "Runtime $RUNTIME_ID lists no supported device types" >&2; exit 1; }
    ITER_IOS_UDID="$(xcrun simctl create "$DEVICE" "$TYPE_ID" "$RUNTIME_ID")"
  fi
fi

# Refuse the iOS 27.0 runtime, whatever way the device was chosen.
DEVICE_RUNTIME="$(xcrun simctl list devices -j | python3 -c '
import json, sys
for rid, ds in json.load(sys.stdin)["devices"].items():
    if any(d["udid"] == sys.argv[1] for d in ds):
        print(rid); break
' "$ITER_IOS_UDID")"
[ -n "$DEVICE_RUNTIME" ] || { echo "No simulator with udid $ITER_IOS_UDID" >&2; exit 1; }
case "$DEVICE_RUNTIME" in
  *iOS-27-0*) echo "Refusing to use $ITER_IOS_UDID: it is on the iOS 27.0 runtime ($DEVICE_RUNTIME)" >&2; exit 1 ;;
esac

if [ "${1:-}" = "--print-device" ]; then
  echo "runtime: $RUNTIME_NAME ($DEVICE_RUNTIME)"
  echo "device:  $DEVICE"
  echo "udid:    $ITER_IOS_UDID"
  exit 0
fi

if [ -z "${ITER_IOS_SKIP_PACKAGE:-}" ]; then
  echo "== Packages/Iter (swift test)"
  ( cd Packages/Iter && swift test 2>&1 | grep -E "Test run with|error:|recorded an issue" )
fi

STATE="$(xcrun simctl list devices | grep "$ITER_IOS_UDID" | sed -E 's/.*\((Booted|Shutdown|[A-Za-z ]+)\) *$/\1/')"
if [ "$STATE" != "Booted" ]; then xcrun simctl boot "$ITER_IOS_UDID"; xcrun simctl bootstatus "$ITER_IOS_UDID" >/dev/null; fi

echo "== iOS app (build-for-testing on $DEVICE, $RUNTIME_NAME, $ITER_IOS_UDID)"
xcodegen generate --quiet
xcodebuild build-for-testing -project Iter.xcodeproj -scheme "Iter iOS" -destination "platform=iOS Simulator,id=$ITER_IOS_UDID" \
  -derivedDataPath "$DERIVED" 2>&1 | grep -E "error:|TEST BUILD (SUCCEEDED|FAILED)" | sort -u | head -30
PRODUCTS="$DERIVED/Build/Products/Debug-iphonesimulator"
APP="$PRODUCTS/Iter.app"
BUNDLE="$APP/PlugIns/IterAppTests iOS.xctest"
[ -d "$BUNDLE" ] || { echo "No test bundle at $BUNDLE (build failed?)" >&2; exit 1; }

P="$(xcrun --sdk iphonesimulator --show-sdk-platform-path)/Developer"
export SIMCTL_CHILD_DYLD_FRAMEWORK_PATH="$P/Library/Frameworks:$P/Library/PrivateFrameworks:$APP:$PRODUCTS/PackageFrameworks:$PRODUCTS"
export SIMCTL_CHILD_DYLD_LIBRARY_PATH="$P/usr/lib:$APP"
export SIMCTL_CHILD_ITER_REPO_ROOT="$ROOT"
while IFS='=' read -r name value; do
  case "$name" in ITER_SNAPSHOT_*|ITER_TEST_*) export "SIMCTL_CHILD_$name=$value" ;; esac
done < <(env)
LOG="$DERIVED/IterAppTests-$$.log"
echo "== xctest (log: $LOG)"
cd /tmp
if [ -n "${ITER_IOS_FILTER:-}" ]; then
  timeout 900 xcrun simctl spawn "$ITER_IOS_UDID" "$P/Library/Xcode/Agents/xctest" -XCTest "$ITER_IOS_FILTER" "$BUNDLE" > "$LOG" 2>&1 || true
else
  timeout 900 xcrun simctl spawn "$ITER_IOS_UDID" "$P/Library/Xcode/Agents/xctest" "$BUNDLE" > "$LOG" 2>&1 || true
fi
grep -E "Test run with|^✘|recorded an issue|error:|Executed" "$LOG" | cut -c1-240 | tail -40
grep -qE "Test run with .* passed|Executed .* with 0 failures" "$LOG"
