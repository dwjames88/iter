#!/bin/bash
# NASA LAADS VNP46A4 (Black Marble annual): file listing API is open, file download redirects to Earthdata login.
UA='IterProbe/0.1 (data-source evaluation)'
curl -sS -m 60 -A "$UA" "https://ladsweb.modaps.eosdis.nasa.gov/api/v2/content/details?products=VNP46A4&temporalRanges=2024-001&regions=%5BBBOX%5DW-119,N37,E-118,S36" | head -c 300; echo
curl -sS -m 60 -A "$UA" -o /dev/null -w 'download (no token) HTTP %{http_code} -> %{redirect_url}\n' "https://ladsweb.modaps.eosdis.nasa.gov/api/v2/content/archives/VNP46A4.A2024001.h06v05.002.2025161223017.h5"
