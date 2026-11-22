#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }

# Wikidata SPARQL: mountains/waterfalls/viewpoints within 15 km, with image (P18)
for pt in "36.5785 -118.2923" "46.5586 8.5610"; do set -- $pt
Q="SELECT ?i ?iLabel ?c ?img WHERE { SERVICE wikibase:around { ?i wdt:P625 ?c . bd:serviceParam wikibase:center \"Point($2 $1)\"^^geo:wktLiteral . bd:serviceParam wikibase:radius \"15\" . } VALUES ?t { wd:Q8502 wd:Q34038 wd:Q1075 } ?i wdt:P31/wdt:P279* ?t . OPTIONAL{?i wdt:P18 ?img} SERVICE wikibase:label { bd:serviceParam wikibase:language \"en\". } } LIMIT 15"
get wikidata_$1 "https://query.wikidata.org/sparql" -H "Accept: application/sparql-results+json" --data-urlencode "query=$Q"
python3 -I -c "
import json
try:
  for b in json.load(open('$OUT/wikidata_$1.out'))['results']['bindings'][:8]: print('  ',b['iLabel']['value'],b['c']['value'],'IMG' if 'img' in b else '')
except Exception as e: print('  ERR',open('$OUT/wikidata_$1.out',errors='replace').read()[:200])"
sleep 2
done
