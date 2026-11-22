#!/bin/bash
. "$(dirname "$0")/_lib.sh"
c "https://www.metoc.navy.mil/jtwc/jtwc.html" 400
c "https://www.metoc.navy.mil/jtwc/products/abpwweb.txt" 400
c "https://www.metoc.navy.mil/jtwc/rss/jtwc.rss" 400
c "https://www.nrlmry.navy.mil/TC.html" 300
c "https://www.nhc.noaa.gov/gis/" 100
