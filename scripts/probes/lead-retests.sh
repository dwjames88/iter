#!/usr/bin/env bash
# Lead re-tests for SOURCES.md (2026-11-22): items where researchers disagreed or left gaps.
# Prints HTTP status and a short excerpt. Downloads go to $OUT (default: a temp dir).
set -u
UA="IterProbe/0.1 (data-source evaluation)"
OUT="${OUT:-$(mktemp -d)}"
D="${D:-$(date -u +%Y%m%d)}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "== WMM2025 coefficient zips (two NCEI paths)"
for u in https://www.ncei.noaa.gov/sites/default/files/2024-12/WMM2025COF.zip \
         https://www.ncei.noaa.gov/sites/default/files/2025-01/WMM2025COF.zip; do
  curl -sS -o /dev/null -A "$UA" -m 30 -w "%{http_code} %{size_download}B $u\n" "$u"
done

echo "== NGA GEOnet Names Server reachability"
curl -sS -o /dev/null -A "$UA" -m 20 -w "%{http_code}\n" https://geonames.nga.mil/geon-ags/rest/services || echo "unreachable"

echo "== HRRR smoke/AOD via NOMADS filter (small box near Whitney; 12z f01)"
curl -sS -A "$UA" -m 60 -o "$OUT/smoke.grib2" -w "%{http_code} %{size_download}B\n" \
 "https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl?dir=%2Fhrrr.${D}%2Fconus&file=hrrr.t12z.wrfsfcf01.grib2&var_MASSDEN=on&var_COLMD=on&var_AOTK=on&all_lev=on&subregion=&toplat=37&leftlon=-119&rightlon=-117.5&bottomlat=36"
python3 -I "$HERE/weather/grib2_templates.py" "$OUT/smoke.grib2" 2>&1 | head -5

echo "== EUMETSAT view WMS GetMap (Meteosat IR 10.8, Swiss Alps box)"
curl -sS -A "$UA" -m 90 -o "$OUT/eum.png" -w "%{http_code} %{content_type} %{size_download}B %{time_total}s\n" \
 "https://view.eumetsat.int/geoserver/wms?service=WMS&version=1.3.0&request=GetMap&layers=msg_fes:ir108&styles=&crs=EPSG:4326&bbox=45,7,48,10&width=256&height=256&format=image/png"
file "$OUT/eum.png"

echo "== Open-Meteo visibility at the Swiss point by model"
for m in ukmo_seamless best_match ecmwf_ifs025; do
  curl -sS -A "$UA" -m 40 "https://api.open-meteo.com/v1/forecast?latitude=46.5586&longitude=8.5610&hourly=visibility&forecast_days=1&models=$m" \
   | python3 -Ic "import sys,json;d=json.load(sys.stdin);print('$m', str(d.get('hourly',{}).get('visibility'))[:70])"
done
