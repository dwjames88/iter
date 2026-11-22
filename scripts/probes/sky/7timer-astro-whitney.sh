#!/bin/bash
# Probe: 7timer-astro-whitney
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://www.7timer.info/bin/astro.php?lon=-118.2923&lat=36.5785&ac=0&unit=metric&output=json&tzshift=0'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/7timer-astro-whitney.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "7timer-astro-whitney HTTP $code"
head -c 600 "$OUT/7timer-astro-whitney.out"; echo
