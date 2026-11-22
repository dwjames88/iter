#!/bin/bash
# Design/tokens.json is the single source of truth for the design tokens.
#   scripts/tokens.sh          generate Packages/Iter/Sources/IterUI/Tokens/TokenValues.swift from Design/tokens.json
#   scripts/tokens.sh check    exit 0 if TokenValues.swift is exactly what generate would write, else 1
#   scripts/tokens.sh format   rewrite Design/tokens.json in the canonical layout
#   scripts/tokens.sh assets [dir]   write Tokens/*.colorset and AccentColor.colorset into an asset catalogue
#                                    (default build/tokens-assets; nothing in the app reads them yet)
# Set ITER_SCRATCH to build somewhere other than Packages/Iter/.build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packages/Iter"
JSON="$ROOT/Design/tokens.json"
SWIFT="$PKG/Sources/IterUI/Tokens/TokenValues.swift"
SCRATCH=()
if [ -n "${ITER_SCRATCH:-}" ]; then SCRATCH=(--scratch-path "$ITER_SCRATCH"); fi

run() { swift run --quiet ${SCRATCH[@]+"${SCRATCH[@]}"} --package-path "$PKG" iter-tokens "$@"; }

case "${1:-generate}" in
  generate) run generate --json "$JSON" --swift "$SWIFT" ;;
  check) run check --json "$JSON" --swift "$SWIFT" ;;
  format) run format --json "$JSON" ;;
  assets) run assets --json "$JSON" --out "${2:-$ROOT/build/tokens-assets}" ;;
  *) echo "usage: scripts/tokens.sh [generate|check|format|assets [dir]]" >&2; exit 2 ;;
esac
