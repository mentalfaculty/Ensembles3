# Changelog

## 3.0.0-beta.9

- **Fix every-launch `cloudIdentityChanged` detach loop on CloudKit-backed apps.** The cloud-identity token's secure-unarchive allowlist did not include `CKRecord.ID`, so the token came back nil on every restore, the identity check compared the live non-nil token against nil, and the ensemble force-detached on every launch — wiping the local event store and re-registering as a fresh peer each time. Reproduced 100% on iOS 26 / macOS 26. Existing affected installs self-recover on the next launch after upgrading; no migration step needed. (#1)
- **Documentation:** the *Migrating from Ensembles 2* chapter now calls out the CloudKit zone-matching constraint — your E3 build must use the same `CloudKitFileSystem` initializer your E2 build used, because the two private-database initializers write to different zones and devices in different zones cannot see each other's records. The chapter also corrects the previous claim that the local event store auto-migrates from E2 — it does not; on first attach E3 wipes the E2 event store and rebuilds from the cloud.
- **Documentation:** fixed non-compiling `CloudKitFileSystem(ubiquityContainerIdentifier:)` single-argument samples scattered across README, DocC articles, and doc comments (no such initializer exists; replaced with the two-argument `privateDatabaseForUbiquityContainerIdentifier:schemaVersion:` form).

## 3.0.0-beta.8

- **Lowered platform minimums** to iOS 15, macOS 12, tvOS 15, watchOS 8 (down from iOS 16 / macOS 13 / tvOS 16 / watchOS 9). SwiftData features still require iOS 17+ / macOS 14+ / tvOS 17+ / watchOS 10+.

## 3.0.0-beta.2

- **Rename `merge()` to `sync()`** across all public APIs (`SyncOptions`, `isSyncing`, `SyncingPhase`)
- **Trial license support** — time-limited trial keys that expire on a calendar date
- **License portal redesign** — dark theme, bundle prefix validation
- **Example apps** included in both binary and source distribution repos
- **Source distribution repo** — premium customers can build from source via private `Ensembles3-Source` repo
- **Release script** now publishes both binary and source distribution repos in a single command

## 3.0.0-beta.1

First public beta of Ensembles 3 — a complete Swift rewrite of the Ensembles sync framework.

### Highlights

- **Pure Swift** with Swift 6 strict concurrency throughout
- **Async/await API** — `attachPersistentStore()`, `sync()`, `detachPersistentStore()`
- **SwiftData support** via `SwiftDataEnsemble` (iOS 17+/macOS 14+)
- **10 cloud backends**: CloudKit, Local File, Memory, Google Drive, OneDrive, pCloud, WebDAV, Encrypted, plus trait-gated Dropbox, S3, Box
- **Backwards compatible** with Ensembles 2 cloud data and event store formats
- **DocC documentation** for all public targets
- **Example apps** for both Core Data and SwiftData

### Cloud Backends

| Backend | Target | License |
|---------|--------|---------|
| CloudKit | `EnsemblesCloudKit` | Free |
| Local File | `EnsemblesLocalFile` | Free |
| In-Memory | `EnsemblesMemory` | Free |
| Google Drive | `EnsemblesGoogleDrive` | Paid |
| OneDrive | `EnsemblesOneDrive` | Paid |
| pCloud | `EnsemblesPCloud` | Paid |
| WebDAV | `EnsemblesWebDAV` | Paid |
| Encrypted | `EnsemblesEncrypted` | Paid |

### Platforms

iOS 16+, macOS 13+, tvOS 16+, watchOS 9+
