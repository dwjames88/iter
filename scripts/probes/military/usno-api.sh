#!/bin/bash
# USNO AA API: sun/moon rise-set-transit, phases, celnav, seasons, eclipses. No key.
. "$(dirname "$0")/_lib.sh"
c "https://aa.usno.navy.mil/api/rstt/oneday?date=2026-11-22&coords=36.5785,-118.2923&tz=-8" 1800
c "https://aa.usno.navy.mil/api/rstt/oneday?date=2026-11-22&coords=46.5586,8.5610&tz=1" 200
c "https://aa.usno.navy.mil/api/moon/phases/date?date=2026-11-22&nump=4" 300
c "https://aa.usno.navy.mil/api/siderealtime?date=2026-11-22&time=08:00:00&coords=36.5785,-118.2923&reps=1&intv_mag=1&intv_unit=hours" 400
c "https://aa.usno.navy.mil/api/seasons?year=2026" 200
c "https://aa.usno.navy.mil/api/eclipses/solar/year?year=2027" 300
c "https://aa.usno.navy.mil/api/rstt/oneyear?coords=36.5785,-118.2923&year=2026&tz=-8" 300
