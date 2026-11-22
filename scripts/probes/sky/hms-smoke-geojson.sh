#!/bin/bash
# Probe: hms-smoke-geojson
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://satepsanone.nesdis.noaa.gov/pub/FIRE/web/HMS/Smoke_Polygons/GeoJSON/2026/11/'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/hms-smoke-geojson.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "hms-smoke-geojson HTTP $code"
head -c 600 "$OUT/hms-smoke-geojson.out"; echo
