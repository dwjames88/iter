#!/bin/bash
# Probe script; downloads go to scratchpad (untrusted). UA is generic.
UA="IterProbe/0.1 (data-source evaluation)"
S=${TMPDIR:-/tmp}/iter-probes/weather
mkdir -p "$S"
for m in gfs_seamless ncep_hrrr_conus ecmwf_ifs025 icon_seamless ukmo_seamless meteofrance_seamless; do
 curl -sS -m 60 -A "$UA" "https://api.open-meteo.com/v1/forecast?latitude=${1:-36.5785}&longitude=${2:--118.2923}&models=$m&hourly=cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility&forecast_days=10" -o $S/om.json -w "$m HTTP %{http_code} "
 python3 -I -c "
import json;h=json.load(open('$S/om.json')).get('hourly',{});print(len(h.get('time',[])),'h low',h.get('cloud_cover_low',[])[12:15],'vis',h.get('visibility',[])[12:15])"
done
curl -sS -m 60 -A "$UA" "https://api.open-meteo.com/v1/forecast?latitude=36.5785&longitude=-118.2923&models=ncep_hrrr_conus&minutely_15=temperature_2m,precipitation&forecast_hours=2" -w '\nminutely_15 HTTP %{http_code}\n' | head -c 400
curl -sS -m 60 -A "$UA" "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=46.5586&longitude=8.561&hourly=aerosol_optical_depth,dust&forecast_days=1" -w '\nair-quality HTTP %{http_code}\n' | head -c 300
