#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }

# OSM Overpass: viewpoints/peaks/waterfalls within 15km of each test point
for pt in "36.5785 -118.2923" "46.5586 8.5610"; do set -- $pt
 for host in overpass-api.de/api/interpreter overpass.kumi.systems/api/interpreter overpass.private.coffee/api/interpreter; do
  q="[out:json][timeout:25];(nwr[tourism=viewpoint](around:15000,$1,$2);node[natural=peak][name](around:15000,$1,$2);node[waterway=waterfall](around:15000,$1,$2););out center 400;"
  get "overpass_${host%%/*}_$1" "https://$host" --data-urlencode "data=$q"
  python3 -I -c "
import json,sys
try: d=json.load(open('$OUT/overpass_${host%%/*}_$1.out'))
except Exception as e: print('  not JSON:',open('$OUT/overpass_${host%%/*}_$1.out',errors='replace').read()[:120].replace('\n',' ')); sys.exit()
el=d['elements']; print('  elements',len(el)); 
for e in el[:6]: t=e.get('tags',{}); print('  ',t.get('name'),t.get('tourism') or t.get('natural') or t.get('waterway'),t.get('ele'))"
  sleep 2
 done
done
