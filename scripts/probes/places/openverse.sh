#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }
# Openverse: CC images; no geo search (probe text query). Anonymous allowed w/ low limits.
get openverse "https://api.openverse.org/v1/images/?q=mount%20whitney&page_size=3&fields=title,license,source"
python3 -I -c "
import json
d=json.load(open('$OUT/openverse.out'))
for r in d.get('results',[])[:3]: print('  ',r['title'],r['license'],r['source'])
print(' keys:',list(d)[:6]) if 'results' not in d else None"
# geo: no bbox/lat/lon parameter exists; bbox is silently ignored (same 240 results as without it)
get openverse_geo "https://api.openverse.org/v1/images/?q=sunrise&bbox=-118.4,36.5,-118.2,36.7&page_size=1"
python3 -I -c "import json;print('  result_count',json.load(open('$OUT/openverse_geo.out'))['result_count'])"
