#!/bin/bash
# Probe: celestrak-stations
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=json'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/celestrak-stations.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "celestrak-stations HTTP $code"
head -c 600 "$OUT/celestrak-stations.out"; echo
