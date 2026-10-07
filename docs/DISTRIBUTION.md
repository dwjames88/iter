# Distribution

How Iter gets a version number, how a release is cut, and how installed copies find and install updates. The code is in `Packages/IterUpdater/` (the updater and the `iter-release` tool), `App/Sources/Updates/` (the menu item, window and settings pane) and `scripts/`.

## Versions

- Iter uses semantic versions: `MAJOR.MINOR.PATCH`, with an optional `-prerelease` such as `1.0.0-beta.1`. It stays at **0.x** until the first signed release, which is **1.0.0**.
- `MARKETING_VERSION` in `project.yml` is the one place the version lives. It becomes `CFBundleShortVersionString` in the app. `scripts/bump.sh <version>` changes it; `scripts/release.sh` calls that for you.
- The **build number** (`CFBundleVersion`) is the number of commits on `main` at the release commit. `scripts/version.sh` prints it as xcodebuild overrides (`CURRENT_PROJECT_VERSION=<count> ITER_GIT_COMMIT=<short hash>`), and `scripts/run.sh`, `scripts/test.sh` and `scripts/release.sh` pass those to xcodebuild. Built from Xcode, the build number is **0**, so such a build never outranks a released one.
- The git short hash is stored as `IterGitCommit` in Info.plist (with `-dirty` added if tracked files have uncommitted changes). Debug builds show it next to the version in Settings ▸ Updates.
- Two builds compare by version first, then by build number.

## Cutting a release

Prerequisites: you are on `main` with a clean tree, `CHANGELOG.md` has entries under `## [Unreleased]`, and XcodeGen and Xcode are installed.

```
scripts/release.sh 0.2.0              # dry run: everything except publishing
scripts/release.sh 0.2.0 --publish    # the same, then push and create the GitHub Release
```

`release.sh` does this, in order, and stops at the first failure:

1. **Checks.** Semver argument, branch `main`, clean tree, tools present, tag `v0.2.0` does not exist yet, the version is greater than the newest `v*` tag and not lower than `MARKETING_VERSION`.
2. **Builds `iter-release`** (the helper in `Packages/IterUpdater`).
3. **Finds the signing key** (see "Signing keys"). If `project.yml` has no `ITER_UPDATE_PUBLIC_KEY` yet, the public key is written in. If it differs from the key you hold, the script stops.
4. **Bumps** `MARKETING_VERSION`.
5. **Rewrites the changelog**: the Unreleased entries move under `## [0.2.0] - <date>`. It fails if Unreleased is empty.
6. **Commits and tags**: `Release 0.2.0` (only `project.yml` and `CHANGELOG.md`) and the annotated tag `v0.2.0`.
7. **Builds** the Release app into `build/release/DerivedData` (never `build/Iter.app`) and copies it to `build/release/0.2.0/Iter.app`.
8. **Checks the code signature.** With `ITER_SIGN_IDENTITY` set, it re-signs with that identity (Hardened Runtime, the app's entitlements); otherwise it keeps what automatic signing produced.
9. **Notarises** if `ITER_NOTARY_PROFILE` is set; otherwise it says it skipped this.
10. **Zips** to `build/release/0.2.0/Iter-0.2.0.zip`, signs the zip with the Ed25519 key, checks the signature against the public key in `project.yml`, and writes the changelog section to `notes.md`.
11. **Updates the feed**: adds the release to `updates/appcast.json`, copies it to `build/release/0.2.0/appcast.json` and commits it as `Update feed for 0.2.0` (the tag stays on the release commit). It also writes `release.env` so a later `--publish` can resume.
12. **Dry run**: prints the version, build, zip path, size, SHA-256, whether it is notarised, and the exact commands a publish would run. **With `--publish`**: checks `gh auth status` and that the repository is public, runs `git push origin main v0.2.0`, then `gh release create v0.2.0 <zip> <appcast.json> --title "Iter 0.2.0" --notes-file notes.md --latest`.

The release is **not** marked as a GitHub pre-release, even for 0.x. The "latest release" URL skips pre-releases, so the feed would not be found. The 0.x number is what says "before 1.0".

Run the dry run first, open `build/release/0.2.0/Iter.app` to check it, then run `scripts/release.sh 0.2.0 --publish`. Because the tag and `release.env` already exist, the second run skips the build, re-verifies the zip's signature against the feed and the tree, and only publishes.

**Undoing a local release before publishing.** Nothing is pushed by a dry run. To discard it:

```
git tag -d v0.2.0
git reset --hard <the commit before "Release 0.2.0">
rm -rf build/release/0.2.0
```

If a step fails after the release commit, the script prints this with the right commit. It never runs it for you. Once a release is published, do not rewrite it: fix forward with a new patch version.

## The update feed

The feed is one JSON file, `appcast.json`, attached to each GitHub Release. Installed copies read:

`https://github.com/dwjames88/iter/releases/latest/download/appcast.json`

Why this URL:

- **One stable URL, one request.** GitHub redirects `latest/download/<name>` to the asset of the newest release. The app does not need to know a version or list releases.
- **No API.** It avoids the GitHub API's rate limit (60 requests an hour without signing in) and its JSON wrapper.
- **Published with the zip.** The feed is an asset of the same release as the zip, published at the same moment, so it can never point at a zip that is not there.
- **Drafts and GitHub pre-releases are invisible to it.** Nobody sees an update until you publish it as a normal release.

The copy in the repo, `updates/appcast.json`, is the history of every release and an audit trail. It is also a fallback: point a copy of Iter at it with `defaults write com.dwjames.iter IterUpdateFeedURL <url>` (for example the raw GitHub URL, or a local server). `defaults delete com.dwjames.iter IterUpdateFeedURL` goes back to the normal feed. Both URLs need the repository to be **public**.

Format (`schemaVersion` 1). Items are newest first; unknown keys are ignored, so the format can grow.

```json
{
  "schemaVersion": 1,
  "items": [
    {
      "version": "0.2.0",
      "build": 412,
      "channel": "release",
      "minimumSystemVersion": "26.0",
      "url": "https://github.com/dwjames88/iter/releases/download/v0.2.0/Iter-0.2.0.zip",
      "length": 12345678,
      "sha256": "…64 lowercase hex characters…",
      "edSignature": "…base64 Ed25519 signature over the zip…",
      "publishedAt": "2026-10-06T12:00:00Z",
      "notarized": false,
      "notes": "Markdown release notes",
      "notesURL": "https://github.com/dwjames88/iter/releases/tag/v0.2.0"
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `schemaVersion` | Format version. Always 1 for now. |
| `version` | Semantic version of the release (`CFBundleShortVersionString`). |
| `build` | Build number (`CFBundleVersion`): the commit count at the release commit. |
| `channel` | `release`. Reserved for later channels; the app asks for `release`. |
| `minimumSystemVersion` | Lowest macOS that can run it. Older Macs do not see the update. |
| `url` | Where the zip is downloaded from. |
| `length` | Size of the zip in bytes. |
| `sha256` | SHA-256 of the zip, lowercase hex. |
| `edSignature` | Ed25519 signature over the exact bytes of the zip, base64. This is the root of trust. |
| `publishedAt` | When the release was prepared, ISO 8601 (UTC). |
| `notarized` | Whether the app is notarised and stapled. |
| `notes` | Release notes in Markdown (the changelog section), shown in the update window. |
| `notesURL` | Optional link to the release page. |

## Signing keys

Updates are signed with **Ed25519** (CryptoKit). The public key is in `project.yml` as `ITER_UPDATE_PUBLIC_KEY`, which becomes `IterUpdatePublicKey` in the app's Info.plist. The private key never goes in the repo.

- **Where it lives.** `scripts/release.sh` generates the key pair the first time it runs and stores the private key in your login Keychain: generic password, service `com.dwjames.iter.update-signing`, account `ed25519`. Alternatively set `ITER_UPDATE_KEY_FILE` to a file **outside the repo** (the script refuses a path inside it; it creates the file, mode 600, if missing). The private key is held in a shell variable and piped to `iter-release` on stdin. It is never put on a command line or written into the repo.
- **Back it up.** Copy it into a password manager: `security find-generic-password -s com.dwjames.iter.update-signing -a ed25519 -w`. **If you lose it, installed copies cannot verify any future update**, because they only trust the public key they were built with. See "Key rollover plan".

What the app checks before it changes anything:

1. The download's **length** and **SHA-256** match the feed.
2. The **Ed25519 signature** over the zip verifies with the embedded public key.
3. After unzipping: exactly one app, with the **same bundle identifier**, and the **version and build** the feed promised (this stops an old genuine archive being replayed under a newer number).
4. The new app has a **valid code signature**. The team is not pinned (see "What changes at 1.0").
5. The **quarantine flag is stripped** from the new bundle.
6. The old app is swapped for the new one in a single step (`FileManager.replaceItemAt`), then Iter **relaunches**.

If any check fails nothing is installed, and the window says why.

## App Sandbox

The direct-download build runs **without the App Sandbox**. A sandboxed app cannot replace its own bundle in `/Applications`, and cannot clear the quarantine flag on a file it downloaded, so it cannot update itself. Hardened Runtime stays on. The entitlements are otherwise unchanged.

The one-time move of your data: on first launch the new build copies what the sandboxed one kept in `~/Library/Containers/com.dwjames.iter` to `~/Library/Application Support/Iter`. The store is now `Iter.store` there. The container is left in place as a backup; delete it yourself when you are happy.

An **App Store build** would turn the sandbox back on and leave out `IterUpdater`, because the App Store does the updating.

## Gatekeeper and quarantine

Current builds are signed by a free Personal Team and are **not notarised**. So:

- A friend's **first download** from GitHub is quarantined, and macOS blocks it ("Apple could not verify…"). They open **System Settings ▸ Privacy & Security**, scroll to the message about Iter and click **Open Anyway**. (macOS 15 and later removed the Control-click Open bypass.) Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Iter.app`.
- **After that**, updates are downloaded by Iter itself, so they carry no quarantine flag and open without prompts.
- **App Translocation.** An app opened straight from Downloads, or from a disk image, runs from a random read-only path and cannot replace itself. Move Iter to `/Applications` and open it from there.

## What changes at 1.0

1.0 is the first release signed with a paid Apple Developer Program membership:

- A **Developer ID Application** certificate. Set `ITER_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"` and `release.sh` re-signs with it.
- **Notarisation.** Run `xcrun notarytool store-credentials <profile>` once, then set `ITER_NOTARY_PROFILE=<profile>`. `release.sh` submits, waits, staples, and records `"notarized": true` in the feed. Downloads then open without the Gatekeeper step.
- **WeatherKit** becomes possible (it needs a paid team; see TESTING.md).
- The **team ID changes**. Updates keep working, because the trust anchor is the Ed25519 key, not the team.

## Key rollover plan

If the signing key must change (for example it leaked):

1. Ship release **N** signed with the **old** key, built with the **new** public key in `project.yml`. Installs that update to N now trust the new key.
2. From **N+1** on, sign with the new key.
3. Installs older than N must update to N first; N+1 will not verify for them.

`release.sh` stops when the key it holds differs from `project.yml`, which protects you from doing this by accident. Release N is therefore a deliberate one-off: put the new public key in `project.yml`, build the release by hand, and sign the zip with the old private key using `iter-release sign`. Treat it as its own task.

If the old key is **lost**, there is no way to ship N. Existing installs cannot auto-update, and users must download the new version manually (and pass Gatekeeper again).

## First public pre-release

1. Make sure `## [Unreleased]` in `CHANGELOG.md` says what you want users to read.
2. Make the repository public (an owner decision; the app cannot download from a private repository): `gh repo edit dwjames88/iter --visibility public --accept-visibility-change-consequences`
3. Run `scripts/release.sh 0.1.0`. This is a dry run: it commits `Release 0.1.0` and `Update feed for 0.1.0` locally, tags `v0.1.0`, builds and zips, and prints the plan. The first run creates the signing key in the login Keychain and writes the public key into `project.yml` in the release commit.
4. Check that `build/release/0.1.0/Iter.app` opens.
5. Back up the key: `security find-generic-password -s com.dwjames.iter.update-signing -a ed25519 -w`, into a password manager.
6. Run `scripts/release.sh 0.1.0 --publish`.
7. Install from the release page into `/Applications`, passing the first-launch Gatekeeper step. From then on **Iter ▸ Check for Updates…** works.
8. For the next release, add notes under Unreleased and run `scripts/release.sh 0.2.0 --publish`.

## Troubleshooting

- **"Feed unavailable" or a 404.** The repository is private, or there is no published release yet. Open the feed URL in a browser; it should download JSON. Drafts and pre-releases do not count.
- **"Can't install" messages.** The window gives the reason: the app is running from a translocated path (move it to `/Applications` and reopen), the app or its folder is not writable (an admin-owned `/Applications` copy; reinstall it yourself), the app is sandboxed (an App Store or sandboxed build cannot self-update), or no update key is embedded (a build made before the first release).
- **"Signature invalid" or "hash mismatch".** The zip does not match the feed, or the key changed. Nothing was installed. Rebuild the release, or see "Key rollover plan".
- **Translocation.** See "Gatekeeper and quarantine".
- **Test the updater locally, without GitHub:** `scripts/updater-e2e.sh`. It builds a throwaway app at 1.0.0 and 2.0.0, serves a signed feed from 127.0.0.1, lets 1.0.0 update itself hidden, and checks the result, plus a second run with a wrong signature that must install nothing. It touches only a temp folder (`ITER_E2E_KEEP=1` keeps it) and uses no Keychain.
