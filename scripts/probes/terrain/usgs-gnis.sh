#!/bin/zsh
# USGS National Map Gazetteer (GNIS) ArcGIS REST: layers + nearby features
UA="IterProbe/0.1 (data-source evaluation)"
B=https://carto.nationalmap.gov/arcgis/rest/services/geonames/MapServer
curl -sS -m 60 -A "$UA" "$B?f=json" | python3 -I -c "import json,sys;d=json.load(sys.stdin);print([ (l['id'],l['name']) for l in d['layers']][:15])"
curl -sS -m 60 -A "$UA" -G "$B/5/query" --data-urlencode 'where=1=1' --data-urlencode 'geometry={"x":-118.2923,"y":36.5785,"spatialReference":{"wkid":4326}}' --data-urlencode geometryType=esriGeometryPoint --data-urlencode inSR=4326 --data-urlencode distance=3000 --data-urlencode units=esriSRUnit_Meter --data-urlencode 'outFields=*' --data-urlencode returnGeometry=false --data-urlencode resultRecordCount=5 --data-urlencode f=json | python3 -I -c "import sys,json;d=json.load(sys.stdin);print([f[\"attributes\"][\"gaz_name\"]+\"/\"+f[\"attributes\"][\"gaz_featureclass\"] for f in d[\"features\"]])"
