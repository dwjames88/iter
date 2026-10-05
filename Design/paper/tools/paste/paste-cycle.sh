#!/bin/zsh
# Paper paste cycle: one subcommand per step. See header of PASTE-LOG.md.
set -u
SCRATCH="${PASTE_SCRATCH:-/tmp/scratch/scratchpad/paste}"
BIN="$SCRATCH/bin"
PAPER_DIR="/path/to/Iter/Design/paper"
LOG="${PASTE_LOG:-$PAPER_DIR/PASTE-LOG.md}"
PAPER_BID="com.todesktop.2601167vjw8xe"
EXPECT_TITLE="Iter"
STATE="$SCRATCH/state"
SHOTS="$SCRATCH/shots"
mkdir -p "$STATE" "$SHOTS"

ts() { date +%Y-%m-%dT%H:%M:%S; }
stamp() { date +%Y%m%d-%H%M%S; }

if [[ ! -f "$LOG" ]]; then
  {
    print -r -- "# Paper paste log"
    print
    print -r -- "Action log of tools/paste/paste-cycle.sh. The last line starting with \"OK \" names the last successful artboard."
    print
    print -r -- "## Log"
    print
  } > "$LOG"
fi

log() { print -r -- "$(ts) $*" >> "$LOG"; }
say() { print -r -- "$*"; log "$*"; }

# globals filled by get_window
WID="" WTITLE="" WX="" WY="" WW="" WH=""
get_window() {
  local line
  line="$("$BIN/paperctl" window)" || return 1
  IFS=$'\t' read -r WID WTITLE WX WY WW WH <<< "$line"
  return 0
}
require_title() {
  get_window || { log "ABORT no Paper window"; print -u2 "no Paper window"; exit 6; }
  if [[ "$WTITLE" != "$EXPECT_TITLE" ]]; then
    log "ABORT window title is '$WTITLE', expected '$EXPECT_TITLE'"
    print -u2 "ABORT: Paper window title is '$WTITLE', expected '$EXPECT_TITLE'"
    exit 6
  fi
}
front_bid() { "$BIN/paperctl" front | cut -f1; }
keys_none() { [[ "$("$BIN/paperctl" keysdown)" == "none" ]]; }
idle_ge() { # idle_ge <secs>
  local v; v="$("$BIN/paperctl" idle)" || return 1
  (( v >= $1 ))
}
guard_owner() { # guard_owner <min idle>
  if ! keys_none || ! idle_ge "$1"; then
    log "ABORT owner active (keys: $("$BIN/paperctl" keysdown 2>&1 | tr '\n' ' ') idle: $("$BIN/paperctl" idle))"
    print -u2 "ABORT owner active"
    exit 4
  fi
}
shoot() { # shoot <name> <suffix>
  local base="$SHOTS/$(stamp)-$1-$2"
  get_window || { log "ABORT no Paper window for screenshot"; exit 6; }
  /usr/sbin/screencapture -x -o -l "$WID" "$base.png" || { log "screencapture failed"; exit 7; }
  /usr/bin/sips -Z 1600 "$base.png" --out "$base-small.png" >/dev/null 2>&1
  log "SHOT window=$WID $base.png"
  print -r -- "$base.png"
  print -r -- "$base-small.png"
}

cmd="${1:-}"; (( $# > 0 )) && shift
case "$cmd" in
  look)
    name="${1:?usage: look <name>}"
    require_title
    shoot "$name" look
    ;;

  shot)
    name="${1:?usage: shot <name> [suffix]}"
    suffix="${2:-shot}"
    require_title
    shoot "$name" "$suffix"
    ;;

  paste)
    file="${1:?usage: paste <payloadFile> [--mode both|plain]}"; shift
    mode="${PASTE_MODE:-plain}"   # trial 2026-10-05: Paper ignores the public.html flavour; plain text works
    if [[ "${1:-}" == "--mode" ]]; then mode="${2:-both}"; fi
    [[ -f "$file" ]] || { print -u2 "no such file: $file"; exit 2; }
    [[ "$mode" == "both" || "$mode" == "plain" ]] || { print -u2 "bad mode"; exit 2; }
    name="$(basename "$file" .html)"
    size=$(wc -c < "$file" | tr -d ' ')
    # (a) remember previous front
    fb="$(front_bid)"
    if [[ "$fb" != "$PAPER_BID" ]]; then print -r -- "$fb" > "$STATE/prev_front"; fi
    # title check before touching anything
    require_title
    # (b) guard
    guard_owner 1.5
    log "PASTE-START $file mode=$mode bytes=$size window=$WID prev_front=$(cat "$STATE/prev_front" 2>/dev/null)"
    # (c) clipboard
    if [[ ! -d "$STATE/owner-clip" ]]; then
      "$BIN/clip" save "$STATE/owner-clip" >/dev/null || { rm -rf "$STATE/owner-clip"; log "ABORT clip save failed"; exit 8; }
      log "owner clipboard saved"
    else
      log "owner clipboard already saved this cycle (kept)"
    fi
    cc="$("$BIN/clip" set "$file" --mode "$mode")" || { log "ABORT clip set failed"; exit 8; }
    log "clipboard set changeCount=$cc"
    # (d) activate
    "$BIN/paperctl" activate "$PAPER_BID" >/dev/null || { log "ABORT could not activate Paper"; print -u2 "ABORT activate failed"; exit 5; }
    "$BIN/paperctl" waitfront "$PAPER_BID" 3 >/dev/null || { log "ABORT Paper not frontmost"; exit 5; }
    log "Paper frontmost"
    require_title
    # deselect first (trial 2: a pasted artboard stays selected; Escape after the paste settles clears it,
    # so the next paste lands at top level instead of possibly inside the previous board)
    if [[ "$(front_bid)" != "$PAPER_BID" ]] || ! keys_none; then log "ABORT focus/keys before Escape"; exit 5; fi
    /usr/bin/osascript -e 'tell application "System Events" to key code 53' || { log "ABORT osascript failed"; exit 5; }
    log "KEY escape sent (deselect)"
    sleep 0.6
    # (e) last-moment checks, then keystroke
    if [[ "$(front_bid)" != "$PAPER_BID" ]] || ! keys_none; then
      log "ABORT focus changed or keys down before keystroke"; print -u2 "ABORT focus/keys before keystroke"; exit 5
    fi
    /usr/bin/osascript -e 'tell application "System Events" to keystroke "v" using command down' || { log "ABORT osascript failed"; exit 5; }
    log "KEYSTROKE cmd+v sent"
    # (f)
    if [[ "$(front_bid)" != "$PAPER_BID" ]]; then
      log "ABORT focus changed after keystroke"; print -u2 "ABORT focus changed"; exit 5
    fi
    # (g)
    sleep "${PASTE_WAIT:-4}"
    shoot "$name" after
    ;;

  undo)
    n="${1:-1}"
    [[ "$n" == <-> ]] || { print -u2 "usage: undo [n]"; exit 2; }
    require_title
    guard_owner 1.0
    if [[ "$(front_bid)" != "$PAPER_BID" ]]; then
      "$BIN/paperctl" activate "$PAPER_BID" >/dev/null || { log "ABORT could not activate Paper for undo"; exit 5; }
      require_title
    fi
    i=0
    while (( i < n )); do
      if [[ "$(front_bid)" != "$PAPER_BID" ]] || ! keys_none; then
        log "ABORT focus changed or keys down before undo $((i+1))"; print -u2 "ABORT"; exit 5
      fi
      /usr/bin/osascript -e 'tell application "System Events" to keystroke "z" using command down' || { log "ABORT osascript failed"; exit 5; }
      log "UNDO $((i+1))/$n sent"
      i=$((i+1))
      (( i < n )) && sleep 0.4
    done
    sleep 2
    shoot "undo" undo
    ;;

  key) # key escape|right  (deselect / one nudge test only; never text)
    k="${1:?usage: key escape|right}"
    case "$k" in escape) code=53 ;; right) code=124 ;; *) print -u2 "only escape|right"; exit 2 ;; esac
    require_title
    guard_owner 1.0
    if [[ "$(front_bid)" != "$PAPER_BID" ]] || ! keys_none; then log "ABORT focus/keys before key $k"; print -u2 "ABORT"; exit 5; fi
    /usr/bin/osascript -e "tell application \"System Events\" to key code $code" || { log "ABORT osascript failed"; exit 5; }
    log "KEY $k sent"
    sleep 1.5
    shoot "key-$k" key
    ;;

  click) # click <winX> <winY>  window-relative points, on a spot confirmed empty from a screenshot (deselect only)
    cx="${1:?usage: click <winX> <winY>}"; cy="${2:?}"
    require_title
    guard_owner 1.0
    if [[ "$(front_bid)" != "$PAPER_BID" ]] || ! keys_none; then log "ABORT focus/keys before click"; print -u2 "ABORT"; exit 5; fi
    "$BIN/paperctl" click $((WX + cx)) $((WY + cy)) >/dev/null || { log "ABORT click failed"; exit 5; }
    log "CLICK window-relative $cx,$cy (screen $((WX + cx)),$((WY + cy)))"
    sleep 1.5
    shoot "click" click
    ;;

  back)
    if [[ -d "$STATE/owner-clip" ]]; then
      "$BIN/clip" restore "$STATE/owner-clip" >/dev/null && { rm -rf "$STATE/owner-clip"; log "owner clipboard restored"; } || { log "clipboard restore FAILED (dir kept)"; exit 8; }
    else
      log "back: no saved owner clipboard"
    fi
    if [[ -s "$STATE/prev_front" ]]; then
      pf="$(cat "$STATE/prev_front")"
      "$BIN/paperctl" activate "$pf" >/dev/null && log "activated previous front $pf" || log "could not activate previous front $pf"
    else
      log "back: no prev_front recorded"
    fi
    ;;

  ok|fail)
    file="${1:?usage: $cmd <payloadFile> <note>}"; shift
    note="$*"
    tag="${cmd:u}"
    print -r -- "$tag $(ts) $file $note" >> "$LOG"
    ;;

  *)
    print -u2 "usage: paste-cycle.sh look <name> | shot <name> [suffix] | paste <file> [--mode both|plain] | undo [n] | back | ok <file> <note> | fail <file> <note>"
    exit 2
    ;;
esac
