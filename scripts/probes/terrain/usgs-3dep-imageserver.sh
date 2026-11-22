#!/bin/zsh
# USGS 3DEP ImageServer: identify (point) + exportImage (small float32 grid around Whitney)
UA="IterProbe/0.1 (data-source evaluation)"
SCRATCH=${TMPDIR:-/tmp}/iter-probes/terrain
mkdir -p $SCRATCH
B=https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer
curl -sS -m 60 -A "$UA" -w '\nHTTP %{http_code}\n' -G "$B/identify" --data-urlencode 'geometry={"x":-118.2923,"y":36.5785,"spatialReference":{"wkid":4326}}' --data-urlencode geometryType=esriGeometryPoint --data-urlencode returnGeometry=false --data-urlencode f=json | head -c 400; echo
curl -sS -m 60 -A "$UA" -w '\nHTTP %{http_code}\n' -G "$B/getSamples" --data-urlencode 'geometry={"points":[[-118.2923,36.5785],[8.561,46.5586]],"spatialReference":{"wkid":4326}}' --data-urlencode geometryType=esriGeometryMultipoint --data-urlencode returnFirstValueOnly=true --data-urlencode f=json | head -c 500; echo
# 21x21 float32 grid, ~0.01 deg box (~1 km), 4326
curl -sS -m 60 -A "$UA" -o $SCRATCH/3dep_grid.tif -w 'exportImage HTTP %{http_code} %{content_type} %{size_download}B\n' -G "$B/exportImage" --data-urlencode bbox=-118.2973,36.5735,-118.2873,36.5835 --data-urlencode bboxSR=4326 --data-urlencode imageSR=4326 --data-urlencode size=21,21 --data-urlencode format=tiff --data-urlencode pixelType=F32 --data-urlencode interpolation=RSP_BilinearInterpolation --data-urlencode f=image
file $SCRATCH/3dep_grid.tif
