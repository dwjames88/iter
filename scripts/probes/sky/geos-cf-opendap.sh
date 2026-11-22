#!/bin/bash
# NASA GMAO GEOS-CF forecast via GrADS Data Server (OPeNDAP-style ASCII point query). Surface PM2.5 only (no AOD in this collection).
curl -g -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -w '\nHTTP %{http_code}\n' "https://opendap.nccs.nasa.gov/dods/gmao/geos-cf/fcast/aqc_tavg_1hr_g1440x721_v1.latest.ascii?pm25_rh35_gcc[0:2][0][506][247]" | head -14
