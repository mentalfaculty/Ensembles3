---
name: ensembles
description: Use when building, debugging, or migrating an app that uses the Ensembles 3 Swift sync framework (CoreDataEnsemble, SwiftDataEnsemble, CloudFileSystem, attach/sync/detach, E2-to-E3 migration, seed policy, compatibility mode, transformable-attribute sync issues).
---

# Ensembles 3

Event-sourcing Core Data / SwiftData sync framework; successor to Ensembles 2 (ObjC). Local saves are captured as events in a separate SQLite event store, exchanged through a pluggable `CloudFileSystem`, and replayed into the user's store. This skill pins the exact API and the handful of things that are easy to get wrong.

## Setup (Core Data + local folder)

The designated init is **failable** and takes a *model object*, not a URL (URL-based convenience inits also exist):

```swift
import EnsemblesLocalFile  // @_exported brings in Ensembles too

let cloud = LocalCloudFileSystem(rootDirectory: sharedFolderURL)
let ensemble = CoreDataEnsemble(
    ensembleIdentifier: "MyStore",
    persistentStoreURL: storeURL,
    managedObjectModel: model,          // NSManagedObjectModel
    managedObjectModels: nil,           // pass all model versions for versioning, else nil
    cloudFileSystem: cloud
)!                                       // returns nil if a store URL is already in use
try await ensemble.attachPersistentStore()       // seedPolicy defaults to .mergeAllData
try await ensemble.sync()
```

SwiftData: use `SwiftDataEnsemble` (factory, builds the model from `@Model` types; iOS 17+/macOS 14+).

## Core API (all async throws)

| Call | Purpose |
|------|---------|
| `attachPersistentStore(seedPolicy:)` | Register store, join the ensemble. Was E2 `leech`. |
| `sync(options:)` | One sync pass: export local, import remote, integrate. Was E2 `merge`. |
| `detachPersistentStore()` | Leave the ensemble. Was E2 `deleech`. |

Operations are serialized internally (AsyncStream); concurrent calls queue safely. `CoreDataEnsembleDelegate` is for hooks (conflict/merge lifecycle, error handling, custom global identifiers), not for driving operations. For reliable cross-device propagation, two rounds are common: `sync()` to export, then `sync()` again after peers have exported, to import.

## Seed policy

Two cases only — `mergeAllData` (default) and `excludeLocalData`. **Always recommend `mergeAllData`** (merges existing local data into the ensemble); don't present it as a decision. Use `excludeLocalData` only when intentionally discarding local data (delete the store first).

## E2 → E3 migration

- E3 reads E2 **cloud** data and event formats. The user's persistent store is untouched.
- The **local event store does NOT carry across.** First `attachPersistentStore` deletes the event-data dir and rejoins as a fresh peer (new `persistentStoreIdentifier`); cloud is source of truth. Unsynced local E2 events are lost — sync E2 to completion before upgrading.
- First attach forces a detach with `EnsembleError.cloudIdentityChanged` — expected, recover by re-attaching.
- Set `compatibilityMode: .ensembles2Compatible` while an E2 fleet still exists; it only restricts *writes* (reads handle both formats). CloudKit gotcha: E2/E3 inits can target different zones — mixed fleets must match.

## Transformable attributes (e.g. CLLocation)

A transformable attribute "syncing as nil" — one attribute empty/wrong on the receiver while everything else syncs fine — has had several distinct causes. Diagnose:

1. **E2 base64 line-wrapping (FIXED, but check the build).** Confirmed root cause of a real customer case. Ensembles 2's ObjC exporter base64-encodes blobs in 64-column CRLF-wrapped lines; E3's import used to decode with strict `Data(base64Encoded:)`, which rejects the line breaks and returned nil — dropping the value at import, before the transformer ran. Symptom is exactly "only the transformable (a `["data", base64]` value) nils; plain-string siblings are fine; NO `Failed to retrieve value transformer` log." Affects E2→E3 only (E3 writes unwrapped base64; E2 reads leniently). Fixed by `.ignoreUnknownCharacters` at `JSONEventImport.swift`. If a customer hits this, get them on a build with the fix and retest.
2. **Transformer not registered on the integrating device.** If `setLoggingLevel(.verbose)` shows `Failed to retrieve value transformer:`, the named transformer wasn't registered before the store loaded. Register a named `@objc(YourName)` `NSSecureUnarchiveFromDataTransformer` subclass (stored class in `allowedTopLevelClasses`) before the CD stack loads, on every device. If that log line is ABSENT, registration is not the cause.
3. **`awakeFromInsert` overwriting synced content.** A footgun, not the usual cause — see below. Only relevant if the model class assigns current-device content in `awakeFromInsert`.
4. **Identity / model / cloud data.** global-id/dedup, entity-hash mismatch, or the value genuinely absent from the exported event — verify the raw event on the sending side.

When in doubt, get the actual `.cdeevent` cloud file and inspect what's really in it (do not trust synthetic reproductions — the base64-wrapping bug was invisible to fixtures built with Swift's `base64EncodedString()`).

## awakeFromInsert and the integration context

Ensembles integrates remote events by inserting/updating objects in its own context, and Core Data fires `awakeFromInsert()` on those objects just like for app-created ones. Any default-content assignment in `awakeFromInsert()` (current location, timestamp, status) therefore runs during integration and *can* overwrite a synced value. (Note: the integrator applies synced attributes AFTER `awakeFromInsert`, so a plain assignment is usually re-overwritten correctly — this bites mainly when the content is re-assigned later, e.g. in a reparation/merge step. It is a footgun to rule out, not a common root cause.)

Guard current-device content with the public `NSManagedObjectContext.isEnsemblesIntegrationContext` accessor:

```swift
override func awakeFromInsert() {
    super.awakeFromInsert()
    guard managedObjectContext?.isEnsemblesIntegrationContext != true else { return }
    if uniqueIdentifier == nil { uniqueIdentifier = UUID().uuidString }
    if let loc = LocationProvider.shared.current { self.location = loc }
}
```

Assigning a stable global identifier need not be guarded; guarding content attributes is what matters. When reviewing or writing a `Syncable`/Core Data model class, always check `awakeFromInsert` (and `awakeFromFetch`) for unguarded current-device assignments.

## Backends & licensing

Out of the box (no extra deps): CloudKit, LocalFile, Memory, iCloudDrive (deprecated), GoogleDrive, OneDrive, pCloud, WebDAV, Encrypted, Supabase. Trait-gated (only fetched when the trait is enabled in `Package.swift`): Dropbox, S3, Box, Zip, Multipeer.

Free backends: `CloudKitFileSystem`, `LocalCloudFileSystem`, `MemoryCloudFileSystem`. All others require a license: `EnsemblesLicense.activate("<key>")` before attach (checked in `performAttach`; failure throws `EnsembleError.unlicensed`).

## Testing

Swift Testing (not XCTest). `MemoryCloudFileSystem` is the preferred backend for tests. Sync suites are `@Suite(.serialized)` and `@MainActor` (mainQueue contexts + NotificationCenter cross-talk).

## Common mistakes

- Using a URL where the designated init wants an `NSManagedObjectModel` (URL convenience inits exist, but the designated init takes a model).
- Forgetting the init is failable (`init?`) — it returns nil if the store URL is already registered to another ensemble.
- Expecting E2 local event history to migrate — it doesn't; the cloud reseeds it.
- Blaming a custom backend for `unlicensed` — only CloudKit/Local/Memory are free.
- Assuming one `sync()` propagates both ways instantly — often needs an export round then an import round.
- An `awakeFromInsert` that re-stamps current-device content (location/timestamp/status) during integration without guarding `isEnsemblesIntegrationContext` — can overwrite synced values.
