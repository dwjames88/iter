#!/bin/zsh
# Download official WMM2025 coefficient zip from NOAA NCEI (NGA/UK DGC model) and show header + a few lines.
UA="IterProbe/0.1 (data-source evaluation)"
S=${TMPDIR:-/tmp}/iter-probes/terrain
mkdir -p $S/wmm_x
curl -sSL -m 60 -A "$UA" -o $S/WMM2025COF.zip -w 'HTTP %{http_code} %{content_type} %{size_download}B\n' https://www.ncei.noaa.gov/sites/default/files/2024-12/WMM2025COF.zip
unzip -o -q $S/WMM2025COF.zip -d $S/wmm_x; ls -la $S/wmm_x; head -4 $S/wmm_x/WMM2025COF/WMM.COF; wc -l $S/wmm_x/WMM2025COF/WMM.COF
