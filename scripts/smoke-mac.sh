#!/bin/bash
# Hidden smoke launch of the Mac render copy (com.dwjames.iter.render): builds it (scripts/render.sh), launches it with
# `open -g -j -n` (background, hidden, new instance: it is never activated or fronted), waits for it to quit by itself or
# stops its own PID after a timeout, and reports what happened.
#   scripts/smoke-mac.sh [--no-build] [--timeout SECONDS] [-- <extra app args>]
#   scripts/smoke-mac.sh -- -IterSeedTrip YES -IterSection trip -IterSmokeQuitAfter 8
# Always passes: -IterInMemoryStore YES -IterLocation 38.39,-109.87 -IterSampleDataEnabled YES -IterSmokeQuitAfter 8
# (each unless the caller passes its own). The app's stdout and stderr go to build/smoke-mac.log.
#
# Switches the Mac shell must implement (the shell worker; IterApp.swift is a stub until then):
#   -IterSmokeQuitAfter N   once the first window's content has loaded, log one line to stdout starting with "smoke: ready"
#                           (what it loaded: section, counts, store kind), then quit itself with exit 0 after N seconds. On a
#                           failure to load, log "smoke: failed <reason>" and exit non-zero straight away.
#   plus the contract in LaunchOptions: -IterInMemoryStore, -IterLocation, -IterSampleDataEnabled, -IterSection, -IterSeedTrip.
# Result: exit 0 = quit by itself and "smoke: ready" was logged; 1 = anything else (timeout, no ready line, a new crash
# report, "smoke: failed"). While the shell is the stub, the script still runs and reports "no smoke: ready line".
# Environment: ITER_DD (derived data, used by render.sh).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RENDER_ID="com.dwjames.iter.render"
APP="$ROOT/build/render/Iter.app"
BIN="$APP/Contents/MacOS/Iter"
BUILD=1; TIMEOUT=30; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) BUILD=0 ;;
    --timeout) TIMEOUT="${2:?--timeout needs seconds}"; shift ;;
    --) shift; EXTRA=("$@"); break ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ "$BUILD" = 1 ]; then "$ROOT/scripts/render.sh" || exit 1; fi
[ -x "$BIN" ] || { echo "No render copy at $APP (run without --no-build)" >&2; exit 1; }
ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [ "$ID" != "$RENDER_ID" ]; then echo "Refusing to launch: bundle id is '$ID', not $RENDER_ID" >&2; exit 1; fi

has() { case " ${EXTRA[*]-} " in *" $1 "*) return 0 ;; esac; return 1; }
ARGS=(-IterInMemoryStore YES)
has -IterLocation || ARGS+=(-IterLocation 38.39,-109.87)
has -IterSampleDataEnabled || ARGS+=(-IterSampleDataEnabled YES)
has -IterSmokeQuitAfter || ARGS+=(-IterSmokeQuitAfter 8)
ARGS+=(${EXTRA[@]+"${EXTRA[@]}"})

LOG="$ROOT/build/smoke-mac.log"; mkdir -p "$ROOT/build"; : > "$LOG"
MARK="$(mktemp "${TMPDIR:-/tmp}/iter-smoke.XXXXXX")"
BEFORE="$(pgrep -f "$BIN" || true)"
START=$(date +%s)
open -g -j -n --stdout "$LOG" --stderr "$LOG" "$APP" --args "${ARGS[@]}"
PID=""
for _ in $(seq 1 50); do
  for p in $(pgrep -f "$BIN" || true); do case " $BEFORE " in *" $p "*) ;; *) PID="$p" ;; esac; done
  [ -n "$PID" ] && break
  sleep 0.2
done
[ -n "$PID" ] || { echo "The render copy did not start" >&2; rm -f "$MARK"; exit 1; }
echo "Launched render copy (hidden), pid $PID, args: ${ARGS[*]}"
KILLED=0
for _ in $(seq 1 "$TIMEOUT"); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null; sleep 1; kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
  KILLED=1
fi
ELAPSED=$(( $(date +%s) - START ))
READY="$(grep -m1 "smoke: ready" "$LOG" || true)"
FAILED="$(grep -m1 "smoke: failed" "$LOG" || true)"
CRASH="$(find "$HOME/Library/Logs/DiagnosticReports" -name 'Iter-*.ips' -newer "$MARK" 2>/dev/null | head -1)"
rm -f "$MARK"
[ "$KILLED" = 1 ] && echo "Status: still running after ${TIMEOUT}s; stopped pid $PID (not a clean quit)" || echo "Status: quit by itself after ${ELAPSED}s"
[ -n "$READY" ] && echo "Ready line: $READY" || echo "Ready line: none (no 'smoke: ready' in $LOG; expected while the shell is the stub)"
[ -n "$FAILED" ] && echo "Failure line: $FAILED"
[ -n "$CRASH" ] && echo "Crash report: $CRASH"
echo "Log: $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
[ "$KILLED" = 0 ] && [ -n "$READY" ] && [ -z "$FAILED" ] && [ -z "$CRASH" ] && { echo "SMOKE PASS"; exit 0; }
echo "SMOKE FAIL"; exit 1
