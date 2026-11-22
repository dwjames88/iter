#!/bin/bash
# Probe: swpc-solarwind
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://services.swpc.noaa.gov/products/solar-wind/mag-1-day.json'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/swpc-solarwind.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "swpc-solarwind HTTP $code"
head -c 600 "$OUT/swpc-solarwind.out"; echo
