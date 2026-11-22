#!/bin/bash
# Probe script; downloads go to scratchpad (untrusted). UA is generic.
UA="IterProbe/0.1 (data-source evaluation)"
S=${TMPDIR:-/tmp}/iter-probes/weather
mkdir -p "$S"
LAT=${1:-36.5785}; LON=${2:--118.2923}
curl -sS -m 60 -A "$UA" "https://api.weather.gov/points/$LAT,$LON" -o $S/pt.json -w 'points HTTP %{http_code}\n'
G=$(python3 -I -c "import json;print(json.load(open('$S/pt.json'))['properties']['forecastGridData'])") || exit 1
curl -sS -m 60 -A "$UA" "$G" -o $S/grid.json -w 'gridpoints HTTP %{http_code} %{size_download}B\n'
python3 -I -c "
import json;d=json.load(open('$S/grid.json'))['properties']
print('has low/mid/high cloud keys:',[k for k in d if 'loud' in k and k!='skyCover'] or 'NONE (only skyCover)')
for k in ['skyCover','visibility','relativeHumidity','windSpeed','probabilityOfPrecipitation','lowVisibilityOccurrenceRiskIndex']:
  v=d[k]['values'];print(k,len(v),v[0])"
curl -sS -m 60 -A "$UA" "https://api.weather.gov/stations/KBIH/observations/latest" -o $S/obs.json -w 'obs HTTP %{http_code}\n'
python3 -I -c "
import json;p=json.load(open('$S/obs.json'))['properties'];print(p['timestamp'],p['textDescription'],p['visibility']['value'],p['cloudLayers'])"
curl -sS -m 60 -A "$UA" "https://api.weather.gov/alerts/active?point=$LAT,$LON" -o /dev/null -w 'alerts HTTP %{http_code}\n'
