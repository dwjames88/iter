#!/bin/bash
# Probe: see header. Output saved under scratchpad; prints HTTP status + excerpt.
UA="IterProbe/0.1 (data-source evaluation)"
OUT=${TMPDIR:-/tmp}/iter-probes/places
mkdir -p "$OUT"
P1="36.5785 -118.2923"; P2="46.5586 8.5610"
get(){ # name url [extra curl args]
  n=$1; u=$2; shift 2
  code=$(curl -sS -m 60 -A "$UA" -o "$OUT/$n.out" -w "%{http_code}" "$@" "$u" 2>"$OUT/$n.err") ; echo "[$n] HTTP $code  bytes=$(wc -c <"$OUT/$n.out")"; }

get reddit_search "https://www.reddit.com/search.json?q=mount+whitney+photography&limit=5"
head -c 200 "$OUT/reddit_search.out"; echo
get reddit_sub "https://www.reddit.com/r/EarthPorn/search.json?q=switzerland&restrict_sr=1&limit=3"
head -c 200 "$OUT/reddit_sub.out"; echo
get reddit_old "https://old.reddit.com/search.json?q=whitney&limit=3"
head -c 120 "$OUT/reddit_old.out"; echo
get reddit_rss "https://www.reddit.com/r/EarthPorn/search.rss?q=switzerland&restrict_sr=1&limit=3"
head -c 200 "$OUT/reddit_rss.out"; echo
get reddit_oauth "https://oauth.reddit.com/api/v1/me"
head -c 150 "$OUT/reddit_oauth.out"; echo
