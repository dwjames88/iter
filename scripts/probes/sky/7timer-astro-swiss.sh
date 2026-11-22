#!/bin/bash
# Probe: 7timer-astro-swiss
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://www.7timer.info/bin/astro.php?lon=8.5610&lat=46.5586&ac=0&unit=metric&output=json&tzshift=0'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/7timer-astro-swiss.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "7timer-astro-swiss HTTP $code"
head -c 600 "$OUT/7timer-astro-swiss.out"; echo
