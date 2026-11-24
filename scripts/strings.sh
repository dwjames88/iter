#!/bin/bash
# Syncs the string catalog (Packages/Iter/Sources/IterUI/Resources/Localizable.xcstrings, the one catalog the apps ship) with
# every string the IterUI Swift code uses. Xcode's editor does this on build; xcodebuild only extracts. Run after a Mac build:
#   scripts/strings.sh
# Environment: ITER_DD = derived data of that build (default build/DerivedData), ITER_CATALOG = another catalog file to sync.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="${ITER_DD:-$ROOT/build/DerivedData}"
CATALOG="${ITER_CATALOG:-$ROOT/Packages/Iter/Sources/IterUI/Resources/Localizable.xcstrings}"
FILES=()
while IFS= read -r f; do FILES+=(--stringsdata "$f"); done < <(find "$DD/Build/Intermediates.noindex" -name "*.stringsdata" -path "*IterUI*.build/*" 2>/dev/null)
[ "${#FILES[@]}" -gt 0 ] || { echo "No IterUI .stringsdata under $DD (build the Mac app first: scripts/run.sh)" >&2; exit 1; }
xcrun xcstringstool sync "$CATALOG" "${FILES[@]}"
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(len(d['strings']),'strings in the catalog')" "$CATALOG"
