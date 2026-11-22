# Store fixtures

Everything here was written by the OLD code (`Legacy/IterKit`, module `IterData`) by the `IterFixtureGen` tool. Nothing was
copied from a real user store. These are the oracle for the rebuild's Phase 1: the new `IterStore` must open each store and
produce the same data as `expected.json`.

## Layout

| Path | What it is | Written by |
| --- | --- | --- |
| `stores/v1/` | A schema V1 store (places, trips, stops; no folders). | Frozen `IterSchemaV1` classes, `Schema(versionedSchema:)`, no migration plan. Fixed UUIDs and dates. |
| `stores/v2/` | A V2 store: folders (trips, locations), filing, a pinned trip, one **nested** trip folder. | Frozen `IterSchemaV2` classes. Fixed UUIDs and dates. |
| `stores/v3/` | A V3 store: folder pins, place pins, one nested location folder, one stop whose `place` is nil (broken link). | Frozen `IterSchemaV3` classes. Fixed UUIDs and dates. |
| `stores/v4-realistic/` | A photographer's library: 4 trips (one 5 days with 9 stops, drive notes, two `eveningBefore` transfers), a filed trip, a pinned trip, a pinned trip folder, location folders, a pinned place, saved curated spots, an edited curated spot, own spots, Apple Maps places (`externalID`), unicode/emoji. | The OLD live API: `IterSchema.makeContainer(url:)` + `IterStore(container:)` and its public methods (`createTrip`, `addStop`, `setDriveNote`, `setTransferTiming`, `setSaved`, `createUserSpot`, `editPlace`, `createFolder`, `moveTrips`, `movePlaces`, `setPinned`...). IDs and `updatedAt`/`pinnedAt` come from the API (random / now). |
| `stores/<name>/Iter.store` (+ `-wal`, `-shm`) | The SwiftData SQLite store, named as on the Mac. Copy the whole folder before opening: opening a store may write to it. | see above |
| `stores/<name>/as-written.json` | The store read back BEFORE any migration (V1-V3 with the frozen schema and no migration plan; V4 with the live classes). Fields that version does not have are absent. | `IterFixtureGen` |
| `stores/<name>/expected.json` | The oracle: a copy of the fixture opened with the OLD current code (`IterSchema.makeContainer(url:)` then `IterStore(container:)`, which migrates to V4 and runs `flattenFolders`), then read back. | `IterFixtureGen` |
| `model-hashes.json` | Model identity evidence: per `IterSchemaV1...V4` the Core Data model SwiftData builds (`NSManagedObjectModel.makeManagedObjectModel(for:)`): entity name, `managedObjectClassName`, `versionHash`, attributes, relationships; and for every store the `NSStoreModelVersionHashes` / `NSStoreModelVersionIdentifiers` metadata before migration and after the old open. | `IterFixtureGen` |
| `documents/*.iter` | One `.iter` v1 document per trip in `v4-realistic`: the exact bytes of `TripDocument(trip: record.plan, exportedAt: 2026-09-21T14:13:20Z).encoded()`, named with `TripDocument.suggestedFileName(forTripNamed:)`. | Old `TripDocument` |
| `documents/older-shape/*.iter` | **Synthesized**, not written by an old build: two of the files above with every `driveNote` key (per stop) and the `transferTimings` key (trip) removed at JSON level, everything else unchanged. This is the shape of v1 files exported before drive notes and transfer timings existed. The old `TripDocument.decode` reads them with those fields defaulted (`""`, `[:]`). | `IterFixtureGen` |

Each document was checked to decode with the old `TripDocument.decode` and to equal the plan it came from; each older-shape file
was checked to decode to that plan with `driveNote = ""` and `transferTimings = [:]`.

## Dump format (`expected.json`, `as-written.json`)

Pretty JSON with sorted keys. Dates are JSON numbers: `timeIntervalSinceReferenceDate` (full Double precision). UUIDs are
uppercase strings. Arrays are sorted by `id`, except a trip's `stopIDs`, which are in `orderedStops` order (day, sortOrder, id).

- `fixture`, `writtenSchemaVersion` (`"1.0.0"`...), `generator` (notes), `flattenedFolderIDs` (folders that were nested in the written store).
- `folders`: every stored field (`id`, `name`, `kindRaw`, `sortOrder`, `createdAt`, `updatedAt`, `isPinned`, `pinnedAt`) plus `parentID`, sorted `tripIDs`, `placeIDs`.
- `places`: every stored field plus `folderID`, sorted `stopIDs`.
- `trips`: every stored field (incl. `transferTimingsRaw`) plus `folderID`, `stopIDs` and, in `expected.json` only, `plan`: the old `TripPlan` from `record.plan`, encoded like `TripDocument.encoded()` (sorted keys, ISO-8601 dates). A stop whose place is nil is absent from `plan.stops`.
- `stops`: every stored field plus `tripID`, `placeID` (null for the broken link in `v3`).

In `expected.json` every `parentID` is null: the old open flattened nested folders (the child keeps its content, loses its parent,
each kind is renumbered 0, 1, 2... with a child right after its former parent). `flattenFolders` also sets the flattened folders'
`updatedAt` to the time of generation, so those values (the ids in `flattenedFolderIDs`) change on every regeneration and a
comparison should skip them.

## Regenerating

From the worktree root:

    swift run --package-path Legacy/IterKit IterFixtureGen Packages/Iter/Tests/IterStoreTests/Fixtures

It deletes and rewrites `stores/`, `documents/` and `model-hashes.json` (this README is left alone). The tool uses
`@testable import IterData` (debug builds enable testability) to reach the frozen `internal` classes. It works in a temp folder and
copies finished stores out once every container is released.

V1-V3 stores are written with fixed UUIDs and dates, so `as-written.json` and `expected.json` reproduce exactly (apart from the
flattened folders' `updatedAt` above); the SQLite files themselves are not byte-identical between runs. **`v4-realistic` IDs and
dates change on every regeneration** (the old API assigns random IDs and `.now`), as do its dump and the documents, which embed
those IDs. Regenerate only on purpose, and commit the whole set together.
