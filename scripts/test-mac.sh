#!/bin/bash
# Runs the hosted Mac tests (IterAppTests) headless, as the render copy, and prints a real pass/fail tally.
#   scripts/test-mac.sh [--only <TestClass>] [--timeout SECONDS] [--no-build]
# Route (works; see TESTING.md): `xcodebuild build-for-testing` then `xcodebuild test-without-building`, scheme Iter, whose test
# action uses the Test configuration (bundle id com.dwjames.iter.render, ad hoc, no hardened runtime) and launches the host
# with -IterInMemoryStore YES -IterLocation 38.39,-109.87. Parallel testing is off (one host app), timeouts are on.
# Safe by construction: it never activates the app (the host is built with activation policy .prohibited under XCTest),
# refuses to run unless the built bundle id is com.dwjames.iter.render, kills only the PIDs it started, and has an overall
# timeout. Snapshots are written to Design/snapshots/rebuild/mac/<name>-<light|dark>.png.
# Environment: ITER_DD = derived data path (default build/DD-test-mac).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RENDER_ID="com.dwjames.iter.render"
ONLY=""; LIMIT=900; BUILD=1
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:?--only needs a test class}"; shift ;;
    --timeout) LIMIT="${2:?--timeout needs seconds}"; shift ;;
    --no-build) BUILD=0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
DD="${ITER_DD:-build/DD-test-mac}"
OUTDIR="$ROOT/build/snapshots-mac-$$"
LOG="$ROOT/build/test-mac-$$.log"
mkdir -p "$ROOT/build"; rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"
START=$(date +%s)
CHILD=""
cleanup() { [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null; return 0; }
trap cleanup EXIT INT TERM
command -v xcodegen >/dev/null || { echo "XcodeGen is needed (brew install xcodegen)" >&2; exit 1; }
xcodegen generate --quiet
# Runs a command with an overall deadline, killing only its own process (and the test host it spawned, by recorded PID).
run_limited() { # seconds logfile cmd...
  local secs="$1" out="$2"; shift 2
  "$@" >"$out" 2>&1 &
  CHILD=$!
  local waited=0
  while kill -0 "$CHILD" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      echo "TIMEOUT after ${secs}s: stopping pid $CHILD" >&2
      pkill -P "$CHILD" 2>/dev/null; kill "$CHILD" 2>/dev/null; wait "$CHILD" 2>/dev/null; CHILD=""; return 124
    fi
    sleep 1; waited=$((waited + 1))
  done
  wait "$CHILD"; local rc=$?; CHILD=""; return $rc
}
COMMON=(-project Iter.xcodeproj -scheme Iter -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD")
if [ "$BUILD" = 1 ]; then
  run_limited "$LIMIT" "$LOG.build" xcodebuild build-for-testing "${COMMON[@]}" $("$ROOT/scripts/version.sh") -quiet
  RC=$?
  if [ $RC -ne 0 ]; then grep -E "error:" "$LOG.build" | head -20; echo "Build failed (exit $RC), log: $LOG.build" >&2; exit 1; fi
fi
HOST_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DD/Build/Products/Test/Iter.app/Contents/Info.plist" 2>/dev/null || true)"
if [ "$HOST_ID" != "$RENDER_ID" ]; then echo "Refusing to run the hosted tests: host bundle id is '$HOST_ID', not $RENDER_ID" >&2; exit 1; fi
FILTER=(); [ -n "$ONLY" ] && FILTER=(-only-testing:"IterAppTests/$ONLY")
TEST_RUNNER_ITER_SNAPSHOT_DIR="$OUTDIR" run_limited "$LIMIT" "$LOG" \
  xcodebuild test-without-building "${COMMON[@]}" -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300 ${FILTER[@]+"${FILTER[@]}"}
RC=$?
# Tally from the Swift Testing lines (and XCTest summaries, if any exist).
PASSED=$(grep -E " Test .* passed after" "$LOG" | grep -vc "Test run with"); FAILED=$(grep -E " Test .* failed after" "$LOG" | grep -vc "Test run with")
XC=$(grep -E "Executed [0-9]+ tests?, with" "$LOG" | tail -1)
grep -E "error:|failed after|recorded an issue" "$LOG" | grep -v "autoShortcut\|Process Instance Registry" | head -30
mkdir -p Design/snapshots/rebuild/mac
N=0
for f in "$OUTDIR"/*.png; do [ -e "$f" ] || continue; cp "$f" Design/snapshots/rebuild/mac/; N=$((N + 1)); done
rm -rf "$OUTDIR"
echo "swift-testing: $PASSED passed, $FAILED failed${XC:+; xctest: $XC}; snapshots written: $N (Design/snapshots/rebuild/mac)"
echo "xcodebuild exit $RC in $(( $(date +%s) - START ))s, log $LOG"
[ $RC -eq 0 ] && [ "$FAILED" -eq 0 ] && [ "$PASSED" -gt 0 ] && { echo "PASS"; exit 0; }
echo "FAIL"; exit 1
