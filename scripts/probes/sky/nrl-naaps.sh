#!/bin/bash
# NRL Monterey NAAPS aerosol page
curl -sS -m 60 -A 'IterProbe/0.1 (data-source evaluation)' -o /dev/null -w 'nrlmry aerosol HTTP %{http_code} -> %{redirect_url}\n' "https://www.nrlmry.navy.mil/aerosol/"
