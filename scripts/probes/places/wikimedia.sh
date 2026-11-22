#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }

for pt in "36.5785|-118.2923" "46.5586|8.5610"; do lat=${pt%|*}; lon=${pt#*|}
 echo "== $lat,$lon"
 get wp_geo_$lat "https://en.wikipedia.org/w/api.php?action=query&list=geosearch&gscoord=$lat%7C$lon&gsradius=10000&gslimit=8&format=json"
 python3 -I -c "import json;[print('   WP',x['title'],x['dist']) for x in json.load(open('$OUT/wp_geo_$lat.out'))['query']['geosearch']]"; sleep 1
 get commons_$lat "https://commons.wikimedia.org/w/api.php?action=query&list=geosearch&gscoord=$lat%7C$lon&gsradius=10000&gsnamespace=6&gslimit=8&format=json"
 python3 -I -c "import json;[print('   Commons',x['title'],x['dist']) for x in json.load(open('$OUT/commons_$lat.out'))['query']['geosearch']]"; sleep 1
done
# Commons licence for one file
get commons_lic "https://commons.wikimedia.org/w/api.php?action=query&generator=geosearch&ggscoord=36.5785%7C-118.2923&ggsradius=10000&ggsnamespace=6&ggslimit=3&prop=imageinfo&iiprop=extmetadata%7Curl&format=json"
python3 -I -c "
import json
for p in json.load(open('$OUT/commons_lic.out'))['query']['pages'].values():
  m=p['imageinfo'][0]['extmetadata']; print('   LIC',p['title'][:50],m.get('LicenseShortName',{}).get('value'),'|',m.get('Artist',{}).get('value','')[:40])"
sleep 1
get wikivoyage "https://en.wikivoyage.org/w/api.php?action=query&list=geosearch&gscoord=46.5586%7C8.5610&gsradius=10000&gslimit=5&format=json"
python3 -I -c "import json;[print('   WV',x['title'],x['dist']) for x in json.load(open('$OUT/wikivoyage.out'))['query']['geosearch']]"
