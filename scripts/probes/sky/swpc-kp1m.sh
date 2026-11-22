#!/bin/bash
# Probe: swpc-kp1m
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://services.swpc.noaa.gov/json/planetary_k_index_1m.json'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/swpc-kp1m.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "swpc-kp1m HTTP $code"
head -c 600 "$OUT/swpc-kp1m.out"; echo
