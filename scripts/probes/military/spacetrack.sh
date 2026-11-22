#!/bin/bash
# Space-Track.org: requires account. Only checks unauthenticated behaviour.
. "$(dirname "$0")/_lib.sh"
c "https://www.space-track.org/basicspacedata/query/class/gp/NORAD_CAT_ID/25544/format/json" 300
c "https://www.space-track.org/" 200
