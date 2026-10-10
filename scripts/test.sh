#!/bin/bash
# Runs every test: the IterKit and IterUpdater packages (swift test) and the app's hosted tests (xcodebuild test).
#   scripts/test.sh            all tests (snapshot rendering is skipped; use scripts/snapshots.sh)
#   ITER_LIVE=1 scripts/test.sh   also run the live MapKit/WeatherKit checks (network)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "== IterKit package (swift test)"
( cd Packages/IterKit && swift test 2>&1 | grep -E "Test run with|error:|failed|recorded an issue" )
echo "== IterUpdater package (swift test)"
( cd Packages/IterUpdater && swift test 2>&1 | grep -E "Test run with|error:|failed|recorded an issue" )
echo "== App hosted tests (xcodebuild test)"
xcodegen generate --quiet
VERSION_ARGS=($("$ROOT/scripts/version.sh"))   # build number and git hash (scripts/version.sh)
# The hosted app is the render copy (com.dwjames.iter.render, ad hoc), never the real bundle id; see scripts/render.sh.
RENDER=(ITER_BUNDLE_ID=com.dwjames.iter.render CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO)
xcodebuild build-for-testing -project Iter.xcodeproj -scheme Iter -destination 'platform=macOS' -derivedDataPath "${ITER_DD:-build/DD-render-tests}" \
  "${RENDER[@]}" "${VERSION_ARGS[@]}" -quiet 2>&1 | { grep -E "error:" | grep -v "failed with exit code 0" || true; }
HOST_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${ITER_DD:-build/DD-render-tests}/Build/Products/Debug/Iter.app/Contents/Info.plist" 2>/dev/null || true)"
[ "$HOST_ID" = "com.dwjames.iter.render" ] || { echo "Refusing to run the hosted tests: host bundle id is '$HOST_ID'" >&2; exit 1; }
xcodebuild test-without-building -project Iter.xcodeproj -scheme Iter -destination 'platform=macOS' -derivedDataPath "${ITER_DD:-build/DD-render-tests}" \
  "${RENDER[@]}" 2>&1 \
  | grep -E "error:|Test run with|failed|passed after|TEST (SUCCEEDED|FAILED)" | tail -20
