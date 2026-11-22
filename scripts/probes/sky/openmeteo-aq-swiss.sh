#!/bin/bash
# Probe: openmeteo-aq-swiss
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://air-quality-api.open-meteo.com/v1/air-quality?latitude=46.5586&longitude=8.5610&hourly=aerosol_optical_depth,dust&forecast_days=2'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/openmeteo-aq-swiss.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "openmeteo-aq-swiss HTTP $code"
head -c 600 "$OUT/openmeteo-aq-swiss.out"; echo
