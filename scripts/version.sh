#!/bin/bash
# Prints the xcodebuild overrides that stamp a build with its place in git history:
#   CURRENT_PROJECT_VERSION=<commit count on HEAD> ITER_GIT_COMMIT=<short hash>
# The hash gets "-dirty" when tracked files have uncommitted changes. Outside a git repository it prints the
# defaults: CURRENT_PROJECT_VERSION=0 ITER_GIT_COMMIT=
#   xcodebuild ... $(scripts/version.sh) build
# See docs/DISTRIBUTION.md, "Versions".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COUNT=0
HASH=""
if git -C "$ROOT" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
  COUNT="$(git -C "$ROOT" rev-list --count HEAD)"
  HASH="$(git -C "$ROOT" rev-parse --short HEAD)"
  if ! git -C "$ROOT" diff-index --quiet HEAD -- 2>/dev/null; then HASH="$HASH-dirty"; fi
fi
echo "CURRENT_PROJECT_VERSION=$COUNT ITER_GIT_COMMIT=$HASH"
