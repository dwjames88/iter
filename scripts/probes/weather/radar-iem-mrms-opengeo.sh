#!/bin/bash
# Probe script; downloads go to scratchpad (untrusted). UA is generic.
UA="IterProbe/0.1 (data-source evaluation)"
S=${TMPDIR:-/tmp}/iter-probes/weather
mkdir -p "$S"
for u in "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/6/10/25.png" \
 "https://mesonet.agron.iastate.edu/json/radar.py?operation=list&lon=-118.29&lat=36.57&start=$(date -u -v-90M +%Y-%m-%dT%H:%MZ)&end=$(date -u +%Y-%m-%dT%H:%MZ)" \
 "https://mrms.ncep.noaa.gov/2D/ReflectivityAtLowestAltitude/" \
 "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_cref_qcd/ows?service=WMS&request=GetCapabilities" \
 "https://mapservices.weather.noaa.gov/eventdriven/rest/services/radar/radar_base_reflectivity/MapServer?f=json" \
 "https://mesonet.agron.iastate.edu/api/1/currents.json?station=KBIH&network=CA_ASOS"; do
 curl -sSL -m 60 -A "$UA" -o $S/t.out -w "HTTP %{http_code} %{content_type} %{size_download}B $u\n" "$u"; done
