#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }
get waymarked "https://hiking.waymarkedtrails.org/api/v1/list/search?query=John+Muir+Trail&limit=3"
head -c 300 "$OUT/waymarked.out"; echo
get darksky_places "https://darksky.org/wp-json/wp/v2/types"
head -c 200 "$OUT/darksky_places.out"; echo
get darksky_rest "https://darksky.org/wp-json/wp/v2/darksky_place?per_page=3&_fields=id,link,title" -D "$OUT/ds.hdr"
grep -i x-wp-total "$OUT/ds.hdr"; python3 -I -c "
import json;[print('  ',x['title']['rendered'],x['link']) for x in json.load(open('$OUT/darksky_rest.out'))]"
get darksky_page "https://darksky.org/what-we-do/international-dark-sky-places/"
echo "  title: $(grep -o -i '<title>[^<]*' "$OUT/darksky_page.out" | head -1)"
