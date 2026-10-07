#!/bin/bash
# Prepares (and, with --publish, publishes) an Iter release. See docs/DISTRIBUTION.md.
#   scripts/release.sh 0.2.0             dry run: commits, tags and builds locally, prints the plan, publishes nothing
#   scripts/release.sh 0.2.0 --publish   the same, then pushes main and the tag and creates the GitHub Release
#   scripts/release.sh 0.2.0 --publish   (a second time, after a dry run) skips the build and just publishes it
# Stages: checks, tool, signing key, version bump, changelog, release commit and tag, build, code signature,
# notarisation (optional), zip and Ed25519 signature, feed, then the dry-run summary or the publish.
# Environment:
#   ITER_UPDATE_KEY_FILE   private signing key in a file OUTSIDE the repo (created if missing, mode 600).
#                          Default: the login Keychain item com.dwjames.iter.update-signing / ed25519.
#   ITER_SIGN_IDENTITY     re-sign with this identity, e.g. "Developer ID Application: Name (TEAMID)".
#                          Default: whatever the project's automatic signing produced.
#   ITER_ENTITLEMENTS      entitlements used for that re-sign (default App/Iter.entitlements).
#   ITER_NOTARY_PROFILE    notarytool keychain profile; if set, the app is notarised and stapled.
# Nothing here ever pushes without --publish. After the release commit, a failure prints how to undo it locally.
set -euo pipefail

REPO_SLUG="dwjames88/iter"
KEY_SERVICE="com.dwjames.iter.update-signing"
KEY_ACCOUNT="ed25519"

usage() { sed -n "2,15p" "$0" | sed 's/^# \{0,1\}//'; }

VERSION=""; PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; usage >&2; exit 2 ;;
    *) if [ -n "$VERSION" ]; then echo "only one version, please" >&2; exit 2; fi; VERSION="$arg" ;;
  esac
done
[ -n "$VERSION" ] || { usage >&2; exit 2; }
VERSION="${VERSION#v}"

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
TAG="v$VERSION"
OUT="build/release/$VERSION"
START_SHA=""; COMMITTED=0; PREPARED=0

stage() { printf '\n== %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ "$COMMITTED" = 1 ] && [ "$PREPARED" = 0 ]; then
    {
      echo
      echo "The release stopped after the release commit. Nothing was pushed. To undo it locally:"
      echo "  git tag -d $TAG; git reset --hard $START_SHA"
      echo "(not run for you; it discards the release commits)"
    } >&2
  fi
}
trap on_exit EXIT

# --- semantic version helpers -------------------------------------------------------------------------------------
is_semver() { [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?$ ]]; }
# semver_cmp A B prints -1, 0 or 1. Core numbers by sort -V; a release outranks its own prereleases.
semver_cmp() {
  local a="$1" b="$2" ca cb pa pb
  ca="${a%%-*}"; cb="${b%%-*}"
  pa=""; pb=""
  [[ "$a" == *-* ]] && pa="${a#*-}"
  [[ "$b" == *-* ]] && pb="${b#*-}"
  if [ "$ca" != "$cb" ]; then
    if [ "$(printf '%s\n%s\n' "$ca" "$cb" | sort -V | tail -1)" = "$ca" ]; then echo 1; else echo -1; fi
    return
  fi
  if [ "$pa" = "$pb" ]; then echo 0
  elif [ -z "$pa" ]; then echo 1
  elif [ -z "$pb" ]; then echo -1
  elif [ "$(printf '%s\n%s\n' "$pa" "$pb" | sort -V | tail -1)" = "$pa" ]; then echo 1
  else echo -1; fi
}
yml_value() { sed -n -E "s/^[[:space:]]*$1:[[:space:]]*\"([^\"]*)\".*/\1/p" project.yml | head -1; }

# --- 1. checks ----------------------------------------------------------------------------------------------------
stage "1/11 Checks"
is_semver "$VERSION" || die "not a semantic version: $VERSION (expected MAJOR.MINOR.PATCH with an optional -prerelease)"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = main ] || die "releases are cut from main (you are on $BRANCH)"
[ -z "$(git status --porcelain)" ] || die "the working tree is not clean; commit or stash first"
for tool in xcodegen xcodebuild ditto shasum swift python3; do
  command -v "$tool" >/dev/null || die "$tool is needed but was not found"
done
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  [ -f "$OUT/release.env" ] || die "tag $TAG already exists and there is no prepared release in $OUT"
  PREPARED=1
  echo "$TAG is already prepared (found $OUT/release.env)."
else
  NEWEST=""
  while IFS= read -r t; do
    t="${t#v}"; is_semver "$t" || continue
    if [ -z "$NEWEST" ] || [ "$(semver_cmp "$t" "$NEWEST")" = 1 ]; then NEWEST="$t"; fi
  done < <(git tag -l 'v*')
  if [ -n "$NEWEST" ] && [ "$(semver_cmp "$VERSION" "$NEWEST")" != 1 ]; then
    die "$VERSION is not greater than the newest tag (v$NEWEST)"
  fi
  CURRENT="$(yml_value MARKETING_VERSION)"
  [ -n "$CURRENT" ] || die "cannot read MARKETING_VERSION from project.yml"
  if [ "$(semver_cmp "$VERSION" "$CURRENT")" = -1 ]; then die "$VERSION is lower than the current MARKETING_VERSION ($CURRENT)"; fi
  echo "Releasing $VERSION (previous tag: ${NEWEST:+v}${NEWEST:-none}; project.yml says $CURRENT)."
fi

# --- 2. the iter-release tool -------------------------------------------------------------------------------------
stage "2/11 Building iter-release"
PKG=Packages/IterUpdater
swift build --package-path "$PKG" -c release --product iter-release 2>&1 | tail -3
TOOL="$(swift build --package-path "$PKG" -c release --show-bin-path)/iter-release"
[ -x "$TOOL" ] || die "iter-release was not built"

# --- 3. signing key -----------------------------------------------------------------------------------------------
PRIVATE_KEY=""
load_private_key() {
  local f real dir
  if [ -n "${ITER_UPDATE_KEY_FILE:-}" ]; then
    f="$ITER_UPDATE_KEY_FILE"
    dir="$(dirname "$f")"
    [ -d "$dir" ] || die "the folder for ITER_UPDATE_KEY_FILE does not exist: $dir"
    real="$(cd "$dir" && pwd -P)/$(basename "$f")"
    case "$real" in "$ROOT"/*) die "ITER_UPDATE_KEY_FILE ($real) is inside the repo; keep the private key outside it" ;; esac
    if [ -f "$f" ]; then
      PRIVATE_KEY="$(tr -d '[:space:]' < "$f")"
      echo "Signing key: file $real"
    else
      echo "Signing key: generating a new one in $real"
      local pair; pair="$("$TOOL" keygen)"
      PRIVATE_KEY="$(printf '%s' "$pair" | python3 -c 'import json,sys;print(json.load(sys.stdin)["privateKey"])')"
      ( umask 077; printf '%s\n' "$PRIVATE_KEY" > "$f" ); chmod 600 "$f"
    fi
  else
    if PRIVATE_KEY="$(security find-generic-password -s "$KEY_SERVICE" -a "$KEY_ACCOUNT" -w 2>/dev/null)" && [ -n "$PRIVATE_KEY" ]; then
      echo "Signing key: login Keychain ($KEY_SERVICE / $KEY_ACCOUNT)"
    else
      echo "Signing key: none in the login Keychain; generating one and storing it as $KEY_SERVICE / $KEY_ACCOUNT"
      local pair; pair="$("$TOOL" keygen)"
      PRIVATE_KEY="$(printf '%s' "$pair" | python3 -c 'import json,sys;print(json.load(sys.stdin)["privateKey"])')"
      # security -i reads its commands from stdin, so the secret never appears in a process argument list.
      printf 'add-generic-password -U -s %s -a %s -l "Iter update signing key" -w "%s"\n' "$KEY_SERVICE" "$KEY_ACCOUNT" "$PRIVATE_KEY" | security -i
      local again; again="$(security find-generic-password -s "$KEY_SERVICE" -a "$KEY_ACCOUNT" -w 2>/dev/null || true)"
      [ "$again" = "$PRIVATE_KEY" ] || die "the key could not be read back from the Keychain; nothing has been changed"
      echo "Stored. Back it up now (docs/DISTRIBUTION.md, \"Signing keys\"): losing it means installed copies cannot verify future updates."
    fi
  fi
  [ -n "$PRIVATE_KEY" ] || die "empty signing key"
}

if [ "$PREPARED" = 0 ]; then
  stage "3/11 Signing key"
  load_private_key
  PUBLIC_KEY="$(printf '%s' "$PRIVATE_KEY" | "$TOOL" public-key)"
  YML_KEY="$(yml_value ITER_UPDATE_PUBLIC_KEY)"
  if [ -z "$YML_KEY" ]; then
    echo "project.yml has no ITER_UPDATE_PUBLIC_KEY yet; writing it (it becomes part of the release commit)."
    TMP="$(mktemp)"
    sed -E "s|^([[:space:]]*ITER_UPDATE_PUBLIC_KEY:[[:space:]]*)\"\"|\1\"$PUBLIC_KEY\"|" project.yml > "$TMP"
    cat "$TMP" > project.yml; rm -f "$TMP"
    [ "$(yml_value ITER_UPDATE_PUBLIC_KEY)" = "$PUBLIC_KEY" ] || die "could not write ITER_UPDATE_PUBLIC_KEY into project.yml"
  elif [ "$YML_KEY" != "$PUBLIC_KEY" ]; then
    die "the signing key does not match ITER_UPDATE_PUBLIC_KEY in project.yml. Installed copies trust the key in project.yml, so a different key would break updates. If the key must change, follow \"Key rollover plan\" in docs/DISTRIBUTION.md."
  else
    echo "Public key matches project.yml."
  fi

  # --- 4, 5, 6. version, changelog, commit, tag ---------------------------------------------------------------------
  START_SHA="$(git rev-parse HEAD)"
  stage "4/11 Version"
  scripts/bump.sh "$VERSION"
  stage "5/11 Changelog"
  "$TOOL" changelog-release CHANGELOG.md --version "$VERSION" --date "$(date +%F)"
  stage "6/11 Release commit and tag"
  git add project.yml CHANGELOG.md
  git commit -q -m "Release $VERSION"
  COMMITTED=1
  git tag -a "$TAG" -m "Iter $VERSION"
  echo "Committed $(git rev-parse --short HEAD) and tagged $TAG."

  # --- 7. build -------------------------------------------------------------------------------------------------------
  BUILD="$(git rev-list --count HEAD)"
  HASH="$(git rev-parse --short HEAD)"
  stage "7/11 Build (Release, build $BUILD, $HASH)"
  xcodegen generate --quiet
  mkdir -p build/release
  if ! xcodebuild -project Iter.xcodeproj -scheme Iter -configuration Release -derivedDataPath build/release/DerivedData \
      CURRENT_PROJECT_VERSION="$BUILD" ITER_GIT_COMMIT="$HASH" build -quiet > build/release/xcodebuild.log 2>&1; then
    grep -E "error:" build/release/xcodebuild.log | sort -u | head -20 >&2 || true
    die "the Release build failed (full log: build/release/xcodebuild.log)"
  fi
  BUILT="build/release/DerivedData/Build/Products/Release/Iter.app"
  [ -d "$BUILT" ] || die "the Release build produced no Iter.app"
  rm -rf "$OUT"; mkdir -p "$OUT"
  ditto "$BUILT" "$OUT/Iter.app"
  APP="$OUT/Iter.app"
  PLIST="$APP/Contents/Info.plist"
  GOT_V="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
  GOT_B="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
  [ "$GOT_V" = "$VERSION" ] && [ "$GOT_B" = "$BUILD" ] || die "the built app says $GOT_V ($GOT_B), expected $VERSION ($BUILD)"
  GOT_K="$(/usr/libexec/PlistBuddy -c 'Print :IterUpdatePublicKey' "$PLIST" 2>/dev/null || true)"
  [ "$GOT_K" = "$PUBLIC_KEY" ] || die "the built app's IterUpdatePublicKey does not match the signing key"
  echo "Built $APP: $GOT_V ($GOT_B)."

  # --- 8. code signature ----------------------------------------------------------------------------------------------
  stage "8/11 Code signature"
  if [ -n "${ITER_SIGN_IDENTITY:-}" ]; then
    echo "Re-signing with: $ITER_SIGN_IDENTITY"
    codesign --force --options runtime --timestamp --entitlements "${ITER_ENTITLEMENTS:-App/Iter.entitlements}" \
      --sign "$ITER_SIGN_IDENTITY" "$APP"
  else
    echo "Keeping the signature from the project's automatic signing (no ITER_SIGN_IDENTITY)."
  fi
  codesign --verify --strict --deep "$APP"
  echo "codesign --verify passed."
  codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "^(Identifier|Authority|TeamIdentifier|CodeDirectory)" || true

  # --- 9. notarisation ------------------------------------------------------------------------------------------------
  NOTARIZED=false
  stage "9/11 Notarisation"
  if [ -n "${ITER_NOTARY_PROFILE:-}" ]; then
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$ITER_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$OUT/notarize.zip"
    NOTARIZED=true
  else
    echo "Skipped (ITER_NOTARY_PROFILE is not set). The feed will say notarized: false."
  fi

  # --- 10. zip, signature, notes --------------------------------------------------------------------------------------
  stage "10/11 Zip and signature"
  ZIP="$OUT/Iter-$VERSION.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  SIG="$(printf '%s' "$PRIVATE_KEY" | "$TOOL" sign "$ZIP")"
  "$TOOL" verify "$ZIP" --signature "$SIG" --public-key "$PUBLIC_KEY"
  echo "Signature verifies against the public key in project.yml."
  "$TOOL" changelog-section CHANGELOG.md --version "$VERSION" > "$OUT/notes.md"
  SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
  LENGTH="$(stat -f %z "$ZIP")"

  # --- 11. feed -------------------------------------------------------------------------------------------------------
  stage "11/11 Update feed"
  MIN_OS="$(yml_value MACOSX_DEPLOYMENT_TARGET)"
  PREVIOUS=()
  [ -f updates/appcast.json ] && PREVIOUS=(--previous updates/appcast.json)
  mkdir -p updates
  "$TOOL" feed --archive "$ZIP" --version "$VERSION" --build "$BUILD" \
    --url "https://github.com/$REPO_SLUG/releases/download/$TAG/Iter-$VERSION.zip" \
    --signature "$SIG" --notes-file "$OUT/notes.md" \
    --notes-url "https://github.com/$REPO_SLUG/releases/tag/$TAG" \
    --min-os "$MIN_OS" --notarized "$NOTARIZED" ${PREVIOUS[@]+"${PREVIOUS[@]}"} --out updates/appcast.json
  cp updates/appcast.json "$OUT/appcast.json"
  git add updates/appcast.json
  git commit -q -m "Update feed for $VERSION"
  {
    printf 'VERSION=%q\nBUILD=%q\nTAG=%q\nZIP=%q\nSHA256=%q\nLENGTH=%q\nNOTARIZED=%q\n' \
      "$VERSION" "$BUILD" "$TAG" "$ZIP" "$SHA256" "$LENGTH" "$NOTARIZED"
  } > "$OUT/release.env"
  echo "Feed written to updates/appcast.json and $OUT/appcast.json; committed (the tag stays on the release commit)."
else
  # shellcheck disable=SC1090,SC1091
  source "$OUT/release.env"
  ZIP="${ZIP:?}"; NOTARIZED="${NOTARIZED:-false}"
  stage "3-11 Skipped: already prepared"
  PUBLIC_KEY="$(yml_value ITER_UPDATE_PUBLIC_KEY)"
  [ -n "$PUBLIC_KEY" ] || die "project.yml has no ITER_UPDATE_PUBLIC_KEY"
  git merge-base --is-ancestor "$TAG" HEAD || die "$TAG is not an ancestor of HEAD"
  [ -f "$ZIP" ] || die "$ZIP is missing; remove $OUT and the tag to start over"
  [ "$(shasum -a 256 "$ZIP" | awk '{print $1}')" = "$SHA256" ] || die "$ZIP has changed since it was prepared"
  SIG="$(python3 - "$OUT/appcast.json" "$VERSION" <<'PY'
import json, sys
feed = json.load(open(sys.argv[1]))
print(next(i["edSignature"] for i in feed["items"] if i["version"] == sys.argv[2]))
PY
)"
  "$TOOL" verify "$ZIP" --signature "$SIG" --public-key "$PUBLIC_KEY"
  echo "Re-verified: the zip matches the feed's signature and the public key in project.yml."
fi

# --- 12. summary or publish ---------------------------------------------------------------------------------------
PUSH_CMD="git push origin main $TAG"
GH_CMD="gh release create $TAG $OUT/Iter-$VERSION.zip $OUT/appcast.json --title \"Iter $VERSION\" --notes-file $OUT/notes.md --latest"
if [ "$PUBLISH" = 0 ]; then
  stage "Dry run complete (nothing published)"
  cat <<SUMMARY
Version      $VERSION (build $BUILD)
App          $OUT/Iter.app
Zip          $ZIP
Size         $LENGTH bytes
SHA-256      $SHA256
Notarised    $NOTARIZED
Feed         updates/appcast.json (copy: $OUT/appcast.json)
Notes        $OUT/notes.md

To publish this release, run scripts/release.sh $VERSION --publish, which does:
  $PUSH_CMD
  $GH_CMD
To undo the local release instead:
  git tag -d $TAG; git reset --hard <the commit before "Release $VERSION">
SUMMARY
  exit 0
fi

stage "Publishing $TAG"
[ -z "$(git status --porcelain)" ] || die "the working tree is not clean"
command -v gh >/dev/null || die "gh (GitHub CLI) is needed to publish"
gh auth status >/dev/null 2>&1 || die "gh is not signed in; run: gh auth login"
VIS="$(gh repo view "$REPO_SLUG" --json visibility -q .visibility)"
[ "$VIS" = PUBLIC ] || die "$REPO_SLUG is $VIS. The app downloads updates without signing in, so a private repository's release assets cannot be fetched. Make it public first (docs/DISTRIBUTION.md, \"First public pre-release\")."
git push origin main "$TAG"
gh release create "$TAG" "$ZIP" "$OUT/appcast.json" --title "Iter $VERSION" --notes-file "$OUT/notes.md" --latest
echo
echo "Published: https://github.com/$REPO_SLUG/releases/tag/$TAG"
echo "Feed:      https://github.com/$REPO_SLUG/releases/latest/download/appcast.json"
