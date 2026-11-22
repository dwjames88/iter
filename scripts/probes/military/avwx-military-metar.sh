#!/bin/bash
# aviationweather.gov Data API: METAR/TAF for military airfields. Military data redistributed by NOAA AWC. No key.
. "$(dirname "$0")/_lib.sh"
c "https://aviationweather.gov/api/data/metar?ids=KNID,KNFL,KEDW,KLSV,ETAR,LIPA&format=json" 1500
c "https://aviationweather.gov/api/data/taf?ids=KNFL,KEDW,ETAR,LIPA&format=raw" 1500
c "https://aviationweather.gov/api/data/stationinfo?ids=KNID,ETAR&format=json" 600
c "https://aviationweather.gov/api/data/metar?bbox=36,-119,37,-117.5&format=raw" 600
