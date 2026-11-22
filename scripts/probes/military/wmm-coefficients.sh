#!/bin/bash
# WMM2025 coefficient file (compute declination locally; avoids the API key)
. "$(dirname "$0")/_lib.sh"
c "https://www.ncei.noaa.gov/products/world-magnetic-model/wmm-coefficients" 100
c "https://www.ncei.noaa.gov/sites/default/files/2025-01/WMM2025COF.zip" 0
