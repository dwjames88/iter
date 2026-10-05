#!/bin/bash
# Renders every screen and state to Design/snapshots (light and dark, two window sizes). No window is shown:
# the hosted test target draws SwiftUI into offscreen bitmaps (see AppTests/Support/Snapshot.swift).
#   scripts/snapshots.sh [test-suite-name]
# Environment: ITER_DD = derived data path (default build/DerivedData).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodegen generate --quiet
RUN="run-$$-$(date +%s)"
CONTAINER_TMP="$HOME/Library/Containers/com.dwjames.iter/Data/tmp/IterSnapshots/$RUN"
rm -rf "$CONTAINER_TMP"
ONLY=()
if [ -n "${1:-}" ]; then ONLY=(-only-testing:"IterAppTests/$1"); fi
TEST_RUNNER_ITER_SNAPSHOT_RUN=$RUN TEST_RUNNER_ITER_SNAPSHOTS=1 xcodebuild test -project Iter.xcodeproj -scheme Iter -destination 'platform=macOS' \
  -derivedDataPath "${ITER_DD:-build/DerivedData}" ${ONLY[@]+"${ONLY[@]}"} -quiet 2>&1 | grep -E "error:|failed|passed|Test run" || true
mkdir -p Design/snapshots
written=()
for f in "$CONTAINER_TMP"/*.png; do
  [ -e "$f" ] || continue
  cp "$f" Design/snapshots/
  written+=("Design/snapshots/$(basename "$f")")
done
rm -rf "$CONTAINER_TMP"
echo "wrote ${#written[@]} snapshots:"
[ ${#written[@]} -gt 0 ] && printf '  %s\n' "${written[@]}"
echo "snapshots in Design/snapshots: $(ls Design/snapshots | wc -l | xargs echo)"
