#!/bin/bash
# Runs every test: the IterKit package (swift test) and the app's hosted tests (xcodebuild test).
#   scripts/test.sh            all tests (snapshot rendering is skipped; use scripts/snapshots.sh)
#   ITER_LIVE=1 scripts/test.sh   also run the live MapKit/WeatherKit checks (network)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "== IterKit package (swift test)"
( cd Packages/IterKit && swift test 2>&1 | grep -E "Test run with|error:|failed|recorded an issue" )
echo "== App hosted tests (xcodebuild test)"
xcodegen generate --quiet
xcodebuild test -project Iter.xcodeproj -scheme Iter -destination 'platform=macOS' -derivedDataPath build/DerivedData 2>&1 \
  | grep -E "error:|Test run with|failed|passed after|TEST (SUCCEEDED|FAILED)" | tail -20
