#!/bin/bash
# Builds the iPhone and iPad app and runs its tests on a Simulator, headless (no Simulator.app window).
# Pinned to the iOS 27.2 runtime BY NAME (never "newest": the iOS 27.0 beta runtime crash-loops PosterBoard).
#   scripts/test-ios.sh                         the "Iter Rebuild" device on iOS 27.2 (created, not booted, if missing)
#   ITER_IOS_DEVICE="My Sim" scripts/test-ios.sh
#   ITER_IOS_UDID=<udid> scripts/test-ios.sh    a specific simulator (still refused if it is on iOS 27.0)
#   ITER_IOS_RUNTIME="iOS 26.5" scripts/test-ios.sh   documented fallback if 27.2 misbehaves
#   scripts/test-ios.sh --print-device          print the chosen runtime, name and udid, then stop
# Also runs the Packages/Iter tests (swift test). It never runs or quits the Mac app and never opens Simulator.app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
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

echo "== Packages/Iter (swift test)"
( cd Packages/Iter && swift test 2>&1 | grep -E "Test run with|error:|recorded an issue" )
echo "== iOS app (xcodebuild test on $DEVICE, $RUNTIME_NAME, $ITER_IOS_UDID)"
xcodegen generate --quiet
xcodebuild test -project Iter.xcodeproj -scheme "Iter iOS" -destination "platform=iOS Simulator,id=$ITER_IOS_UDID" \
  -derivedDataPath "$DERIVED" 2>&1 | grep -E "error:|Test run with|failed|passed after|TEST (SUCCEEDED|FAILED)" | tail -20
