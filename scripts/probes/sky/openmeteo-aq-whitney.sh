#!/bin/bash
# Probe: openmeteo-aq-whitney
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://air-quality-api.open-meteo.com/v1/air-quality?latitude=36.5785&longitude=-118.2923&hourly=aerosol_optical_depth,dust,pm2_5,pm10&forecast_days=2'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/openmeteo-aq-whitney.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "openmeteo-aq-whitney HTTP $code"
head -c 600 "$OUT/openmeteo-aq-whitney.out"; echo
