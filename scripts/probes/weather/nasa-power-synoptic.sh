#!/bin/bash
# Probe script; downloads go to scratchpad (untrusted). UA is generic.
UA="IterProbe/0.1 (data-source evaluation)"
S=${TMPDIR:-/tmp}/iter-probes/weather
mkdir -p "$S"
curl -sS -m 60 -A "$UA" "https://power.larc.nasa.gov/api/temporal/hourly/point?parameters=CLOUD_AMT&community=RE&longitude=-118.29&latitude=36.57&start=20261110&end=20261111&format=JSON" -w '\nNASA POWER HTTP %{http_code}\n' | head -c 300
curl -sS -m 60 -A "$UA" "https://api.synopticdata.com/v2/stations/latest?stid=KBIH&token=none" -w '\nSynoptic (no token) HTTP %{http_code}\n'
