#!/bin/bash
# Probe: swpc-3day
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://services.swpc.noaa.gov/text/3-day-forecast.txt'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/swpc-3day.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "swpc-3day HTTP $code"
head -c 600 "$OUT/swpc-3day.out"; echo
