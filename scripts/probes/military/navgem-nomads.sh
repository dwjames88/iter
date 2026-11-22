#!/bin/bash
# NAVGEM (FNMOC) mirrored on NOAA NOMADS. FNMOC's own public site is down (503, CAC only).
. "$(dirname "$0")/_lib.sh"
D=$(date -u +%Y%m%d); B=https://nomads.ncep.noaa.gov/pub/data/nccf/com/fnmoc/prod
c "https://www.fnmoc.navy.mil/" 700
curl -sS --http1.1 -m 20 -A "$UA" "$B/" | grep -o 'href="[a-z_.0-9]*/"'
curl -sS --http1.1 -m 20 -A "$UA" "$B/navgem.$D/" | sed 's/<[^>]*>//g' | grep grib2 | tail -3
# NOTE: curl needs --http1.1 (HTTP/2 gives curl error 92 on directory pages). Body of a download is prefixed by a stray HTTP header block: scan for "GRIB".
F=$OUT/navgem_f024.grib2
curl -sS --http1.1 -m 90 -A "$UA" -o "$F" -w "HTTP %{http_code} size=%{size_download} t=%{time_total}\n" "$B/navgem.$D/navgem_${D}00f024.grib2"
python3 -I - "$F" <<'PY'
import sys,struct
d=open(sys.argv[1],'rb').read(); print("first GRIB at byte",d.find(b'GRIB'))
i=d.find(b'GRIB'); n=0
while i>=0 and i<len(d):
    L=struct.unpack('>Q',d[i+8:i+16])[0]; n+=1; i=d.find(b'GRIB',i+L)
print(n,"GRIB2 messages")
PY
