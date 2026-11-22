#!/bin/bash
# Runs the Mac-side checks: the Packages/Iter and IterUpdater packages (swift test), then builds the Mac app.
#   scripts/test.sh
# The hosted Mac tests (IterAppTests) are built by the scheme but NOT run in this phase: running them launches the
# app. Hosted snapshot tests return in a later phase, on the render copy. iOS: scripts/test-ios.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "== Packages/Iter (swift test)"
( cd Packages/Iter && swift test 2>&1 | grep -E "Test run with|error:|failed|recorded an issue" )
echo "== IterUpdater package (swift test)"
( cd Packages/IterUpdater && swift test 2>&1 | grep -E "Test run with|error:|failed|recorded an issue" )
echo "== Mac app (xcodebuild build)"
xcodegen generate --quiet
xcodebuild build -project Iter.xcodeproj -scheme Iter -destination 'platform=macOS' -derivedDataPath "${ITER_DD:-build/DerivedData-rebuild-mac}" \
  2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -20
