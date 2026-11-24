#!/bin/bash
# Builds the Mac app (Debug, signed with your Apple Development certificate) into build/Iter.app. It only opens it with --real.
#   scripts/run.sh          build only
#   scripts/run.sh --real   build, then open build/Iter.app
#
# WARNING: build/Iter.app is the REAL app (bundle id com.dwjames.iter) on the REAL store in ~/Library/Application Support/Iter.
# The first launch of a build with the V5 schema migrates that store to V5; there is no way back except a backup. The owner
# decides when to launch it, which is why a plain run never opens it. For anything automated use scripts/render.sh (the render
# copy, in-memory store) or scripts/test-mac.sh.
# Environment: ITER_DD = derived data path (default build/DerivedData).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OPEN=0
for arg in "$@"; do
  case "$arg" in
    --real) OPEN=1 ;;
    *) echo "unknown option: $arg (the only option is --real)" >&2; exit 2 ;;
  esac
done
command -v xcodegen >/dev/null || { echo "XcodeGen is needed (brew install xcodegen)" >&2; exit 1; }
xcodegen generate --quiet
VERSION_ARGS=($("$ROOT/scripts/version.sh"))   # build number and git hash (scripts/version.sh)
DD="${ITER_DD:-build/DerivedData}"
set +e   # keep going so the build status can be reported (PIPESTATUS below)
xcodebuild -project Iter.xcodeproj -scheme Iter -configuration Debug -derivedDataPath "$DD" \
  "${VERSION_ARGS[@]}" build -quiet 2>&1 | { grep -E "error:" | grep -v "failed with exit code 0" || true; }
BUILD_STATUS=${PIPESTATUS[0]}
set -e
APP="$DD/Build/Products/Debug/Iter.app"
if [ "$BUILD_STATUS" -ne 0 ] || [ ! -x "$APP/Contents/MacOS/Iter" ]; then
  echo "Build failed (xcodebuild exit $BUILD_STATUS); build/Iter.app was left as it was." >&2
  exit 1
fi
rm -rf build/Iter.app && ditto "$APP" build/Iter.app
echo "Built $ROOT/build/Iter.app"
echo "WARNING: this is the real app (com.dwjames.iter) on the real store; its first launch migrates the store to V5." >&2
if [ "$OPEN" = 1 ]; then
  echo "Opening it now (--real)." >&2
  open build/Iter.app
else
  echo "Not opened. Pass --real to open it when you are ready." >&2
fi
