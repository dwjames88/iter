#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }
# NPS & RIDB: need keys. Using api.data.gov public DEMO_KEY for NPS (shared, rate-limited); no key for RIDB -> expect 401.
get nps "https://developer.nps.gov/api/v1/places?limit=3&q=whitney&api_key=DEMO_KEY" -D "$OUT/nps.hdr"
grep -i -E "x-ratelimit" "$OUT/nps.hdr"
python3 -I -c "
import json
d=json.load(open('$OUT/nps.out'));print('  total',d.get('total'))
for x in d.get('data',[])[:3]: print('  ',x['title'],x.get('latitude'),x.get('longitude'))"
get nps_parks_near "https://developer.nps.gov/api/v1/parks?limit=3&q=sequoia&api_key=DEMO_KEY"
python3 -I -c "
import json
for x in json.load(open('$OUT/nps_parks_near.out')).get('data',[])[:3]: print('  ',x['fullName'],x['latitude'],x['longitude'])"
get ridb "https://ridb.recreation.gov/api/v1/recareas?latitude=36.5785&longitude=-118.2923&radius=25"
head -c 200 "$OUT/ridb.out"; echo
