#!/bin/zsh
# Probe script (IterProbe/0.1). Prints HTTP status + short excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
SCRATCH=${TMPDIR:-/tmp}/iter-probes/terrain
mkdir -p $SCRATCH
c(){ echo "== $1"; curl -sS -m 60 -A "$UA" -w "\nHTTP %{http_code} %{content_type} %{size_download}B\n" "$1" | head -c ${2:-500}; echo; }

c "https://epqs.nationalmap.gov/v1/json?x=-118.2923&y=36.5785&units=Meters&wkid=4326&includeDate=false"
c "https://epqs.nationalmap.gov/v1/json?x=8.5610&y=46.5586&units=Meters&wkid=4326"  # expected failure: US only
