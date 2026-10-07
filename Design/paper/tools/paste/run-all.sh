#!/bin/zsh
# Full paste run, one step per invocation. Usage: run-all.sh next | status
set -u
SCRATCH="${PASTE_SCRATCH:-/tmp/iter-scratch/paste}"
BIN="$SCRATCH/bin"
HERE="${0:A:h}"
PAPER_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="${PASTE_LOG:-$PAPER_DIR/PASTE-LOG.md}"
ORDER="$HERE/ORDER.txt"
CYCLE="$HERE/paste-cycle.sh"
PAPER_BID="com.todesktop.2601167vjw8xe"
STATE="$SCRATCH/state"
mkdir -p "$STATE"

# Page list row click positions (window-relative points)
PAGE_X=75
typeset -A PAGE_Y
PAGE_Y=( "Foundations" 166  "Flows" 194  "Screens (Dark)" 222  "Screens (Light)" 251  "Components" 278 )
typeset -A DIR_PAGE
DIR_PAGE=( foundations "Foundations"  components "Components"  screens-light "Screens (Light)"  screens-dark "Screens (Dark)"  flows "Flows" )

ts() { date +%Y-%m-%dT%H:%M:%S; }
log() { print -r -- "$(ts) $*" >> "$LOG"; }
[[ -f "$LOG" ]] || "$CYCLE" look-none >/dev/null 2>&1   # creates the log header (usage error is expected)

# absolute paths of entries with an OK line
done_list() { awk '$1=="OK"{print $3}' "$LOG" 2>/dev/null; }

next_entry() {
  local done e
  done="$(done_list)"
  while IFS= read -r e; do
    [[ -z "$e" ]] && continue
    if ! print -r -- "$done" | grep -qxF -- "$PAPER_DIR/$e"; then print -r -- "$e"; return 0; fi
  done < "$ORDER"
  return 1
}

pending_paste() { # true if last PASTE-START has no OK/FAIL after it
  local p r
  p=$(grep -n 'PASTE-START' "$LOG" | tail -1 | cut -d: -f1)
  [[ -z "$p" ]] && return 1
  r=$(grep -nE '^(OK|FAIL) ' "$LOG" | tail -1 | cut -d: -f1)
  [[ -z "$r" ]] && return 0
  (( p > r ))
}

switch_page() { # switch_page <page name>
  local page="$1" y="${PAGE_Y[$1]:-}" line wid title wx wy ww wh k i
  [[ -n "$y" ]] || { print -u2 "unknown page $page"; exit 2; }
  line="$("$BIN/paperctl" window)" || { print -u2 "no Paper window"; exit 6; }
  IFS=$'\t' read -r wid title wx wy ww wh <<< "$line"
  [[ "$title" == "Iter" ]] || { log "ABORT title is '$title'"; print -u2 "ABORT title '$title'"; exit 6; }
  k="$("$BIN/paperctl" keysdown)"; i="$("$BIN/paperctl" idle)"
  if [[ "$k" != "none" ]] || (( i < 1.5 )); then log "ABORT owner active (page switch)"; print -u2 "ABORT owner active"; exit 4; fi
  if [[ "$("$BIN/paperctl" front | cut -f1)" != "$PAPER_BID" ]]; then
    "$BIN/paperctl" activate "$PAPER_BID" >/dev/null || { log "ABORT could not activate Paper (page switch)"; exit 5; }
    line="$("$BIN/paperctl" window)"; IFS=$'\t' read -r wid title wx wy ww wh <<< "$line"
    [[ "$title" == "Iter" ]] || { log "ABORT title '$title' after activate"; exit 6; }
  fi
  local cx=$((wx + PAGE_X)) cy=$((wy + y))
  [[ "$("$BIN/paperctl" keysdown)" == "none" && "$("$BIN/paperctl" front | cut -f1)" == "$PAPER_BID" ]] || { log "ABORT focus/keys before click"; exit 5; }
  log "PAGE-SWITCH $page click=$cx,$cy (window $wid at $wx,$wy)"
  "$BIN/paperctl" click "$cx" "$cy" >/dev/null || { log "click failed"; exit 5; }
  sleep 1
  print -r -- "$page" > "$STATE/current_page"
  print -r -- "switched to page: $page"
  "$CYCLE" shot "page-${page// /_}" page
}

case "${1:-}" in
  next)
    if pending_paste; then
      print -u2 "REFUSED: last paste has no OK/FAIL yet. Run: paste-cycle.sh ok|fail <file> \"<note>\""
      exit 9
    fi
    entry="$(next_entry)" || { print "ALL DONE"; exit 0; }
    page="${DIR_PAGE[${entry:h:t}]:-}"
    [[ -n "$page" ]] || { print -u2 "no page mapping for $entry"; exit 2; }
    cur="$(cat "$STATE/current_page" 2>/dev/null || true)"
    if [[ "$cur" != "$page" ]]; then
      switch_page "$page"
      print "next step: re-run 'run-all.sh next' to paste $entry"
      exit 0
    fi
    print -r -- "pasting: $PAPER_DIR/$entry"
    "$CYCLE" paste "$PAPER_DIR/$entry" --mode "${PASTE_MODE:-plain}"; rc=$?
    (( rc == 0 )) && print "then run: paste-cycle.sh ok|fail $PAPER_DIR/$entry \"<note>\"" || print -u2 "paste exited $rc"
    exit $rc
    ;;
  status)
    total=$(grep -c . "$ORDER"); okc=0
    while IFS= read -r e; do [[ -n "$e" ]] && print -r -- "$(done_list)" | grep -qxF -- "$PAPER_DIR/$e" && okc=$((okc+1)); done < "$ORDER"
    print "last OK: $(grep -E '^OK ' "$LOG" | tail -1)"
    print "current page: $(cat "$STATE/current_page" 2>/dev/null || echo unknown)"
    print "pending paste (no OK/FAIL): $(pending_paste && echo yes || echo no)"
    print "next entry: $(next_entry || echo none)"
    print "remaining: $((total - okc)) of $total"
    ;;
  *)
    print -u2 "usage: run-all.sh next | status"; exit 2 ;;
esac
