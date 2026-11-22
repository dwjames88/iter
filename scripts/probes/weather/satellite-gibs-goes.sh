#!/bin/bash
# Probe script; downloads go to scratchpad (untrusted). UA is generic.
UA="IterProbe/0.1 (data-source evaluation)"
S=${TMPDIR:-/tmp}/iter-probes/weather
mkdir -p "$S"
echo "-- STAR CDN"
for u in GOES19/ABI/CONUS/GEOCOLOR/latest.jpg GOES18/ABI/SECTOR/psw/GEOCOLOR/latest.jpg GOES19/ABI/SECTOR/psw/13/latest.jpg; do
 curl -sS -m 60 -A "$UA" -I "https://cdn.star.nesdis.noaa.gov/$u" | egrep -i '^HTTP|last-modified|content-length' | tr '\r\n' '  '; echo " $u"; done
echo "-- GIBS WMTS tile (EPSG:4326, 2km matrix, z4 row4 col5 covers Sierra Nevada); time must be a 10-min stamp that exists"
T=${1:-$(date -u -v-60M +%Y-%m-%dT%H:%M:00Z | sed 's/:[0-9][0-9]:00Z/:00:00Z/')}
mkdir -p $S/gibs; curl -sS -m 60 -A "$UA" -o $S/gibs/ir.png -w "GIBS GOES-West B13 $T HTTP %{http_code} %{size_download}B\n" "https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/GOES-West_ABI_Band13_Clean_Infrared/default/$T/2km/4/4/5.png"
file $S/gibs/ir.png
