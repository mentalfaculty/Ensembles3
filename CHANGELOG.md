# Changelog

## 3.0.1

- **Fix the tvOS build with current Swift toolchains.** Newer Swift toolchains (6.4 / Xcode 27) enforce tvOS API availability that older ones let slide, surfacing two latent issues at the package's tvOS 15 target. First, `ASWebAuthenticationSession` requires tvOS 16 and `ASWebAuthenticationPresentationContextProviding` is unavailable on tvOS, but the shared web-authentication helper (and the Google Drive, OneDrive, and pCloud authenticators) guarded interactive OAuth only against watchOS; the guard now also excludes tvOS, which has no usable web-auth presentation surface. Second, `CKSubscription.NotificationInfo.alertBody` is unavailable on tvOS but was set unconditionally when subscribing for CloudKit push notifications; that assignment is now guarded (silent background delivery is unaffected — it is driven by `shouldSendContentAvailable`). tvOS keeps the full SDK and all sync; only the interactive OAuth sign-in UI for those three backends is unavailable there, as it was in practice already.
- **Fix external data files (such as images) being lost during rebasing and baseline consolidation.** Large attribute values are stored outside the event database as files, tracked by a separate `data_files` index. The index must be re-synced whenever an object change's property changes are written, otherwise `removeUnreferencedDataFiles()` treats the file as orphaned and deletes it. `EventBuilder` and the consolidator's reinsert path did this, but `Rebaser` (all merge branches) and `BaselineConsolidator`'s merge-into-existing path did not. When a baseline was rebased or two baselines were consolidated, an object that gained or carried a data-file-backed attribute could have its property changes merged while its `data_files` entries were left stale, so the file was later garbage-collected and the attribute came back empty. Both `Rebaser.mergeChange` and `BaselineConsolidator` now call `syncDataFiles` after merging property changes. This is a regression introduced by the Ensembles 3 rewrite: in Ensembles 2 the data-file index was a Core Data relationship rebuilt automatically inside `CDEObjectChange`'s property-change setter, so it could never go stale; Ensembles 3's raw-SQLite event store made re-syncing the index an explicit, separate call that these two merge paths omitted. Reported by Ernst. Regression tests cover rebasing and consolidation, asserting the file survives the unreferenced-file cleanup.

## 3.0.0

First stable release of Ensembles 3.

- **Fix Ensembles 2 → 3 sync dropping transformable attribute values.** Ensembles 2's Objective-C exporter base64-encodes `Data` and transformable blobs in 64-column lines joined by CRLF. The Ensembles 3 JSON importer decoded the `"data"` tag with strict `Data(base64Encoded:)`, which rejects the embedded line breaks and returns nil — so the value was dropped at import, before any value transformer ran. For a model with a transformable attribute (for example a `CLLocation`), the attribute arrived nil on the receiving E3 device while plain-string siblings on the same record arrived correctly, and no value-transformer error was logged because the loss happened upstream of the transformer. Only the E2 → E3 direction was affected: E3 writes its base64 unwrapped, and E2 reads with its own lenient decoder. The importer now decodes with `.ignoreUnknownCharacters`, matching Ensembles 2. (`b1e7902`)
- **Guard transformable-attribute decoding against an uncaught exception.** Decoding a transformable value through the built-in `NSSecureUnarchiveFromDataTransformer` raised an uncaught Objective-C `NSInvalidUnarchiveOperationException` (which Swift cannot catch, crashing the process) when the archived blob held a class outside the transformer's allowlist. Decoding now runs through the Swift-throwing `NSKeyedUnarchiver`, degrading to nil and logging instead of crashing; a blank-transformer attribute also decodes via its declared value class. (`01be04d`)
- **Add `NSManagedObjectContext.isEnsemblesIntegrationContext`.** Core Data calls `awakeFromInsert()` on objects Ensembles inserts while integrating remote events, just as it does for objects your app inserts. A model class that assigns current-device content there (a location, a timestamp) can interfere with synced values during integration. The new public property lets you guard such side effects so they run only for objects your app creates. (`e5be2a5`)
- **Ship a Claude Code skill.** The package and both distribution repos now include an Ensembles skill, installable as a Claude Code plugin (`/plugin marketplace add mentalfaculty/Ensembles3` then `/plugin install ensembles@ensembles`), that teaches the assistant the API, backends, migration, seed policy, and common pitfalls. The README, DocC Getting Started guide, and Manual point to it. (`86a00ec`)
- **Documentation:** clarified compatibility mode (the two modes produce identical exports unless `compressModelHashes` is opted in; the setting restricts writes, not reads), and documented transformable attributes and the `awakeFromInsert` integration-context trap in the Migrating-from-E2 guide, the DocC Conflict Resolution guide, and the Manual.

## 3.0.0-beta.14

- **Fix the Ensembles 2 → 3 migration "stuck sync" (and the underlying cause of the earlier migration wipe).** Ensembles 2 stored the event database as `events.sqlite`; Ensembles 3 rewrote the event store as raw SQLite and renamed the file to `eventstore.db`, with no migrator for it. But E3 still carries the metadata sidecar forward (E2's `store.plist` is renamed to `store-metadata.plist`). So an E2 → 3 app update left the device with a *persistent store identifier* (read from the inherited sidecar) but *no event database* — and `EventStore` silently created a fresh empty one. The result was an event store that reported `containsEventData`, so the ensemble believed it was already attached and never ran a clean attach. It would then re-import its own previously-uploaded cloud baseline on every sync; because the consolidator skips dependency-checking and promotion of baselines produced under the local store's own id, that baseline stayed at `.baselineMissingDependencies` (invisible to `fetchBaselineEvent()`) forever — manifesting as a permanent `EnsembleError.dataCorruptionDetected` on every sync (or, before the beta.13 wipe guard, as a full-store wipe). Two fixes restore the Ensembles 2 invariant that a live store identifier implies a populated event store:
  - `EventStore` now discards the restored metadata (identifier, identity token, baseline id) when it finds the event database file was absent and had to be created fresh. The store reads as un-attached, so the host triggers a normal attach, which mints a fresh identifier — and the cloud baseline then correctly looks *remote* and integrates.
  - `BaselineConsolidator` no longer skips dependency-checking and promotion of a baseline that is type `.baselineMissingDependencies`, even when its event-revision store id matches the local store. A re-imported baseline must always be promotable; only a genuinely locally-produced `.baseline` (type 100) is skipped.

  Already-stuck installs self-heal on the next launch. Each fix has its own regression test.

## 3.0.0-beta.13

- **Harden baseline consolidation against identifier desync.** `BaselineConsolidator` re-identified the merged baseline whenever more than one baseline existed at all — including the common, benign case of one real baseline plus an empty placeholder. Ensembles 2 only re-identified the merged baseline when a non-empty *other* baseline was actually merged into it; the Swift port broadened that condition. The over-eager rename can desync a device's local baseline identifier from its copy in the cloud, which can lead the device to re-download and re-import its own baseline as `.baselineMissingDependencies`. The consolidator skips dependency-checking (and therefore promotion) of locally-produced baselines, so such a re-imported baseline is never promoted back to `.baseline`. The consolidator now matches Ensembles 2: it only re-identifies the merged baseline when a non-empty other baseline was actually merged in.
- **Add a full-integration wipe guard to `EventIntegrator`.** If the store modification events present cannot be integrated (e.g. because the baseline is unusable), a full integration would previously rebuild the persistent store from an empty event set and delete every existing object as "unreferenced" — then export those deletions to the cloud. `EventIntegrator` now refuses to run a full integration when events exist but none are integrable, throwing `EnsembleError.dataCorruptionDetected` instead of wiping the store. This turns a class of "lost baseline" bugs into a recoverable, surfaced error rather than silent data loss.

  These two changes are motivated by a customer report of an Ensembles 2 → 3 migration wiping all local and remote data, which Ensembles 2 did not do. The baseline-rename divergence from Ensembles 2 is the most plausible mechanism — but the full end-to-end chain has not yet been reproduced in a test, so the link to that specific report is unverified. Each fix is independently covered by a regression test for the concrete defect it addresses.

## 3.0.0-beta.12

- **Breaking: global identifiers are now required and must be non-empty.** The `CoreDataEnsembleDelegate.coreDataEnsemble(_:globalIdentifiersForManagedObjects:)` signature returns `[String]` (was `[String?]`). The container's `globalIdentifiers` closure signature changes similarly. Attaching without a configured globalID source (delegate method, container closure, or `Syncable` conformance) now throws `EnsembleError.missingGlobalIdentifierSource` instead of silently auto-generating UUIDs that would never match across devices. Empty-string globalIDs hit a `precondition` failure. The framework no longer invents substitute IDs under any circumstance. App authors must provide a stable, non-empty identifier for every managed object the ensemble syncs.
- **Fix: JSON event import index-drift bug.** When a change-dict in an event file lacked a `globalIdentifier` key (possible in legacy E2 data, since Objective-C `dict[key] = nil` is a no-op that omits the key), the importer's `compactMap`-based loop cross-wired property changes to the wrong globalIdentifier rows and silently dropped the last change in the batch. In `.ensembles3` mode this now throws `EnsembleError.invalidGlobalIdentifier`; in `.ensembles2Compatible` mode the affected change is skipped with a warning, and the remaining changes keep their correct indexing.
- **Fix: nil globalIdentifier coercion in E2 binary import.** `ObjectGraphMigrator` previously coerced nil to `""`, collapsing multiple legacy objects onto a single empty-string row in the new event store. Such rows are now skipped with a warning.
- **Rename the event store metadata file from `store.plist` to `store-metadata.plist`.** Both E2 and pre-rename E3 wrote to the same `store.plist` path with the same dictionary keys, so a device downgraded from E3 back to E2 (e.g. during staged rollout or App Store rollback) would read E3's metadata as its own, conclude it was leeched, and proceed with an empty `events.sqlite` — instead of leeching cleanly. Renaming the E3 file makes downgrades safe by design: a downgraded E2 device sees no `store.plist`, considers itself unleeched, and recovers via a non-destructive leech on next sync. Existing E3 installs transparently rename the legacy file on first launch — no detach, no re-leech, no user-visible change.

## 3.0.0-beta.11

- **New `EnsemblesSupabase` backend.** `SupabaseCloudFileSystem` syncs through a Supabase Storage bucket; `SupabaseAuthenticator` covers email/password sign-in against Supabase's built-in GoTrue auth (with single-flight token refresh and Keychain-backed credentials). Direct REST against the Storage and Auth APIs — no SDK dependency, no package trait. When the authenticator-driven init is used, the file system automatically prefixes every object key with the user's UUID so a one-line row-level-security policy (`(storage.foldername(name))[1] = auth.uid()::text`) is sufficient for per-user isolation. The authenticator works on all platforms including watchOS and tvOS (no `ASWebAuthenticationSession` round-trip required). (#3)
- **Fix concurrent refresh-token races on Google Drive and OneDrive.** Both authenticators previously had no guard against concurrent token refreshes — if two callers raced through `validAccessToken()` after the cached token expired, each fired its own `/token` request, and refresh-token rotation could invalidate one response with the other, leaving the credential broken on the next call. Concurrent callers now join a single in-flight refresh `Task` via `NSLock`. (#4)
- **DRY the four backend authenticators.** Extracted two shared helpers into `Sources/Ensembles/Auth/`: `KeychainCredentialStore<Credential>` (generic Keychain save/load/delete) and `WebAuthenticationFlow.run(...)` (wraps `ASWebAuthenticationSession`). Both exposed via `@_spi(Auth)`. GoogleDrive, OneDrive, pCloud, and Supabase authenticators now use them. Net −312 LOC in authenticators, +169 LOC of new tested infrastructure. Keychain service strings preserved exactly, so existing installs keep their credentials with no re-sign-in. (#5)

## 3.0.0-beta.10

- **Replace the `NSObject.self` catch-all in the cloud-identity-token unarchive allowlist with a per-backend tight list.** The beta.9 fix used `NSObject.self` as a catch-all, which Apple's `NSKeyedUnarchiver.validateAllowedClass:forKey:` runtime validator started warning would become an error in a future OS release. Each `CloudFileSystem` backend now declares the classes it might return from `fetchUserIdentity()` via a new `cloudIdentityTokenClasses: [AnyClass]` protocol property. The default lists Foundation primitives only; CloudKit overrides to add `CKRecord.ID`. Wrapper backends (Encrypted, Zip) forward to their inner backend. The console warning is gone; the every-launch detach behaviour fixed in beta.9 stays fixed. (#2)

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
