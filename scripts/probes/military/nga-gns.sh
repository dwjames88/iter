#!/bin/bash
# NGA GEOnet Names Server. From the probing network every geonames.nga.mil connection TIMED OUT (not HTTP). nga.mil itself answers.
. "$(dirname "$0")/_lib.sh"
c "https://geonames.nga.mil/geonames/GNSData/" 300
c "https://geonames.nga.mil/geonames/GNSHome/services.html" 300
c "https://www.nga.mil/" 100
