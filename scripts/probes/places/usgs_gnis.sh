#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }
# USGS GNIS via National Map ArcGIS GNIS_Names MapServer (no key). Layer 0..? discover then query by point+distance.
get gnis_meta "https://carto.nationalmap.gov/arcgis/rest/services/geonames/MapServer?f=json"
python3 -I -c "
import json;d=json.load(open('$OUT/gnis_meta.out'));print('  layers:',[(l['id'],l['name']) for l in d.get('layers',[])][:12])"
# Layer 5 = Landforms (Summit, Falls, Overlook ...). Envelope query works; distance/point form returned HTTP 400.
get gnis_q "https://carto.nationalmap.gov/arcgis/rest/services/geonames/MapServer/5/query" -G --data-urlencode "where=1=1" --data-urlencode 'geometry={"xmin":-118.37,"ymin":36.50,"xmax":-118.21,"ymax":36.66,"spatialReference":{"wkid":4326}}' --data-urlencode "geometryType=esriGeometryEnvelope" --data-urlencode "spatialRel=esriSpatialRelIntersects" --data-urlencode "outFields=gaz_name,gaz_featureclass" --data-urlencode "returnGeometry=true" --data-urlencode "outSR=4326" --data-urlencode "resultRecordCount=300" --data-urlencode "f=json"
python3 -I -c "
import json,collections;d=json.load(open('$OUT/gnis_q.out'));f=d.get('features',[]);print('  features',len(f))
print('  ',collections.Counter(x['attributes']['gaz_featureclass'] for x in f).most_common(6))
for x in [y for y in f if y['attributes']['gaz_featureclass']=='Summit'][:5]: print('  ',x['attributes']['gaz_name'],x['geometry']['points'][0])"
