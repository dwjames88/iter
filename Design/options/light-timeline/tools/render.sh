#!/bin/bash
# render.sh [--2x] [id ...]  -> scratchpad/timeline-options/renders/<id>.png (1x) and <id>@2x.png (with --2x). Headless Chrome only.
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(dirname "$HERE")"
OUTD="/tmp/scratch/scratchpad/timeline-options/renders"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
X2=0; [ "$1" = "--2x" ] && X2=1 && shift
mkdir -p "$OUTD"
shot() { nice -n 10 "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=$5 --no-first-run --disable-extensions \
  --allow-file-access-from-files --default-background-color=00000000 --screenshot="$2" --window-size="$3,$4" "$1" >/dev/null 2>&1; }
LIST=$(node -e 'const m=require(process.argv[1]);const ids=process.argv.slice(2);for(const a of m)if(!ids.length||ids.some(i=>a.id.includes(i)))console.log(a.id,a.width,a.height)' "$ROOT/artboards/manifest.json" "$@")
echo "$LIST" | while read -r ID W H; do
  [ -z "$ID" ] && continue
  shot "file://$ROOT/artboards/$ID.html" "$OUTD/$ID.png" "$W" "$H" 1; echo "$OUTD/$ID.png"
  [ $X2 = 1 ] && shot "file://$ROOT/artboards/$ID.html" "$OUTD/$ID@2x.png" "$W" "$H" 2 && echo "$OUTD/$ID@2x.png"
done
