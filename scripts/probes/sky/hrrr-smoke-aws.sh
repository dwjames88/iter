#!/bin/bash
# NOAA HRRR smoke fields on AWS open data (GRIB2, byte-range via .idx). MASSDEN = near-surface smoke, COLMD = column smoke.
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}; mkdir -p "$OUT"
UA='IterProbe/0.1 (data-source evaluation)'; D=$(date -u +%Y%m%d)
B=https://noaa-hrrr-bdp-pds.s3.amazonaws.com/hrrr.$D/conus/hrrr.t12z.wrfsfcf00.grib2
curl -sS -m 60 -A "$UA" -o "$OUT/hrrr.idx" -w 'idx HTTP %{http_code}\n' $B.idx
grep -E 'MASSDEN|COLMD|AOTK' "$OUT/hrrr.idx"
S=$(grep MASSDEN "$OUT/hrrr.idx"|cut -d: -f2); E=$(grep -A1 MASSDEN "$OUT/hrrr.idx"|tail -1|cut -d: -f2)
curl -sS -m 60 -A "$UA" -r $S-$((E-1)) -o "$OUT/massden.grib2" -w "range HTTP %{http_code} %{size_download}B\n" $B; head -c 4 "$OUT/massden.grib2"; echo
