#!/bin/bash
# Probe: firms-area
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://firms.modaps.eosdis.nasa.gov/api/area/csv/DEMO_KEY/VIIRS_SNPP_NRT/-120,35,-117,38/1'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/firms-area.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "firms-area HTTP $code"
head -c 600 "$OUT/firms-area.out"; echo
