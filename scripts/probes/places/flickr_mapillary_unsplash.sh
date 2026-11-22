#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }
# Keyed services: expect auth failure without key (no accounts created)
get flickr "https://www.flickr.com/services/rest/?method=flickr.photos.search&lat=36.5785&lon=-118.2923&format=json&nojsoncallback=1"
head -c 200 "$OUT/flickr.out"; echo
get mapillary "https://graph.mapillary.com/images?fields=id&bbox=-118.30,36.57,-118.28,36.59&limit=1"
head -c 200 "$OUT/mapillary.out"; echo
get unsplash "https://api.unsplash.com/search/photos?query=mount+whitney"
head -c 200 "$OUT/unsplash.out"; echo
get five00px "https://api.500px.com/v1/photos/search?term=whitney"
head -c 200 "$OUT/five00px.out"; echo
get geonames "http://api.geonames.org/findNearbyJSON?lat=36.5785&lng=-118.2923&username=demo"
head -c 200 "$OUT/geonames.out"; echo
