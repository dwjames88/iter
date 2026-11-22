#!/bin/bash
# Probe: celestrak-iss
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=json'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/celestrak-iss.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "celestrak-iss HTTP $code"
head -c 600 "$OUT/celestrak-iss.out"; echo
