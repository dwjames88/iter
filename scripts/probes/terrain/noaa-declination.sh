#!/bin/zsh
# Probe script (IterProbe/0.1). Prints HTTP status + short excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
SCRATCH=${TMPDIR:-/tmp}/iter-probes/terrain
mkdir -p $SCRATCH
c(){ echo "== $1"; curl -sS -m 60 -A "$UA" -w "\nHTTP %{http_code} %{content_type} %{size_download}B\n" "$1" | head -c ${2:-500}; echo; }

# NOAA NCEI requires a key (free registration -> owner sign-up). Without key:
c "https://www.ngdc.noaa.gov/geomag-web/calculators/calculateDeclination?lat1=36.5785&lon1=-118.2923&resultFormat=json"
# Set NOAA_KEY env var to test with a real key:
[ -n "$NOAA_KEY" ] && c "https://www.ngdc.noaa.gov/geomag-web/calculators/calculateDeclination?lat1=36.5785&lon1=-118.2923&key=$NOAA_KEY&resultFormat=json" 900
