#!/bin/bash
# The one-stop test runner. Runs, in order, each headless:
#   1. Packages/Iter        swift test
#   2. Packages/IterUpdater swift test
#   3. the hosted Mac tests  scripts/test-mac.sh   (render copy com.dwjames.iter.render, in-memory store)
#   4. the iOS tests         scripts/test-ios.sh   (iOS 27.2 Simulator, headless)
#   scripts/test.sh [--no-package] [--no-updater] [--no-mac] [--no-ios]
# Flags skip a stage. Every stage runs even if an earlier one failed; the exit code is non-zero if any failed.
# Environment: ITER_SCRATCH = SwiftPM scratch path for stages 1 and 2 (default: each package's .build).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PKG=1; UPD=1; MAC=1; IOS=1
for arg in "$@"; do
  case "$arg" in
    --no-package) PKG=0 ;;
    --no-updater) UPD=0 ;;
    --no-mac) MAC=0 ;;
    --no-ios) IOS=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
SCRATCH=(); [ -n "${ITER_SCRATCH:-}" ] && SCRATCH=(--scratch-path "$ITER_SCRATCH")
FAILED=()
swift_test() { # name dir
  echo "== $1 (swift test)"
  ( cd "$2" && swift test ${SCRATCH[@]+"${SCRATCH[@]}"} 2>&1 | grep -E "Test run with|error:|failed|recorded an issue"; exit "${PIPESTATUS[0]}" ) || FAILED+=("$1")
}
[ "$PKG" = 1 ] && swift_test "Packages/Iter" Packages/Iter
[ "$UPD" = 1 ] && swift_test "Packages/IterUpdater" Packages/IterUpdater
if [ "$MAC" = 1 ]; then echo "== Mac hosted tests"; "$ROOT/scripts/test-mac.sh" || FAILED+=("Mac hosted tests"); fi
if [ "$IOS" = 1 ]; then echo "== iOS tests"; ITER_IOS_SKIP_PACKAGE=1 "$ROOT/scripts/test-ios.sh" || FAILED+=("iOS tests"); fi
if [ "${#FAILED[@]}" -gt 0 ]; then echo "FAILED: ${FAILED[*]}"; exit 1; fi
echo "ALL PASSED"
