#!/bin/bash
# Probe: swpc-kp-forecast
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/swpc-kp-forecast.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "swpc-kp-forecast HTTP $code"
head -c 600 "$OUT/swpc-kp-forecast.out"; echo
