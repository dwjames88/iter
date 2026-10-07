#!/bin/bash
# End-to-end check of the updater, entirely local and invisible: no window, no Keychain, no network beyond 127.0.0.1.
#   scripts/updater-e2e.sh
# It builds the updater-fixture executable and iter-release, makes two ad-hoc-signed fixture apps (1.0.0 and 2.0.0),
# signs 2.0.0 with a throwaway key, serves a feed from a local web server, launches 1.0.0 hidden and checks that it
# finds, verifies and installs 2.0.0 (stripping the quarantine flag), relaunches as 2.0.0 and cleans up after itself.
# A second phase serves a feed signed with the wrong key and checks that nothing gets installed.
# Environment: ITER_E2E_DIR = work folder (default $TMPDIR/iter-updater-e2e-<pid>); ITER_E2E_KEEP=1 keeps it.
# Exits non-zero if any assertion fails. The fixture's own cache (~/Library/Caches/com.dwjames.iter.updatertest) is used and removed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
PKG="$ROOT/Packages/IterUpdater"
E2E="${ITER_E2E_DIR:-${TMPDIR:-/tmp}}"
[ -n "${ITER_E2E_DIR:-}" ] || E2E="${E2E%/}/iter-updater-e2e-$$"
mkdir -p "$E2E"; E2E="$(cd "$E2E" && pwd -P)"
FIXTURE_ID="com.dwjames.iter.updatertest"
CACHE="$HOME/Library/Caches/$FIXTURE_ID/Updates"
SERVERS=()
FAILS=0

# Stops only fixture processes started from inside this run's temp folder, found by their path (never by name).
kill_fixtures() {
  local pid
  for pid in $(pgrep -f "$E2E/install(-bad)?/UpdaterFixture.app" 2>/dev/null || true); do kill "$pid" 2>/dev/null || true; done
}

cleanup() {
  local pid
  for pid in ${SERVERS[@]+"${SERVERS[@]}"}; do { kill "$pid"; wait "$pid"; } 2>/dev/null || true; done
  kill_fixtures
  if [ "${ITER_E2E_KEEP:-0}" = 1 ]; then echo "kept $E2E"; else rm -rf "$E2E"; fi
}
trap cleanup EXIT

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
check() { # description, then a command
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi
}
free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }

echo "== Building updater-fixture and iter-release"
swift build --package-path "$PKG" -c release --product iter-release 2>&1 | tail -1
swift build --package-path "$PKG" -c release --product updater-fixture 2>&1 | tail -1
BIN="$(swift build --package-path "$PKG" -c release --show-bin-path)"
TOOL="$BIN/iter-release"; FIXTURE="$BIN/updater-fixture"
[ -x "$TOOL" ] && [ -x "$FIXTURE" ] || { echo "the package did not build both executables" >&2; exit 1; }

echo "== Throwaway keys (temp files only)"
RIGHT_PAIR="$("$TOOL" keygen)"; WRONG_PAIR="$("$TOOL" keygen)"
field() { printf '%s' "$1" | python3 -c "import json,sys;print(json.load(sys.stdin)['$2'])"; }
PRIV="$(field "$RIGHT_PAIR" privateKey)"; PUB="$(field "$RIGHT_PAIR" publicKey)"
WRONG_PRIV="$(field "$WRONG_PAIR" privateKey)"

# make_app <dest dir> <version> <build> <feed port> <log path>
make_app() {
  local dest="$1" version="$2" build="$3" port="$4" log="$5"
  local app="$dest/UpdaterFixture.app"
  rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
  cp "$FIXTURE" "$app/Contents/MacOS/UpdaterFixture"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$FIXTURE_ID</string>
  <key>CFBundleName</key><string>UpdaterFixture</string>
  <key>CFBundleExecutable</key><string>UpdaterFixture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>LSBackgroundOnly</key><true/>
  <key>LSUIElement</key><true/>
  <key>IterUpdateFeedURL</key><string>http://127.0.0.1:$port/appcast.json</string>
  <key>IterUpdatePublicKey</key><string>$PUB</string>
  <key>FixtureLogPath</key><string>$log</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST
  codesign --force -s - --options runtime "$app" >/dev/null 2>&1
}

serve() { # folder, port
  python3 -m http.server "$2" --bind 127.0.0.1 --directory "$1" >/dev/null 2>&1 &
  SERVERS+=("$!")
  local i
  for i in $(seq 1 50); do curl -fs -o /dev/null "http://127.0.0.1:$2/" && return 0; sleep 0.1; done
  echo "web server on port $2 did not start" >&2; exit 1
}

wait_for() { # file, pattern, seconds
  local i
  for i in $(seq 1 "$3"); do grep -qE "$2" "$1" 2>/dev/null && return 0; sleep 1; done
  return 1
}

echo "== Fixture bundles (1.0.0 build 1 and 2.0.0 build 2)"
PORT_OK="$(free_port)"; PORT_BAD="$(free_port)"
while [ "$PORT_BAD" = "$PORT_OK" ]; do PORT_BAD="$(free_port)"; done
mkdir -p "$E2E/build-v1" "$E2E/build-v2" "$E2E/served" "$E2E/served-bad" "$E2E/install" "$E2E/install-bad"
make_app "$E2E/build-v1" 1.0.0 1 "$PORT_OK" "$E2E/log.txt"
make_app "$E2E/build-v2" 2.0.0 2 "$PORT_OK" "$E2E/log.txt"
# A downloaded app carries the quarantine flag; the updater must strip it from what it installs.
STAMP="0081;$(printf %x "$(date +%s)");Safari;"
find "$E2E/build-v2/UpdaterFixture.app" -exec xattr -w com.apple.quarantine "$STAMP" {} \;
ditto -c -k --keepParent "$E2E/build-v2/UpdaterFixture.app" "$E2E/served/UpdaterFixture-2.0.0.zip"
printf 'E2E\n' > "$E2E/notes.md"
feed() { # signing key, zip, out
  local sig; sig="$(printf '%s' "$1" | "$TOOL" sign "$2")"
  "$TOOL" feed --archive "$2" --version 2.0.0 --build 2 --url "http://127.0.0.1:$4/UpdaterFixture-2.0.0.zip" \
    --signature "$sig" --notes-file "$E2E/notes.md" --min-os 26.0 --notarized false --out "$3"
}
feed "$PRIV" "$E2E/served/UpdaterFixture-2.0.0.zip" "$E2E/served/appcast.json" "$PORT_OK"
# Wrong-key phase: the same archive, but the feed's signature comes from a different key.
cp "$E2E/served/UpdaterFixture-2.0.0.zip" "$E2E/served-bad/"
feed "$WRONG_PRIV" "$E2E/served-bad/UpdaterFixture-2.0.0.zip" "$E2E/served-bad/appcast.json" "$PORT_BAD"
mkdir -p "$E2E/unzip-check" && ditto -x -k "$E2E/served/UpdaterFixture-2.0.0.zip" "$E2E/unzip-check"
if xattr -r "$E2E/unzip-check" 2>/dev/null | grep -q com.apple.quarantine; then
  echo "note: the served zip carries the quarantine flag, so the strip is really tested"
else
  echo "note: the served zip does not carry the quarantine flag (ditto dropped it); the updater's strip is not exercised"
fi

echo "== Phase 1: update 1.0.0 to 2.0.0"
serve "$E2E/served" "$PORT_OK"
ditto "$E2E/build-v1/UpdaterFixture.app" "$E2E/install/UpdaterFixture.app"
rm -rf "$CACHE"; : > "$E2E/log.txt"
open -g -j -n "$E2E/install/UpdaterFixture.app"
if wait_for "$E2E/log.txt" '^up-to-date 2\.0\.0' 60; then pass "the fixture reached up-to-date 2.0.0 within 60 s"; else fail "no 'up-to-date 2.0.0' within 60 s"; fi
sleep 1
echo "--- log"; cat "$E2E/log.txt"; echo "---"
LOG="$E2E/log.txt"
check "log: launched 1.0.0"    grep -qE '^launched 1\.0\.0' "$LOG"
check "log: found 2.0.0"       grep -qE '^found 2\.0\.0' "$LOG"
check "log: verified"          grep -qE '^verified' "$LOG"
check "log: installed"         grep -qE '^installed' "$LOG"
check "log: relaunching"       grep -qE '^relaunching' "$LOG"
check "log: launched 2.0.0 with quarantined=false" grep -qE '^launched 2\.0\.0 .*quarantined=false' "$LOG"
check "no error in the log"    bash -c "! grep -qE '^error' '$LOG'"
INSTALLED="$E2E/install/UpdaterFixture.app"
GOT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED/Contents/Info.plist" 2>/dev/null || true)"
if [ "$GOT" = 2.0.0 ]; then pass "installed Info.plist says 2.0.0"; else fail "installed Info.plist says '$GOT', expected 2.0.0"; fi
check "no quarantine flag anywhere in the installed bundle" bash -c "! xattr -r '$INSTALLED' 2>/dev/null | grep -q com.apple.quarantine"
check "codesign --verify passes on the installed bundle" codesign --verify --strict --deep "$INSTALLED"
check "the fixture's work folder is gone" bash -c "[ ! -d '$CACHE' ] || [ -z \"\$(ls -A '$CACHE')\" ]"
kill_fixtures

echo "== Phase 2: a feed signed with the wrong key must install nothing"
serve "$E2E/served-bad" "$PORT_BAD"
make_app "$E2E/install-bad" 1.0.0 1 "$PORT_BAD" "$E2E/log-bad.txt"
: > "$E2E/log-bad.txt"
open -g -j -n "$E2E/install-bad/UpdaterFixture.app"
if wait_for "$E2E/log-bad.txt" '^error' 60; then pass "the fixture logged an error for the bad signature"; else fail "no 'error' within 60 s"; fi
sleep 1
echo "--- log"; cat "$E2E/log-bad.txt"; echo "---"
check "log: found 2.0.0 but never installed" bash -c "grep -qE '^found 2\.0\.0' '$E2E/log-bad.txt' && ! grep -qE '^installed' '$E2E/log-bad.txt'"
GOT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$E2E/install-bad/UpdaterFixture.app/Contents/Info.plist" 2>/dev/null || true)"
if [ "$GOT" = 1.0.0 ]; then pass "1.0.0 is still installed"; else fail "installed version is '$GOT', expected 1.0.0"; fi
rm -rf "$CACHE"

echo
if [ "$FAILS" = 0 ]; then echo "updater-e2e: ALL PASSED"; else echo "updater-e2e: $FAILS FAILED"; exit 1; fi
