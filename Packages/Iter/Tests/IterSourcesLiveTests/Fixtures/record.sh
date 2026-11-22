#!/bin/bash
# Records the source fixtures (everything under Fixtures/ except GRIB2/ and Geomag/, which have their own scripts)
# into the folder this script lives in. Paths are relative to the script; nothing here touches GRIB2/ or Geomag/.
# Usage: record.sh [YYYY-MM-DD]      (USNO date, default: today UTC)
# Test points: W = 36.5785,-118.2923 (Mount Whitney, US), S = 46.5586,8.5610 (Swiss Alps near the Gotthard).
# Writes one line per request to manifest.tsv: file, UTC fetch time, HTTP status, bytes, method, URL, body, headers.
# Requests are spaced a few seconds apart. Up to three retries, 30 s apart, on 429/502/503/504.
# ONLY=<folder> (e.g. ONLY=Overpass) re-records just that folder and replaces its manifest rows.
# Note: reference.json for Terrarium is produced separately by Terrarium/make-reference.py.
set -u
UA="IterProbe/0.1 (data-source evaluation)"
HERE="$(cd "$(dirname "$0")" && pwd)"
DATE=${1:-$(date -u +%Y-%m-%d)}
WLAT=36.5785; WLON=-118.2923; SLAT=46.5586; SLON=8.5610
MANIFEST="$HERE/manifest.tsv"
ONLY=${ONLY:-}
if [ -z "$ONLY" ]; then
  printf 'file\tfetched_utc\tstatus\tbytes\tmethod\turl\tbody\theaders\n' > "$MANIFEST"
elif [ -f "$MANIFEST" ]; then
  grep -v "^$ONLY/" "$MANIFEST" > "$MANIFEST.new"; mv "$MANIFEST.new" "$MANIFEST"
fi

# fetch FILE URL SIDECAR(0|1) POST_BODY [extra header ...]
fetch() {
  local rel="$1" url="$2" side="$3" body="$4"; shift 4
  if [ -n "$ONLY" ] && [ "${rel%%/*}" != "$ONLY" ]; then return 0; fi
  local out="$HERE/$rel" now code tries=0 hdrs="" h tmp method=GET
  mkdir -p "$(dirname "$out")"
  tmp="$(mktemp)"
  local args=(-sS -m 120 -A "$UA" -D "$tmp" -o "$out" -w '%{http_code}')
  for h in "$@"; do args+=(-H "$h"); hdrs="$hdrs$h; "; done
  if [ -n "$body" ]; then method=POST; args+=(--data-urlencode "data=$body"); fi
  while :; do
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    code=$(curl "${args[@]}" "$url") || code=000
    case "$code" in 429|502|503|504) if [ $tries -lt 3 ]; then tries=$((tries+1)); sleep 30; continue; fi;; esac
    break
  done
  if [ "$side" = 1 ]; then
    tr -d '\r' < "$tmp" | grep -i -E '^(HTTP/|expires:|last-modified:|date:|content-type:|etag:)' > "${out%.*}.headers.txt"
  fi
  rm -f "$tmp"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$now" "$code" "$(wc -c < "$out" | tr -d ' ')" "$method" "$url" "$body" "$hdrs" | tee -a "$MANIFEST"
  [ "$code" = 200 ] || echo "FAILED: $rel (HTTP $code)" >&2
  sleep 3
}

# 1. MET Norway locationforecast 2.0 complete (coordinates at most 4 decimals), headers kept in a sidecar
fetch MetNo/locationforecast-W.json "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=$WLAT&lon=$WLON" 1 ""
fetch MetNo/locationforecast-S.json "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=$SLAT&lon=$SLON" 1 ""

# 2. aviationweather.gov
AW="https://aviationweather.gov/api/data"
WIDS="KO26,KBIH,KNID,KEDW"
SIDS="LSMM,LSMA,LSZC,LSZA,LSZL,LSME,LSZH,LIMC"
for k in W:$WIDS S:$SIDS; do
  p=${k%%:*}; ids=${k#*:}
  fetch AviationWeather/metar-$p.json "$AW/metar?ids=$ids&format=json" 0 ""
  fetch AviationWeather/metar-$p.txt  "$AW/metar?ids=$ids&format=raw" 0 ""
  fetch AviationWeather/taf-$p.json   "$AW/taf?ids=$ids&format=json" 0 ""
  fetch AviationWeather/taf-$p.txt    "$AW/taf?ids=$ids&format=raw" 0 ""
  fetch AviationWeather/stationinfo-$p.json "$AW/stationinfo?ids=$ids&format=json" 0 ""
done
fetch AviationWeather/metar-bbox-W.json "$AW/metar?bbox=36,-119,37,-117.5&format=json" 0 ""

# 3. NWS api.weather.gov (the ~300 KB gridpoint forecast is deliberately not recorded)
NWS="https://api.weather.gov"
fetch NWS/points-W.json "$NWS/points/$WLAT,$WLON" 0 "" "Accept: application/geo+json"
fetch NWS/alerts-active-W.json "$NWS/alerts/active?point=$WLAT,$WLON" 0 "" "Accept: application/geo+json"
fetch NWS/stations-KBIH-observations-latest.json "$NWS/stations/KBIH/observations/latest" 0 "" "Accept: application/geo+json"

# 4. NOAA SWPC
SW="https://services.swpc.noaa.gov"
fetch SWPC/ovation_aurora_latest.json "$SW/json/ovation_aurora_latest.json" 0 ""
fetch SWPC/planetary_k_index_1m.json "$SW/json/planetary_k_index_1m.json" 0 ""
fetch SWPC/noaa-planetary-k-index-forecast.json "$SW/products/noaa-planetary-k-index-forecast.json" 0 ""

# 5. USNO one-day rise/set/transit
fetch USNO/oneday-W.json "https://aa.usno.navy.mil/api/rstt/oneday?date=$DATE&coords=$WLAT,$WLON&tz=-8" 0 ""
fetch USNO/oneday-S.json "https://aa.usno.navy.mil/api/rstt/oneday?date=$DATE&coords=$SLAT,$SLON&tz=1" 0 ""

# 6. USGS EPQS point elevation (US only)
fetch USGS/epqs-W.json "https://epqs.nationalmap.gov/v1/json?x=$WLON&y=$WLAT&units=Meters&wkid=4326" 0 ""

# 7. AWS Terrarium z12 tiles containing W and S (web-mercator tile index)
tilexy() { python3 -I -c "
import math,sys
lat,lon,z=float(sys.argv[1]),float(sys.argv[2]),12
n=2**z; x=(lon+180)/360*n; y=(1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*n
print(int(x),int(y))" "$1" "$2"; }
read -r WX WY < <(tilexy $WLAT $WLON); read -r SX SY < <(tilexy $SLAT $SLON)
fetch Terrarium/terrarium-12-$WX-$WY-W.png "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/12/$WX/$WY.png" 0 ""
fetch Terrarium/terrarium-12-$SX-$SY-S.png "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/12/$SX/$SY.png" 0 ""

# 8. Overpass: viewpoints, named peaks and waterfalls within 6 km, "out center"
OP="https://overpass-api.de/api/interpreter"
for k in "W:$WLAT:$WLON" "S:$SLAT:$SLON"; do
  IFS=: read -r p la lo <<< "$k"
  q="[out:json][timeout:25];(nwr[tourism=viewpoint](around:6000,$la,$lo);node[natural=peak][name](around:6000,$la,$lo);node[waterway=waterfall](around:6000,$la,$lo););out center;"
  fetch Overpass/overpass-$p.json "$OP" 0 "$q"
  sleep 5
done

# 9. Wikipedia and Commons geosearch (10 km, 10 results) plus Commons imageinfo for the first three files
WP="https://en.wikipedia.org/w/api.php"; CM="https://commons.wikimedia.org/w/api.php"
for k in "W:$WLAT|$WLON" "S:$SLAT|$SLON"; do
  p=${k%%:*}; c=${k#*:}; cenc=${c//|/%7C}
  fetch Wikimedia/wikipedia-geosearch-$p.json "$WP?action=query&list=geosearch&gscoord=$cenc&gsradius=10000&gslimit=10&format=json" 0 ""
  fetch Wikimedia/commons-geosearch-$p.json "$CM?action=query&list=geosearch&gscoord=$cenc&gsradius=10000&gsnamespace=6&gslimit=10&format=json" 0 ""
  fetch Wikimedia/commons-imageinfo-$p.json "$CM?action=query&generator=geosearch&ggscoord=$cenc&ggsradius=10000&ggsnamespace=6&ggslimit=3&prop=imageinfo&iiprop=url%7Cextmetadata&format=json" 0 ""
done
