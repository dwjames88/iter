#!/bin/bash
# Probe script; downloads go to scratchpad (untrusted). UA is generic.
UA="IterProbe/0.1 (data-source evaluation)"
S=${TMPDIR:-/tmp}/iter-probes/weather
mkdir -p "$S"
D=${1:-$(date -u +%Y%m%d)}; C=${2:-12}
B=https://noaa-hrrr-bdp-pds.s3.amazonaws.com/hrrr.$D/conus/hrrr.t${C}z.wrfsfcf01.grib2
curl -sS -m 60 -A "$UA" "$B.idx" -o $S/hrrr.idx -w 'idx HTTP %{http_code}\n'; grep -E ':(VIS|LCDC|MCDC|HCDC|TCDC):' $S/hrrr.idx
R=$(grep -A1 ':LCDC:' $S/hrrr.idx | awk -F: 'NR==1{s=$2} NR==2{print s"-"$2-1}')
mkdir -p $S/aws; curl -sS -m 60 -A "$UA" -r $R -o $S/aws/lcdc.grib2 -w "range $R HTTP %{http_code} %{size_download}B\n" "$B"
python3 -I "$(dirname "$0")/grib2_templates.py" $S/aws/lcdc.grib2
