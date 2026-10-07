#!/bin/bash
# Builds Iter (Debug, signed with your Apple Development certificate) and opens it.
#   scripts/run.sh               build and open build/Iter.app
#   scripts/run.sh --no-open     build only
#   scripts/run.sh --weatherkit  include the WeatherKit entitlement (needs a paid team with WeatherKit on the
#                                App ID com.dwjames.iter and an Apple ID signed in to Xcode; see TESTING.md)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OPEN=1; EXTRA=()
for arg in "$@"; do
  case "$arg" in
    --no-open) OPEN=0 ;;
    --weatherkit) EXTRA+=(ITER_ENTITLEMENTS=App/Iter-WeatherKit.entitlements -allowProvisioningUpdates) ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
command -v xcodegen >/dev/null || { echo "XcodeGen is needed (brew install xcodegen)" >&2; exit 1; }
xcodegen generate --quiet
VERSION_ARGS=($("$ROOT/scripts/version.sh"))   # build number and git hash (scripts/version.sh)
xcodebuild -project Iter.xcodeproj -scheme Iter -configuration Debug -derivedDataPath build/DerivedData \
  "${VERSION_ARGS[@]}" ${EXTRA[@]+"${EXTRA[@]}"} build -quiet 2>&1 | grep -E "error:|warning: .*Iter/(App|Packages)" || true
APP="build/DerivedData/Build/Products/Debug/Iter.app"
[ -d "$APP" ] || { echo "Build failed." >&2; exit 1; }
rm -rf build/Iter.app && ditto "$APP" build/Iter.app
echo "Built $ROOT/build/Iter.app"
if [ "$OPEN" = 1 ]; then open build/Iter.app; fi
