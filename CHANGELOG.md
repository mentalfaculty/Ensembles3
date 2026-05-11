# Changelog

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
