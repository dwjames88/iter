#!/bin/bash
# WMM declination via NOAA NCEI (military-origin model by NGA+UK DGC, hosted by NOAA)
. "$(dirname "$0")/_lib.sh"
c "https://www.ngdc.noaa.gov/geomag-web/calculators/calculateDeclination?lat1=36.5785&lon1=-118.2923&model=WMM&startYear=2026&startMonth=11&startDay=22&resultFormat=json" 600
c "https://www.ngdc.noaa.gov/geomag-web/calculators/calculateDeclination?lat1=36.5785&lon1=-118.2923&model=WMM&startYear=2026&startMonth=11&startDay=22&resultFormat=json" 300
c "https://www.ngdc.noaa.gov/geomag/WMM/data/WMM2025/WMM2025COF.zip" 100
c "https://www.ncei.noaa.gov/products/world-magnetic-model" 200
# Keyed call: export NOAA_GEOMAG_KEY (free, self-registered) to test
[ -n "$NOAA_GEOMAG_KEY" ] && c "https://www.ngdc.noaa.gov/geomag-web/calculators/calculateDeclination?lat1=36.5785&lon1=-118.2923&model=WMM&startYear=2026&startMonth=11&startDay=22&key=$NOAA_GEOMAG_KEY&resultFormat=json" 800
