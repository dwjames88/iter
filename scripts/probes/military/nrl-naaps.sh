#!/bin/bash
. "$(dirname "$0")/_lib.sh"
c "https://www.nrlmry.navy.mil/aerosol/" 200
c "https://www.nrlmry.navy.mil/aerosol-bin/aerosol_web_data.cgi" 200
c "https://science.nrlmry.navy.mil/geoips/tcweb/" 100
c "https://www.nrlmry.navy.mil/tc-bin/tc_home2.cgi" 100
