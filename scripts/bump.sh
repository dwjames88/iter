#!/bin/bash
# Sets the app's version: rewrites MARKETING_VERSION in project.yml, the one place the version lives.
#   scripts/bump.sh 0.2.0          (MAJOR.MINOR.PATCH, optionally with a -prerelease like 1.0.0-beta.1)
# Prints "old -> new". It does not commit; scripts/release.sh calls it and makes the release commit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/project.yml"
NEW="${1:-}"
if [ -z "$NEW" ] || [ "$#" -ne 1 ]; then echo "usage: scripts/bump.sh <version>   (for example 0.2.0)" >&2; exit 2; fi
if ! [[ "$NEW" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
  echo "not a semantic version: $NEW (expected MAJOR.MINOR.PATCH with an optional -prerelease)" >&2; exit 2
fi
COUNT="$(grep -cE '^[[:space:]]*MARKETING_VERSION:' "$FILE" || true)"
if [ "$COUNT" != 1 ]; then echo "project.yml must contain exactly one MARKETING_VERSION line (found $COUNT)" >&2; exit 1; fi
OLD="$(sed -n -E 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"([^"]*)".*/\1/p' "$FILE")"
if [ -z "$OLD" ]; then echo "MARKETING_VERSION in project.yml is not a quoted string" >&2; exit 1; fi
TMP="$(mktemp)"
sed -E "s/^([[:space:]]*MARKETING_VERSION:[[:space:]]*)\"[^\"]*\"/\1\"$NEW\"/" "$FILE" > "$TMP"
cat "$TMP" > "$FILE"; rm -f "$TMP"
echo "$OLD -> $NEW"
