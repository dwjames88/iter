#!/bin/zsh
# Probe script (IterProbe/0.1). Prints HTTP status + short excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
SCRATCH=${TMPDIR:-/tmp}/iter-probes/terrain
mkdir -p $SCRATCH
c(){ echo "== $1"; curl -sS -m 60 -A "$UA" -w "\nHTTP %{http_code} %{content_type} %{size_download}B\n" "$1" | head -c ${2:-500}; echo; }

c "https://re.jrc.ec.europa.eu/api/printhorizon?lat=36.5785&lon=-118.2923&outputformat=json" 700
c "https://re.jrc.ec.europa.eu/api/printhorizon?lat=46.5586&lon=8.5610&outputformat=json" 700
c "https://re.jrc.ec.europa.eu/api/printhorizon?lat=-33.8568&lon=151.2153&outputformat=json" 300  # Sydney, global test
c "https://re.jrc.ec.europa.eu/api/printhorizon?lat=64.0&lon=-19.0&outputformat=json" 300  # Iceland
