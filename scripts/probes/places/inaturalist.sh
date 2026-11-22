#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }
# iNaturalist: no key for reads. Observations w/ photos near point (licence filter)
for pt in "36.5785 -118.2923" "46.5586 8.5610"; do set -- $pt
 get inat_$1 "https://api.inaturalist.org/v1/observations?lat=$1&lng=$2&radius=10&per_page=5&photos=true&photo_license=cc-by,cc-by-nc,cc0&order_by=votes"
 python3 -I -c "
import json
d=json.load(open('$OUT/inat_$1.out'));print('  total',d['total_results'])
for o in d['results'][:5]: print('  ',o.get('species_guess'),o.get('place_guess'),o['photos'][0]['license_code'] if o['photos'] else '')"
 sleep 1
done
