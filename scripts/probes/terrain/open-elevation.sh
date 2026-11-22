#!/bin/zsh
# Probe script (IterProbe/0.1). Prints HTTP status + short excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
SCRATCH=${TMPDIR:-/tmp}/iter-probes/terrain
mkdir -p $SCRATCH
c(){ echo "== $1"; curl -sS -m 60 -A "$UA" -w "\nHTTP %{http_code} %{content_type} %{size_download}B\n" "$1" | head -c ${2:-500}; echo; }

c "https://api.open-elevation.com/api/v1/lookup?locations=36.5785,-118.2923|46.5586,8.5610"
