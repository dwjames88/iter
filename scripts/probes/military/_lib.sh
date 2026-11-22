# shared helper: c URL [maxbytes]
UA='IterProbe/0.1 (data-source evaluation)'
OUT=${TMPDIR:-/tmp}/iter-probes/military
mkdir -p "$OUT"; TMPF="$OUT/o.$$.txt"
c(){ echo "### $1"; rm -f "$TMPF"; curl -sSL --connect-timeout 10 -m 25 -A "$UA" -o "$TMPF" -w "HTTP %{http_code} ct=%{content_type} size=%{size_download} final=%{url_effective}\n" "$1" || echo "CURL FAIL rc=$?"; head -c ${2:-400} "$TMPF"; echo; }
