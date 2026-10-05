#!/bin/bash
# Round trip between the Swift token registry and the design-tool files.
#   scripts/tokens.sh            export: TokenValues.swift -> Design/tokens.json + Assets.xcassets/Tokens
#   scripts/tokens.sh import     import: Design/tokens.json -> TokenValues.swift
# Set ITER_SCRATCH to build somewhere other than Packages/IterKit/.build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packages/IterKit"
JSON="$ROOT/Design/tokens.json"
ASSETS="$ROOT/App/Resources/Assets.xcassets"
SWIFT="$PKG/Sources/IterDesign/TokenValues.swift"
SCRATCH=()
if [ -n "${ITER_SCRATCH:-}" ]; then SCRATCH=(--scratch-path "$ITER_SCRATCH"); fi

case "${1:-export}" in
  export) swift run ${SCRATCH[@]+"${SCRATCH[@]}"} --package-path "$PKG" iter-tokens export --json "$JSON" --assets "$ASSETS" ;;
  import) swift run ${SCRATCH[@]+"${SCRATCH[@]}"} --package-path "$PKG" iter-tokens import --json "$JSON" --swift "$SWIFT" ;;
  *) echo "usage: scripts/tokens.sh [export|import]" >&2; exit 2 ;;
esac
