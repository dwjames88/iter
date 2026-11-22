#!/bin/bash
# Records the GRIB2 test fixtures from the NOAA NOMADS GRIB filter into the folder this script lives in.
# Usage: record.sh [YYYYMMDD] [HRRR cycle hour] [GFS cycle hour]     (defaults: today UTC, 12, 06)
# Test points: W = 36.5785,-118.2923 (Mount Whitney), S = 46.5586,8.5610 (Swiss Alps).
# Prints one line per file: name, UTC fetch time, size, URL.
set -u
UA="IterProbe/0.1 (data-source evaluation)"
HERE="$(cd "$(dirname "$0")" && pwd)"
DATE=${1:-$(date -u +%Y%m%d)}
HC=${2:-12}
GC=${3:-06}
VARS="var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on"
LEVS="lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on"
SMOKE="var_MASSDEN=on&var_COLMD=on&var_AOTK=on&lev_8_m_above_ground=on&lev_entire_atmosphere_%28considered_as_a_single_layer%29=on"

fetch() { # name url
  local out="$HERE/$1" now code
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  code=$(curl -sS -m 90 -A "$UA" -o "$out" -w '%{http_code}' "$2")
  echo "$1 | $now | HTTP $code | $(wc -c < "$out" | tr -d ' ') bytes | $2"
  [ "$code" = 200 ] || { rm -f "$out"; echo "FAILED: $1" >&2; }
  sleep 3
}

for f in 01 06 12; do
  fetch "hrrr-W-${DATE}t${HC}z-f${f}.grib2" \
    "https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl?dir=%2Fhrrr.${DATE}%2Fconus&file=hrrr.t${HC}z.wrfsfcf${f}.grib2&${VARS}&${SMOKE}&${LEVS}&subregion=&toplat=36.8&leftlon=-118.6&rightlon=-118.0&bottomlat=36.3"
done
for f in 003 006 012; do
  fetch "gfs-S-${DATE}t${GC}z-f${f}.grib2" \
    "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?dir=%2Fgfs.${DATE}%2F${GC}%2Fatmos&file=gfs.t${GC}z.pgrb2.0p25.f${f}&${VARS}&${LEVS}&subregion=&toplat=47&leftlon=8&rightlon=9&bottomlat=46"
  fetch "gfs-W-${DATE}t${GC}z-f${f}.grib2" \
    "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?dir=%2Fgfs.${DATE}%2F${GC}%2Fatmos&file=gfs.t${GC}z.pgrb2.0p25.f${f}&${VARS}&${LEVS}&subregion=&toplat=37&leftlon=-119&rightlon=-118&bottomlat=36"
done
