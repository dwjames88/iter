#!/bin/bash
# NASA GIBS VIIRS_Night_Lights WMTS tile (level 3, tile covering Mt Whitney). No key.
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}; mkdir -p "$OUT"
U='https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/VIIRS_Night_Lights/default/2016-01-01/500m/3/2/2.png'
curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -o "$OUT/nl.png" -w "gibs-night-lights HTTP %{http_code} %{size_download}B %{content_type}\n" "$U"; file "$OUT/nl.png"
