#!/bin/bash
# CelesTrak GP (public mirror of 18th SDS / Space Force catalog). No key.
. "$(dirname "$0")/_lib.sh"
c "https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=json" 700
c "https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=tle" 300
c "https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=tle" 200
c "https://celestrak.org/NORAD/elements/gp.php?GROUP=starlink&FORMAT=tle" 200
c "https://celestrak.org/NORAD/elements/supplemental/sup-gp.php?SOURCE=SpaceX-E&FORMAT=json" 200
