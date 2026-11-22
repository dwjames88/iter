#!/bin/bash
# Probe: usno-oneday
OUT=${OUT:-${TMPDIR:-/tmp}/iter-probes/sky}
mkdir -p "$OUT"
URL='https://aa.usno.navy.mil/api/rstt/oneday?date=2026-11-22&coords=36.5785,-118.2923&tz=-8'
code=$(curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o "$OUT/usno-oneday.out" -w '%{http_code} %{size_download}B %{content_type}' "$URL")
echo "usno-oneday HTTP $code"
head -c 600 "$OUT/usno-oneday.out"; echo
