#!/bin/bash
# Probe script; downloads go to scratchpad (untrusted). UA is generic.
UA="IterProbe/0.1 (data-source evaluation)"
S=${TMPDIR:-/tmp}/iter-probes/weather
mkdir -p "$S"
for p in "46.5586 8.5610" "36.5785 -118.2923"; do set -- $p
 curl -sS -m 60 -A "$UA" "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=$1&lon=$2" -o $S/met.json -w "locationforecast $1,$2 HTTP %{http_code}\n"
 python3 -I -c "
import json;t=json.load(open('$S/met.json'))['properties']['timeseries'];d=t[1]['data']['instant']['details'];print(len(t),t[-1]['time'],{k:d[k] for k in d if 'cloud' in k or 'fog' in k},'visibility' in d)"
 curl -sS -m 60 -A "$UA" "https://api.met.no/weatherapi/nowcast/2.0/complete?lat=$1&lon=$2" -w 'nowcast HTTP %{http_code}\n' | head -c 200
done
