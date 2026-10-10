#!/bin/bash
# Real-pointer test for dragging your own pin on the Mac maps (Explore and Locations). For each screen and camera it
# launches the render copy (visible, not activated; a hidden window gets no pointer events), then posts CGEvent mouse
# events and reads what the app's -IterPinDragProbe wrote. Cases per screen and camera (3 km flat, 80 km flat, pitched):
#   a  drag right after the spot is added (selected)
#   b  click empty map so the pin is unselected, then drag it: the pin must move, not the map
#   c  click the selected pin once (it must stay selected), then drag it
# Then one cluster case on Explore: a spot of yours beside a curated sample spot with the camera 200 km out, where the
# two would merge into a numbered cluster. After a click on empty map (unselected) the probe must report it as a pin
# (dot or chip), report at least one cluster in view, and the pin must drag as above.
# Each case asserts the stored coordinate is where the drop point was (|stored - expected| <= max(3 m, 2 pt in metres)),
# that the pin's tip followed the pointer by the dragged delta (<= 2.5 pt), and that the map did not pan.
# Needs Accessibility trust for the terminal to post events, and the screen unlocked. Moves the cursor briefly and puts it back.
# Environment: ITER_DD = derived data path (scripts/render.sh); ITER_PINDRAG_CAMERAS = "name=lat,lon,km[,pitch];..." and
# ITER_PINDRAG_SECTIONS = "explore locations" (either one, or both) to override.
#   scripts/pin-drag-test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/build/render/Iter.app"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/iter-pindrag.XXXXXX")"
TOOL="$WORK/pointer"
CAMERAS="${ITER_PINDRAG_CAMERAS:-3 km flat=34.64,-120.61,3;80 km flat=34.64,-120.61,80;pitched=34.64,-120.61,0.5,45}"
CLUSTER_SPOT="37.7170,-119.6790,Cluster Test"   # ~200 m from Tunnel View, a curated spot
CLUSTER_CAMERA="37.72,-119.68,200"
PID=""
export ITER_POINTER_LOG="${ITER_POINTER_LOG:-$WORK/pointer.log}"
cleanup() { [ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

command -v jq >/dev/null || { echo "jq is needed" >&2; exit 1; }
"$ROOT/scripts/render.sh" || exit 1
swiftc -O "$ROOT/scripts/tools/pointer.swift" -o "$TOOL" || exit 1

FAILS=0
report() { # name case ok detail
  if [ "$3" = 1 ]; then echo "PASS  $1 / $2  $4"; else echo "FAIL  $1 / $2  $4"; FAILS=$((FAILS + 1)); fi
}
J() { jq -r "$1" "$PROBE" 2>/dev/null; }
wait_for() { # jq expression that must be true, seconds
  local i; for i in $(seq 1 $(($2 * 5))); do [ "$(J "$1")" = true ] && return 0; sleep 0.2; done; return 1
}

# Waits until the camera and the pin's tip have stopped changing for 1.2 s (pitch and tiles settle after launch and clicks).
settle() {
  local last="" now same=0 i
  for i in $(seq 1 60); do
    now="$(J '[.settles, .camera.pitch, .spot.grabGlobal.x, .spot.grabGlobal.y] | tostring')"
    if [ "$now" = "$last" ]; then same=$((same + 1)); [ "$same" -ge 4 ] && return 0; else same=0; fi
    last="$now"; sleep 0.3
  done
}

# Drags the pin by (dx,dy) points from its body and judges the move. $1 camera name, $2 case, $3 dx, $4 dy
drag_case() {
  local name="$1" case="$2" dx="$3" dy="$4" before gx gy
  settle
  before="$(J '.moves | length')"
  CAM0="$(J '.camera | "\(.lat) \(.lon)"')"   # the map's own settles after a click are not the drag's pan
  gx="$(J '.spot.grabGlobal.x')"; gy="$(J '.spot.grabGlobal.y')"
  "$TOOL" drag "$gx" "$gy" "$(awk "BEGIN{print $gx+($dx)}")" "$(awk "BEGIN{print $gy+($dy)}")"
  if ! wait_for "(.moves | length) > $before and (.moves[-1].tipAfterWindow != null)" 8; then
    cp "$PROBE" "${TMPDIR:-/tmp}/pindrag-fail-$case.json" 2>/dev/null; cp "$ITER_POINTER_LOG" "${TMPDIR:-/tmp}/pindrag-fail-$case.pointer.log" 2>/dev/null; report "$name" "$case" 0 "no committed move (the pointer panned the map or never reached the pin)"; return
  fi
  local err tol tipdx tipdy tiperr drift pan
  err="$(J '.moves[-1].errorMetres')"
  tol="$(J '[3, .spot.metresPer2pt] | max')"
  # Judged against the delta this script posted (not the gesture's own report), so a wrong conversion cannot pass.
  tiperr="$(jq -r --argjson dx "$dx" --argjson dy "$dy" '.moves[-1] | ((.tipAfterWindow.x - (.tipBeforeWindow.x + $dx)) as $a | (.tipAfterWindow.y - (.tipBeforeWindow.y + $dy)) as $b | ($a*$a + $b*$b | sqrt))' "$PROBE")"
  drift="$(jq -r --argjson lat0 "${CAM0% *}" --argjson lon0 "${CAM0#* }" '.camera as $c | (($c.lat - $lat0) * 111320) as $y | (($c.lon - $lon0) * 111320 * ($lat0 * 0.0174533 | cos)) as $x | ($x*$x + $y*$y | sqrt)' "$PROBE")"
  pan="$(awk -v d="$drift" -v t="$tol" 'BEGIN{print (d <= t) ? 1 : 0}')"
  local ok=1
  awk -v e="$err" -v t="$tol" 'BEGIN{exit !(e <= t)}' || ok=0
  awk -v e="$tiperr" 'BEGIN{exit !(e <= 2.5)}' || ok=0
  [ "$pan" = 1 ] || ok=0
  report "$name" "$case" "$ok" "$(printf 'error %.2f m (tolerance %.1f m), tip off by %.2f pt, map drift %.2f m' "$err" "$tol" "$tiperr" "$drift")"
}

# Launches the render copy on a section with a spot added, waits for the probe, brings the window to the front and settles.
# $1 result name, $2 section, $3 -IterAddSpot value, $4 camera. Sets PID, returns 1 when the copy never got going.
front() { osascript -e "tell application \"System Events\" to get unix id of first process whose frontmost is true" 2>/dev/null; }
launch() {
  local name="$1" section="$2" add="$3" cam="$4" before p
  PROBE="$WORK/probe.json"; rm -f "$PROBE"
  before="$(pgrep -f "$APP/Contents/MacOS/Iter" || true)"
  open -g -n "$APP" --args -IterInMemoryStore YES -IterSampleDataEnabled YES -IterSection "$section" \
    -IterAddSpot "$add" -IterMapCamera "$cam" -IterWindowSize 1280x820 -IterScriptKeepOpen YES -IterPinDragProbe "$PROBE"
  PID=""
  for _ in $(seq 1 50); do
    for p in $(pgrep -f "$APP/Contents/MacOS/Iter" || true); do
      case " $before " in *" $p "*) ;; *) PID="$p" ;; esac
    done
    [ -n "$PID" ] && break
    sleep 0.2
  done
  [ -n "$PID" ] || { echo "FAIL  $name  the render copy did not start"; FAILS=$((FAILS + 1)); return 1; }
  if ! wait_for '.spot != null and .window != null and .initialCamera != null' 40; then
    report "$name" "setup" 0 "the probe never reported the spot"; kill "$PID" 2>/dev/null; PID=""; return 1
  fi
  sleep 2   # tiles and the card settle
  for _ in 1 2 3 4 5 6 7 8; do
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $PID) to true" >/dev/null 2>&1
    sleep 0.6
    [ "$(front)" = "$PID" ] && break
  done
  [ "$(front)" = "$PID" ] || echo "note: the render copy is not frontmost; events may not reach it"
  settle
}

# Clicks the empty map at the window's bottom-right (clear of the toolbar, the floating list card and the pin) so nothing is selected.
click_empty_map() {
  local wx wy ww wh
  wx="$(J '.window.x')"; wy="$(J '.window.y')"; ww="$(J '.window.w')"; wh="$(J '.window.h')"
  "$TOOL" click "$(awk "BEGIN{print $wx+$ww-60}")" "$(awk "BEGIN{print $wy+$wh-60}")"
}

stop() { kill "$PID" 2>/dev/null; PID=""; sleep 1; }

# a, b and c at every camera on one screen. $1 section (explore or locations)
run_section() {
  local section="$1" entry NAME CAM PITCH
  IFS=';' read -ra LIST <<< "$CAMERAS"
  for entry in "${LIST[@]}"; do
    NAME="$section ${entry%%=*}"; CAM="${entry#*=}"
    launch "$NAME" "$section" "34.64,-120.61,Wall Cliffs" "$CAM" || continue
    PITCH="$(J '.camera.pitch')"
    echo "-- $NAME ($CAM): camera pitch $(printf '%.1f' "$PITCH") distance $(printf '%.0f' "$(J '.camera.distance')") m; window $(J '.window | "\(.x),\(.y) \(.w)x\(.h)"'); 2 pt = $(printf '%.2f' "$(J '.spot.metresPer2pt')") m"

    case "$NAME" in *pitched*) awk -v p="$PITCH" 'BEGIN{exit !(p >= 10)}' && report "$NAME" "camera pitches" 1 "pitch $(printf '%.0f' "$PITCH") degrees" || report "$NAME" "camera pitches" 0 "pitch is only $PITCH, the map is top-down" ;; esac
    # a: selected, right after the add
    drag_case "$NAME" "a selected" 90 50

    sleep 1.5
    # b: click empty map so nothing is selected, then drag
    click_empty_map
    sleep 2
    drag_case "$NAME" "b unselected" -70 40

    sleep 1.5
    # c: click the selected pin once; it must stay selected; then drag
    "$TOOL" click "$(J '.spot.grabGlobal.x')" "$(J '.spot.grabGlobal.y')"
    sleep 2
    if [ "$(J '.selectedID // empty')" != "" ] && [ "$(J '.selectedID')" = "$(J '.spot.id')" ]; then report "$NAME" "c click keeps it selected" 1 ""; else report "$NAME" "c click keeps it selected" 0 "selection is '$(J '.selectedID')'"; fi
    drag_case "$NAME" "c click then drag" 50 -60

    stop
  done
}

# Explore only: a spot of yours beside Tunnel View (a curated sample spot) with the camera far out, where the two would
# otherwise merge into one numbered cluster. Unselected, it must still be drawn as its own pin.
run_cluster_case() {
  local NAME="explore cluster" style clusters
  launch "$NAME" explore "$CLUSTER_SPOT" "$CLUSTER_CAMERA" || return
  echo "-- $NAME ($CLUSTER_CAMERA): spot $CLUSTER_SPOT; window $(J '.window | "\(.x),\(.y) \(.w)x\(.h)"'); 2 pt = $(printf '%.2f' "$(J '.spot.metresPer2pt')") m"
  click_empty_map
  sleep 2.5
  settle
  style="$(J '.spot.style')"; clusters="$(J '.clusters')"
  [ "$(J '.selectedID // empty')" = "" ] && report "$NAME" "unselected" 1 "" || report "$NAME" "unselected" 0 "selection is '$(J '.selectedID')'"
  case "$style" in dot|chip) report "$NAME" "own spot is a pin, not merged" 1 "style $style" ;; *) report "$NAME" "own spot is a pin, not merged" 0 "style is '$style'" ;; esac
  [ "${clusters:-0}" -ge 1 ] 2>/dev/null && report "$NAME" "area clusters" 1 "$clusters cluster(s) in view" || report "$NAME" "area clusters" 0 "no cluster in view ('$clusters'), so the case proves nothing"
  drag_case "$NAME" "d drag unclustered pin" 90 50
  stop
}

SECTIONS="${ITER_PINDRAG_SECTIONS:-explore locations}"
for section in $SECTIONS; do run_section "$section"; done
case " $SECTIONS " in *" explore "*) run_cluster_case ;; esac
[ "$FAILS" = 0 ] && echo "All pin-drag cases passed" || echo "$FAILS pin-drag case(s) FAILED"
[ "$FAILS" = 0 ]
