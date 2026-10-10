#!/bin/bash
# Builds a render copy of the Mac app and (optionally) runs it hidden, for screenshots and measurements.
# The copy has bundle id com.dwjames.iter.render and is ad-hoc signed, so it never runs as the real app: it keeps off the
# Keychain, the real store and Application Support/Iter (see RenderCopy). It never touches any other process.
#   scripts/render.sh                      build build/render/Iter.app (Debug)
#   scripts/render.sh --release            build Release instead
#   scripts/render.sh --run [--wait N] [--capture DIR] -- <app args>
#                                          also launch it (open -g -j -n) with -IterInMemoryStore YES -IterSampleDataEnabled YES
#                                          plus your args; wait N seconds (default 20) or until it exits; then stop that PID only
#   --capture DIR                          adds -IterCaptureWindow DIR and, unless you pass -IterCaptureAfter, -IterCaptureAfter 6
#                                          (one screen.png of whatever is showing, then the app quits)
#   --run adds -IterLocation 37.77,-122.42 (San Francisco) unless you pass -IterLocation, so no location dialog ever shows
# Environment: ITER_DD = derived data path (default build/DD-render).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RENDER_ID="com.dwjames.iter.render"
CONFIG=Debug; RUN=0; WAIT=20; CAPTURE=""; APP_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --release) CONFIG=Release ;;
    --run) RUN=1 ;;
    --wait) WAIT="${2:?--wait needs seconds}"; shift ;;
    --capture) CAPTURE="${2:?--capture needs a folder}"; shift ;;
    --) shift; APP_ARGS=("$@"); break ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
DD="${ITER_DD:-build/DD-render}"
OUT="$ROOT/build/render/Iter.app"

command -v xcodegen >/dev/null || { echo "XcodeGen is needed (brew install xcodegen)" >&2; exit 1; }
xcodegen generate --quiet
VERSION_ARGS=($("$ROOT/scripts/version.sh"))
# Ad hoc, no team, no hardened runtime (a Debug build loads Iter.debug.dylib, which hardened runtime would refuse).
SIGN=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO)
set +e
xcodebuild -project Iter.xcodeproj -scheme Iter -configuration "$CONFIG" -derivedDataPath "$DD" \
  ITER_BUNDLE_ID="$RENDER_ID" "${SIGN[@]}" "${VERSION_ARGS[@]}" build -quiet 2>&1 | { grep -E "error:" | grep -v "failed with exit code 0" || true; }
STATUS=${PIPESTATUS[0]}
set -e
BUILT="$DD/Build/Products/$CONFIG/Iter.app"
if [ "$STATUS" -ne 0 ] || [ ! -x "$BUILT/Contents/MacOS/Iter" ]; then echo "Build failed (xcodebuild exit $STATUS)" >&2; exit 1; fi

rm -rf "$OUT"; mkdir -p "$(dirname "$OUT")"; ditto "$BUILT" "$OUT"
# The copy may carry a provisioning profile or Developer ID signature from the build; re-sign ad hoc, no runtime option.
codesign --force --deep -s - "$OUT" >/dev/null 2>&1
ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$OUT/Contents/Info.plist")"
if [ "$ID" != "$RENDER_ID" ]; then echo "Refusing to continue: built bundle id is '$ID', not $RENDER_ID" >&2; rm -rf "$OUT"; exit 1; fi
echo "Built $OUT ($CONFIG, $ID)"
[ "$RUN" = 1 ] || exit 0

if [ -n "$CAPTURE" ]; then
  mkdir -p "$CAPTURE"
  CAPTURE="$(cd "$CAPTURE" && pwd)"   # the app resolves a relative folder against its own cwd and writes nowhere
  APP_ARGS+=(-IterCaptureWindow "$CAPTURE")
  case " ${APP_ARGS[*]} " in *" -IterCaptureAfter "*) ;; *) APP_ARGS+=(-IterCaptureAfter 6) ;; esac
fi
# Only a PID that was not there before this launch, matched on the full path of this render copy, is ever ours.
BEFORE="$(pgrep -f "$OUT/Contents/MacOS/Iter" || true)"
# A render copy never uses real location (no dialog): give it San Francisco unless the caller chose a place.
case " ${APP_ARGS[*]-} " in *" -IterLocation "*) ;; *) APP_ARGS+=(-IterLocation 37.77,-122.42) ;; esac
open -g -j -n "$OUT" --args -IterInMemoryStore YES -IterSampleDataEnabled YES ${APP_ARGS[@]+"${APP_ARGS[@]}"}
PID=""
for _ in $(seq 1 50); do
  for p in $(pgrep -f "$OUT/Contents/MacOS/Iter" || true); do
    case " $BEFORE " in *" $p "*) ;; *) PID="$p" ;; esac
  done
  [ -n "$PID" ] && break
  sleep 0.2
done
[ -n "$PID" ] || { echo "The render copy did not start" >&2; exit 1; }
echo "Launched render copy, pid $PID"
for _ in $(seq 1 "$WAIT"); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
if kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null || true; echo "Stopped pid $PID"; else echo "Render copy exited"; fi
[ -n "$CAPTURE" ] && ls "$CAPTURE"/*.png 2>/dev/null || true
