#!/bin/bash
# NOAA OSPO Hazard Mapping System smoke polygons (KML/shapefile only; no GeoJSON path found).
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}; mkdir -p "$OUT"
Y=$(date -u +%Y); M=$(date -u +%m); D=$(date -u +%Y%m%d)
curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -o "$OUT/hms.kml" -w "hms HTTP %{http_code} %{size_download}B\n" "https://satepsanone.nesdis.noaa.gov/pub/FIRE/web/HMS/Smoke_Polygons/KML/$Y/$M/hms_smoke$D.kml"
echo "Placemarks (smoke polygons): $(grep -c '<Placemark' "$OUT/hms.kml")"
