#!/bin/zsh
# Misc endpoint probes: GNIS, GeoNames (needs username), Wikidata, OpenTopography, OSRM, Valhalla, ORS, ETOPO, DTED hosts
UA="IterProbe/0.1 (data-source evaluation)"
c(){ echo "== $1"; curl -sS -m 60 -A "$UA" -w '\nHTTP %{http_code} %{content_type} %{size_download}B\n' "$1" | head -c ${2:-500}; echo; }
c "https://carto.nationalmap.gov/arcgis/rest/services/geonames/MapServer/0/query?where=1%3D1&geometry=-118.2923,36.5785&geometryType=esriGeometryPoint&inSR=4326&distance=5000&units=esriSRUnit_Meter&outFields=*&returnGeometry=false&resultRecordCount=5&f=json" 600
c "https://carto.nationalmap.gov/arcgis/rest/services/geonames/MapServer?f=json" 300
c "http://api.geonames.org/findNearbyJSON?lat=36.5785&lng=-118.2923&username=demo" 300
c "https://www.wikidata.org/w/api.php?action=query&list=geosearch&gscoord=36.5785|-118.2923&gsradius=5000&gslimit=5&format=json" 500
c "https://portal.opentopography.org/API/globaldem?demtype=SRTMGL1&south=36.57&north=36.58&west=-118.30&east=-118.29&outputFormat=GTiff" 300
c "https://router.project-osrm.org/route/v1/driving/-118.2923,36.5785;-118.1,36.6?overview=false" 400
c "https://valhalla1.openstreetmap.de/route?json=%7B%22locations%22%3A%5B%7B%22lat%22%3A36.5785%2C%22lon%22%3A-118.2923%7D%2C%7B%22lat%22%3A36.6%2C%22lon%22%3A-118.1%7D%5D%2C%22costing%22%3A%22auto%22%7D" 400
c "https://api.openrouteservice.org/v2/directions/driving-car?start=-118.2923,36.5785&end=-118.1,36.6" 300
