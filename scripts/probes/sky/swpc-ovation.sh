#!/bin/bash
# Probe: swpc-ovation
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://services.swpc.noaa.gov/json/ovation_aurora_latest.json'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/swpc-ovation.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "swpc-ovation HTTP $code"
head -c 600 "$OUT/swpc-ovation.out"; echo
