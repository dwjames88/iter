#!/bin/bash
# Colorado School of Mines EOG VIIRS annual composites: expect redirect to eogauth login.
curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -L -o /dev/null -w 'EOG HTTP %{http_code} final=%{url_effective}\n' "https://eogdata.mines.edu/nighttime_light/annual/v22/2024/" | cut -c1-200
