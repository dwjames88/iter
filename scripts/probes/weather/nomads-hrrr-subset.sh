#!/bin/bash
# Probe script; downloads go to scratchpad (untrusted). UA is generic.
UA="IterProbe/0.1 (data-source evaluation)"
S=${TMPDIR:-/tmp}/iter-probes/weather
mkdir -p "$S"
# HRRR f01 box subset via NOMADS GRIB filter (pick latest cycle manually; edit D/C)
D=${1:-$(date -u +%Y%m%d)}; C=${2:-12}
Q="https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl?dir=%2Fhrrr.$D%2Fconus&file=hrrr.t${C}z.wrfsfcf01.grib2&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&subregion=&toplat=37&leftlon=-119&rightlon=-117.5&bottomlat=36"
mkdir -p $S/hrrr; curl -sS -m 60 -A "$UA" -o $S/hrrr/sub.grib2 -w 'NOMADS filter HTTP %{http_code} %{size_download}B\n' "$Q"
python3 -I "$(dirname "$0")/grib2_templates.py" $S/hrrr/sub.grib2
