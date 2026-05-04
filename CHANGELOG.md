# Changelog

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
