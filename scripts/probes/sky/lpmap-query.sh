#!/bin/bash
# Probe: lpmap-query
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://www.lightpollutionmap.info/QueryRaster/?ql=wa_2015&qt=point&qd=-118.2923,36.5785'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/lpmap-query.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "lpmap-query HTTP $code"
head -c 600 "$OUT/lpmap-query.out"; echo
