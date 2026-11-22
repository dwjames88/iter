#!/bin/zsh
# Copernicus DEM on AWS (no key): HEAD + 16 KB range read of COG header. Value decode not done (needs TIFF reader).
UA="IterProbe/0.1 (data-source evaluation)"
for u in https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N36_00_W119_00_DEM/Copernicus_DSM_COG_10_N36_00_W119_00_DEM.tif https://copernicus-dem-90m.s3.amazonaws.com/Copernicus_DSM_COG_30_N46_00_E008_00_DEM/Copernicus_DSM_COG_30_N46_00_E008_00_DEM.tif; do
 curl -sSI -m 60 -A "$UA" $u | egrep -i '^HTTP|content-length|last-mod'
 curl -sS -m 60 -A "$UA" -r 0-63 -w '\nrange HTTP %{http_code}\n' $u | head -c 120 | xxd | head -2
done
