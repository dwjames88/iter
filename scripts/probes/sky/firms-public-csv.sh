#!/bin/bash
# Probe: firms-public-csv
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://firms.modaps.eosdis.nasa.gov/data/active_fire/suomi-npp-viirs-c2/csv/SUOMI_VIIRS_C2_USA_contiguous_and_Hawaii_24h.csv'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/firms-public-csv.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "firms-public-csv HTTP $code"
head -c 600 "$OUT/firms-public-csv.out"; echo
