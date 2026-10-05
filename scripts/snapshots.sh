#!/bin/bash
# Renders every screen and state to Design/snapshots (light and dark, two window sizes). No window is shown.
#   scripts/snapshots.sh [test-name-filter]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodegen generate --quiet
RUN="run-$$-$(date +%s)"
CONTAINER_TMP="$HOME/Library/Containers/com.dwjames.iter/Data/tmp/IterSnapshots/$RUN"
rm -rf "$CONTAINER_TMP"
ONLY=()
if [ -n "${1:-}" ]; then ONLY=(-only-testing:"IterAppTests/$1"); fi
TEST_RUNNER_ITER_SNAPSHOT_CACHE=${ITER_SNAPSHOT_CACHE:-0} TEST_RUNNER_ITER_SNAPSHOT_RUN=$RUN TEST_RUNNER_ITER_SNAPSHOTS=1 xcodebuild test -project Iter.xcodeproj -scheme Iter -destination 'platform=macOS' \
  -derivedDataPath "${ITER_DD:-build/DerivedData}" ${ONLY[@]+"${ONLY[@]}"} -quiet 2>&1 | grep -E "error:|failed|passed|Test run" || true
mkdir -p Design/snapshots
cp "$CONTAINER_TMP"/*.png Design/snapshots/ 2>/dev/null || true
rm -rf "$CONTAINER_TMP"
ls Design/snapshots | wc -l | xargs echo "snapshots in Design/snapshots:"
