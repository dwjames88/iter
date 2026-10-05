#!/bin/bash
# Syncs App/Resources/Localizable.xcstrings with every string the app's Swift code uses (Xcode's editor does this
# on build; xcodebuild only extracts). Run after a build: scripts/strings.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="${ITER_DD:-$ROOT/build/DerivedData}"
FILES=()
while IFS= read -r f; do FILES+=(--stringsdata "$f"); done < <(find "$DD/Build/Intermediates.noindex/Iter.build" -name "*.stringsdata" -path "*Iter.build/Debug/Iter.build*")
xcrun xcstringstool sync "$ROOT/App/Resources/Localizable.xcstrings" "${FILES[@]}"
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(len(d['strings']),'strings in the catalog')" "$ROOT/App/Resources/Localizable.xcstrings"
