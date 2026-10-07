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
xcodebuild test -project Iter.xcodeproj -scheme Iter -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  "${VERSION_ARGS[@]}" 2>&1 \
  | grep -E "error:|Test run with|failed|passed after|TEST (SUCCEEDED|FAILED)" | tail -20
