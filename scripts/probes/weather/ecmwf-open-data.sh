#!/bin/bash
# Probe script; downloads go to scratchpad (untrusted). UA is generic.
UA="IterProbe/0.1 (data-source evaluation)"
S=${TMPDIR:-/tmp}/iter-probes/weather
mkdir -p "$S"
D=${1:-$(date -u +%Y%m%d)}; C=${2:-06}
U=https://data.ecmwf.int/forecasts/$D/${C}z/ifs/0p25/oper/${D}${C}0000-3h-oper-fc
curl -sS -m 60 -A "$UA" "$U.index" -o $S/ecmwf_idx.json -w 'index HTTP %{http_code}\n'
python3 -I -c "
import json
for l in open('$S/ecmwf_idx.json'):
  x=json.loads(l)
  if x['param'] in('lcc','mcc','hcc','tcc','vis'): print(x['param'],x['_offset'],x['_length'])"
mkdir -p $S/ecmwf
O=$(python3 -I -c "
import json
for l in open('$S/ecmwf_idx.json'):
  x=json.loads(l)
  if x['param']=='lcc': print(x['_offset'],x['_offset']+x['_length']-1)" | tr ' ' '-')
curl -sS -m 60 -A "$UA" -r $O -o $S/ecmwf/lcc.grib2 -w "lcc range HTTP %{http_code} %{size_download}B\n" "$U.grib2"
python3 -I "$(dirname "$0")/grib2_templates.py" $S/ecmwf/lcc.grib2
