#!/bin/bash
# NASA FIRMS: API requires MAP_KEY (free, needs sign-up) -> expect 400/401 Invalid MAP_KEY.
UA='IterProbe/0.1 (data-source evaluation)'
curl -sS -m 60 -A "$UA" -w ' [HTTP %{http_code}]\n' "https://firms.modaps.eosdis.nasa.gov/api/area/csv/DEMO_KEY/VIIRS_SNPP_NRT/-120,35,-117,38/1"
curl -sS -m 60 -A "$UA" -w ' [HTTP %{http_code} public CSV]\n' "https://firms.modaps.eosdis.nasa.gov/data/active_fire/suomi-npp-viirs-c2/csv/SUOMI_VIIRS_C2_USA_contiguous_and_Hawaii_24h.csv" | head -3
