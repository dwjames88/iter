#!/bin/bash
# thumbs.sh - screen thumbnails for the Flows board: Design/paper/assets/thumbs/<id>.png, 320x205.
#   Design/paper/tools/thumbs.sh [id ...]      default: every light 1280-wide screen artboard in the manifest
# Renders headlessly at 1x (sequential, niced); 1280x2600 spot pages are cropped to the top 820 (a 1280x820 window).
# Resize uses sips (macOS built-in). Re-runnable. Never opens a window.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"; PAPER="$(cd "$HERE/.." && pwd)"
OUT="$PAPER/assets/thumbs"; TMP="/tmp/scratch/scratchpad/paper/thumbs-tmp"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p "$OUT" "$TMP"
LIST=$(node -e '
const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
const ids=process.argv.slice(2);
for(const e of m){ if(e.section!=="screens"||e.theme!=="light"||e.width!==1280||e.companionOf) continue; if(ids.length&&!ids.includes(e.id)) continue; console.log(e.id+" "+e.file+" "+e.height); }' "$PAPER/artboards/manifest.json" "$@")
N=0
while read -r ID FILE H; do
  [ -z "$ID" ] && continue
  RAW="$TMP/$ID.png"; rm -f "$RAW"
  nice -n 10 "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --no-first-run --disable-extensions --allow-file-access-from-files --screenshot="$RAW" --window-size="1280,$([ "$H" -gt 820 ] && echo 820 || echo $H)" "file://$PAPER/artboards/$FILE" </dev/null >/dev/null 2>&1 || true; [ -f "$RAW" ] || { echo "render failed: $ID" >&2; continue; }
  sips -z 205 320 "$RAW" --out "$OUT/$ID.png" >/dev/null
  N=$((N+1))
done <<< "$LIST"
echo "thumbs: $N written to assets/thumbs/"
