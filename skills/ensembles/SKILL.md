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

## Install

Add the Swift package:

```swift
.package(url: "https://github.com/mentalfaculty/Ensembles3.git", from: "3.0.0")
```

Then depend on the products you need (`Ensembles`, `EnsemblesCloudKit`, …). This is the binary distribution; CloudKit and local sync are free, other backends need a licence. Premium customers with a source licence use the `Ensembles3-Source` package instead, which also enables package traits for the SDK-backed backends (`Dropbox`, `S3`, `Box`, `Zip`, `Multipeer`).

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

If a transformable attribute (e.g. a `CLLocation` stored via a value transformer) arrives nil on the receiving device while the rest of the object syncs fine, check, in order:

1. **Use Ensembles 3.0.0 or later.** Earlier builds could drop a transformable value when migrating from Ensembles 2, because Ensembles 2 writes the value's base64 in line-wrapped form and older E3 builds didn't read it. If you migrated from E2 and see only the transformable attribute coming through nil (plain attributes fine), update to 3.0.0+.
2. **Register your value transformer before the Core Data stack loads, on every device.** If the named transformer isn't registered when an event is integrated, the attribute decodes to nil. Use a named `@objc(YourTransformerName)` `NSSecureUnarchiveFromDataTransformer` subclass with the stored class in `allowedTopLevelClasses`, and call its registration early (e.g. in `App.init` / `application(_:didFinishLaunching…)`), before you build the container. With `setLoggingLevel(.verbose)`, a `Failed to retrieve value transformer:` line confirms this is the cause.
3. **Check your `awakeFromInsert`** — see below. If it assigns the attribute from a current-device source, it can overwrite the synced value during integration.

## awakeFromInsert and the integration context

When Ensembles applies changes synced from another device, it inserts objects into a context of its own, and Core Data calls `awakeFromInsert()` on them just as it does for objects your app creates. If your `awakeFromInsert()` assigns content from the current device (the current location, a timestamp, a status), that assignment can overwrite the value arriving from the other device. Guard it.

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

Free backends: `CloudKitFileSystem`, `LocalCloudFileSystem`, `MemoryCloudFileSystem`. All others require a license: call `EnsemblesLicense.activate("<key>")` before attaching, or attach throws `EnsembleError.unlicensed`.

## Testing your app

Use `MemoryCloudFileSystem` as the backend in tests — it's an in-memory cloud, so two ensembles sharing one instance sync without touching CloudKit or the filesystem. Drive a save on one, `sync()` both, and assert the data arrived on the other.

## Common mistakes

- Using a URL where the designated init wants an `NSManagedObjectModel` (URL convenience inits exist, but the designated init takes a model).
- Forgetting the init is failable (`init?`) — it returns nil if the store URL is already registered to another ensemble.
- Expecting E2 local event history to migrate — it doesn't; the cloud reseeds it.
- Blaming a custom backend for `unlicensed` — only CloudKit/Local/Memory are free.
- Assuming one `sync()` propagates both ways instantly — often needs an export round then an import round.
- An `awakeFromInsert` that re-stamps current-device content (location/timestamp/status) during integration without guarding `isEnsemblesIntegrationContext` — can overwrite synced values.
