#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }
# Web-search APIs without credentials: record what each says
get ddg_ia "https://api.duckduckgo.com/?q=Mount+Whitney&format=json&no_html=1"
python3 -I -c "
import json
try: d=json.load(open('$OUT/ddg_ia.out'));print('  Abstract:',d.get('AbstractText','')[:120],'| Results',len(d.get('Results',[])),'Related',len(d.get('RelatedTopics',[])))
except Exception as e: print('  not JSON',open('$OUT/ddg_ia.out',errors='replace').read()[:120])"
get brave "https://api.search.brave.com/res/v1/web/search?q=mount+whitney+photo+spots" -H "Accept: application/json"
head -c 250 "$OUT/brave.out"; echo
get mojeek "https://www.mojeek.com/search?q=mount+whitney&fmt=json"
grep -o "<title>[^<]*" "$OUT/mojeek.out" | head -1
get bing "https://api.bing.microsoft.com/v7.0/search?q=whitney"   # retired 2025-08-11: expect DNS failure / HTTP 000
[ -f "$OUT/bing.out" ] && head -c 250 "$OUT/bing.out"; echo
get gcse "https://www.googleapis.com/customsearch/v1?q=whitney"
head -c 250 "$OUT/gcse.out"; echo
get places_new "https://places.googleapis.com/v1/places:searchText" -X POST -H "Content-Type: application/json" -d '{"textQuery":"viewpoint"}'
head -c 250 "$OUT/places_new.out"; echo
