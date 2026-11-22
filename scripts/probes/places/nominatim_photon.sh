#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }

get nominatim "https://nominatim.openstreetmap.org/search?q=Mount+Whitney&format=jsonv2&limit=2"
python3 -I -c "import json;[print('  ',x['display_name'][:80],x['lat'],x['lon']) for x in json.load(open('$OUT/nominatim.out'))]"
sleep 1.2
get nominatim_rev "https://nominatim.openstreetmap.org/reverse?lat=46.5586&lon=8.5610&format=jsonv2"
python3 -I -c "import json;print('  ',json.load(open('$OUT/nominatim_rev.out')).get('display_name'))"
sleep 1.2
get photon "https://photon.komoot.io/api/?q=Grimsel+Pass&limit=3"
python3 -I -c "
import json
for f in json.load(open('$OUT/photon.out'))['features']: print('  ',f['properties'].get('name'),f['properties'].get('country'),f['geometry']['coordinates'])"
