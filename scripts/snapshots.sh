#!/bin/bash
# Renders every screen and state to Design/snapshots (light and dark, two window sizes). No window is shown:
# the hosted test target draws SwiftUI into offscreen bitmaps (see AppTests/Support/Snapshot.swift).
#   scripts/snapshots.sh [test-suite-name]
# The hosted app is built as com.dwjames.iter.render (ad hoc, no team, no hardened runtime) so it never launches as the real
# app and never touches its Keychain or store; the script checks the built Info.plist before running anything.
# Environment: ITER_DD = derived data path (default build/DD-render-tests).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodegen generate --quiet
RUN="run-$$-$(date +%s)"
OUT="$ROOT/build/snapshots-$RUN"
rm -rf "$OUT"
ONLY=()
if [ -n "${1:-}" ]; then ONLY=(-only-testing:"IterAppTests/$1"); fi
DD="${ITER_DD:-build/DD-render-tests}"
OVERRIDES=(ITER_BUNDLE_ID=com.dwjames.iter.render CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO)
# Build first and refuse to run unless the host app really carries the render bundle id.
xcodebuild build-for-testing -project Iter.xcodeproj -scheme Iter -destination 'platform=macOS' -derivedDataPath "$DD" \
  "${OVERRIDES[@]}" -quiet 2>&1 | { grep -E "error:" | grep -v "failed with exit code 0" || true; }
HOST_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DD/Build/Products/Debug/Iter.app/Contents/Info.plist" 2>/dev/null || true)"
if [ "$HOST_ID" != "com.dwjames.iter.render" ]; then echo "Refusing to run the hosted tests: host bundle id is '$HOST_ID', not com.dwjames.iter.render" >&2; exit 1; fi
TEST_RUNNER_ITER_SNAPSHOT_RUN=$RUN TEST_RUNNER_ITER_SNAPSHOT_DIR="$OUT" TEST_RUNNER_ITER_SNAPSHOTS=1 xcodebuild test-without-building -project Iter.xcodeproj -scheme Iter -destination 'platform=macOS' \
  -derivedDataPath "$DD" "${OVERRIDES[@]}" ${ONLY[@]+"${ONLY[@]}"} -quiet 2>&1 | grep -E "error:|failed|passed|Test run" || true
mkdir -p Design/snapshots
written=()
for f in "$OUT"/*.png; do
  [ -e "$f" ] || continue
  cp "$f" Design/snapshots/
  written+=("Design/snapshots/$(basename "$f")")
done
rm -rf "$OUT"
echo "wrote ${#written[@]} snapshots:"
[ ${#written[@]} -gt 0 ] && printf '  %s\n' "${written[@]}"
echo "snapshots in Design/snapshots: $(ls Design/snapshots | wc -l | xargs echo)"
