# LegacyFixtureGen

A fixture and dry-run tool. Nothing else.

It contains a frozen copy of the store code from before the rebuild (the old `IterCore` and `IterData` modules, verbatim) and
`IterFixtureGen`, which runs that old code. It is never linked into the Mac or iOS app and is not a dependency of `Packages/Iter`.
Do not fix, refactor or extend the frozen sources: the old behaviour is the point. It is the only oracle for the migration fixtures
in `Packages/Iter/Tests/IterStoreTests/Fixtures`, and the only way to see a store the way the old code read it (the "before" side
of a dry run on a real store).

## Build

    swift build --package-path Tools/LegacyFixtureGen

## Regenerate the fixtures (on purpose only)

    swift run --package-path Tools/LegacyFixtureGen IterFixtureGen Packages/Iter/Tests/IterStoreTests/Fixtures

This deletes and rewrites `stores/`, `documents/` and `model-hashes.json` there. The `v4-realistic` ids and dates change on every
run, so commit the whole set together. To try it without touching the committed fixtures, give it a temp folder instead.

## Dump a store as the old code reads it

    swift run --package-path Tools/LegacyFixtureGen IterFixtureGen --dump <storeDir> <out.json>

`<storeDir>` is the folder holding `Iter.store` (+ `-wal`, `-shm`). It is never opened: the whole folder is copied to a temp
folder first. Writes `<out>.as-written.json`, `<out>.expected.json` and `<out>.schema.json`. The `expected` file is what the new
`IterStore` must reproduce, except the `updatedAt` of folders listed in `flattenedFolderIDs` (the old open sets it to "now").
Stdout shows counts only. Details of the format: `Packages/Iter/Tests/IterStoreTests/Fixtures/README.md`.
