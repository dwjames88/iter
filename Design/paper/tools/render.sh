#!/bin/bash
# render.sh - headless Chrome screenshots of built artboards, sequential and niced.
#   Design/paper/tools/render.sh <artboard.html ...>         -> <scratch>/renders/<same relative path>.png  (1x, manifest size)
#   Design/paper/tools/render.sh --side <artboard.html ...>   -> also <path>.side.png: the render beside its snapshot, same height
# Never opens a window: --headless=new only.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="/tmp/iter-scratch/paper/renders"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SIDE=0
[ "$1" = "--side" ] && SIDE=1 && shift
[ $# -eq 0 ] && { echo "usage: render.sh [--side] <artboard.html ...>"; exit 1; }
shot() { # url out w h
  nice -n 10 "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --no-first-run --disable-extensions \
    --allow-file-access-from-files --default-background-color=00000000 --screenshot="$2" --window-size="$3,$4" "$1" >/dev/null 2>&1
}
for f in "$@"; do
  f="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
  read -r W H REL SNAP < <(node "$HERE/render-info.mjs" "$f")
  OUT="$SCRATCH/$REL"
  mkdir -p "$(dirname "$OUT")"
  shot "file://$f" "$OUT" "$W" "$H"
  echo "$OUT"
  if [ $SIDE -eq 1 ]; then
    if [ "$SNAP" = "-" ] || [ ! -f "$SNAP" ]; then echo "  (no snapshot for $REL)"; continue; fi
    HTML="${OUT%.png}.side.html"
    read -r SW SH < <(node "$HERE/render-info.mjs" --side-html "$OUT" "$SNAP" "$HTML")
    shot "file://$HTML" "${OUT%.png}.side.png" "$SW" "$SH"
    echo "${OUT%.png}.side.png"
  fi
done
