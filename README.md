<!-- Generated file. Regenerated on each release; do not edit. -->
# Ensembles 3

**Local-first sync for Core Data and SwiftData.**

[![Platforms](https://img.shields.io/badge/Platforms-iOS_15%2B_%7C_macOS_12%2B_%7C_tvOS_15%2B_%7C_watchOS_8%2B_%7C_visionOS_1%2B-blue)](https://swiftpackageindex.com/mentalfaculty/Ensembles3)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138)](https://swiftpackageindex.com/mentalfaculty/Ensembles3)
[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue)](https://mentalfaculty.github.io/Ensembles3/Ensembles/documentation/ensembles/)
[![License](https://img.shields.io/badge/License-Commercial-orange)](https://ensembles.io)

> **This package distributes pre-built XCFrameworks (binary only).** Source code is available separately with a [premium license](https://ensembles.io). CloudKit and local backends are free to use; other backends require a license key. See [Licensing](#licensing) below.

Ensembles is the only [local-first](https://www.inkandswitch.com/local-first/) sync framework for Core Data and SwiftData. Unlike most sync frameworks, it requires no custom server: your data syncs as opaque files through storage your users already have, whether that is CloudKit, Dropbox, Google Drive, S3, WebDAV, or a custom backend.

Each device keeps a complete copy of the data, so apps work fully offline. Data stays in your users' own accounts, and can be end-to-end encrypted before it ever leaves the device. There is no server to run, and no cloud bill.

Ensembles has synced production apps since 2013, including [Agenda](https://agenda.com). Ensembles 3 is a complete rewrite in Swift, with async/await concurrency and Swift Package Manager distribution, and it is fully backward compatible with Ensembles 2 cloud data.

## Why Ensembles?

- **Local-first, not offline-first** — cloud data is opaque files, not structured records a server indexes and controls. With end-to-end encryption enabled, the storage provider cannot read your data at all.
- **No custom server** — users sync through their own storage accounts, so there is no server to deploy and no cloud bill. Devices can also sync peer-to-peer via MultipeerConnectivity with no cloud at all.
- **Any cloud backend** — 15 built-in backends including CloudKit, Dropbox, S3, Google Drive, OneDrive, Box, pCloud, Supabase, and WebDAV. Not locked to iCloud. Implement the `CloudFileSystem` protocol (8 methods) to add your own.
- **End-to-end encrypted** — AES-256-GCM encryption before data leaves the device. No need to rely on Apple's Advanced Data Protection.
- **Core Data fidelity** — ordered relationships and validation rules are preserved, with no changes to your model required.
- **Transparent to your app** — Ensembles observes your existing `NSManagedObjectContext` saves. You don't need to change your data model or your save logic.
- **Automatic conflict resolution** — causal revision tracking merges changes deterministically on every device. Delegate hooks let you inspect and repair merged data before it's committed.

## Quick Start (Core Data)

`CoreDataEnsembleContainer` creates a Core Data stack, sets up a delegate, and auto-syncs on save:

```swift
import Ensembles
import EnsemblesCloudKit

// modelURL points to the .momd compiled from your .xcdatamodeld
let modelURL = Bundle.main.url(forResource: "Model", withExtension: "momd")!

// The store is placed automatically at Application Support/MainStore.sqlite
let container = CoreDataEnsembleContainer(
    name: "MainStore",
    modelURL: modelURL,
    cloudFileSystem: CloudKitFileSystem(
        privateDatabaseForUbiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp",
        schemaVersion: .v2
    )
)!
```

For deduplication, conform your `NSManagedObject` subclass to the `Syncable` protocol:

```swift
class Note: NSManagedObject, Syncable {
    static let globalIdentifierKey = "uniqueID"
    @NSManaged var uniqueID: String
    @NSManaged var title: String
}
```

That's it. The container automatically attaches to the cloud, syncs on save, on app activation, and on a timer. Remote changes are merged into the container's `viewContext` automatically.

Pass `EnsembleContainerConfiguration(autoSyncPolicy: .manual)` to the initializer to disable all automatic syncing and call `sync()` yourself.

For more control, use `CoreDataEnsemble` directly — see the [Getting Started guide](https://mentalfaculty.github.io/Ensembles3/Ensembles/documentation/ensembles/gettingstarted).

## Quick Start (SwiftData)

```swift
import EnsemblesSwiftData
import EnsemblesCloudKit

// The store is placed automatically at Application Support/MainStore.sqlite
let container = SwiftDataEnsembleContainer(
    name: "MainStore",
    modelTypes: [Item.self, Tag.self],
    cloudFileSystem: CloudKitFileSystem(
        privateDatabaseForUbiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp",
        schemaVersion: .v2
    )
)!

// Use container.modelContainer with SwiftUI
ContentView()
    .modelContainer(container.modelContainer)
```

SwiftData models can declare a global identifier for automatic deduplication by conforming to the `Syncable` protocol. A UUID assigned at creation time is usually the best choice. Use a fixed, meaningful value (like a name) for singleton objects or reference data like tags, where two devices might independently create the same logical object:

```swift
@Model
class Item: Syncable {
    static let globalIdentifierKey = "uniqueID"
    var uniqueID: String       // UUID — unique per object
    var title: String
}

@Model
class Tag: Syncable {
    static let globalIdentifierKey = "name"
    var name: String            // Fixed value — two "Work" tags merge into one
}
```

SwiftData support requires iOS 17+ / macOS 14+.

## First Sync and Existing Data

The first time a device attaches, existing data in its store is imported and merged with whatever is already in the cloud. That is the default seed policy (`mergeAllData`), and it means the order devices come online doesn't matter. Objects created independently on two devices (the same "Work" tag, say) merge into one when they share a global identifier via `Syncable`.

For CloudKit, add the iCloud capability with CloudKit enabled to your target, and test on a device or simulator signed in to an iCloud account. The `schemaVersion: .v2` in the quick starts is correct for new apps; if you are migrating an Ensembles 2 fleet, match the schema version your E2 build used.

## Ensembles vs Apple CloudKit Sync

Apple's built-in option is `NSPersistentCloudKitContainer` for Core Data, or SwiftData's CloudKit sync. If you want an alternative to CloudKit sync with more control, here is how they compare:

| Feature | Ensembles | Core Data + CloudKit | SwiftData + CloudKit |
|---------|-----------|---------------------|---------------------|
| Architecture | Local-first | Offline-first | Offline-first |
| Cloud data format | Opaque files | Structured CKRecords | Structured CKRecords |
| Cloud backends | Any (15 built-in + custom) | CloudKit only | CloudKit only |
| Custom server required | No — uses existing storage | No — but locked to Apple | No — but locked to Apple |
| Decentralized | Yes — no central authority | No — Apple servers mediate | No — Apple servers mediate |
| Peer-to-peer sync | Yes (MultipeerConnectivity) | No | No |
| Ordered relationships | Yes | No | No |
| Validation rules | Fully preserved | Relaxed | All relationships optional |
| E2E encryption | Built-in (AES-256-GCM) | Requires ADP | Requires ADP |
| Custom backends | Yes (8-method protocol) | No | No |
| Conflict resolution | Revision tracking + delegate | Last-writer-wins | Last-writer-wins |
| Core Data support | Yes | Yes | N/A |
| SwiftData support | Yes | N/A | Yes |

Apple's CloudKit sync is **offline-first**: it works without a network connection, but Apple's servers remain the central authority. Most other local-first frameworks avoid vendor lock-in yet still require you to deploy and maintain a custom sync server, the way git requires a git server. Ensembles needs no server infrastructure at all: any storage service that can hold files is enough.

## How It Works

Ensembles uses an event-sourcing architecture. Every save to your Core Data store is recorded as an event. Events are exported to the cloud as files, downloaded on other devices, and replayed into each local store.

1. **Attach** — `attachPersistentStore()` sets up local sync metadata, imports the persistent store contents into an event log, and registers the device in the cloud.

2. **Save** — When the app saves to the monitored store, Ensembles automatically captures the inserted, updated, and deleted objects as a `StoreModificationEvent`.

3. **Sync** — `sync()` downloads remote events from the cloud, replays them into the local store (resolving conflicts via revision tracking), and uploads new local events.

4. **Compact** — Old events are automatically compacted into a baseline snapshot: the full state of the store at a point in time. Earlier events are discarded, and superseded files are cleaned up in the cloud, so sync data stays bounded no matter how long a store has been syncing.

### What a Merge Actually Does

Conflicts are resolved at the attribute level. Causal ordering decides the winner: a change made with knowledge of another change beats it, and truly concurrent edits to the same attribute fall back to last-writer-wins with a deterministic tiebreaker. To-many relationships use an add-wins strategy: additions from both sides are kept, and only explicit removals are removed. Devices that have seen the same events always converge to the same state.

When those defaults aren't right for your model, the delegate hands you the merged changes before they are committed: inspect them, repair them in a reparation context (repairs sync to all peers as new events), or veto the save entirely. See [Conflict Resolution](https://mentalfaculty.github.io/Ensembles3/Ensembles/documentation/ensembles/conflictresolution) for the full story.

### Lifecycle API

- **Delegate** — Implement `CoreDataEnsembleDelegate` to merge save notifications into your main context, handle forced detaches, provide global identifiers for deduplication, and repair data before merge saves.
- **Suspend/Resume** — On iOS, call `suspendSync()` from a background task's expiration handler to pause an in-progress sync. Call `resumeSync()` when the app gets time again. The sync resumes from where it left off rather than restarting.
- **Detach** — `detachPersistentStore()` removes local sync data and unregisters from the cloud. The persistent store itself is not affected.

## Installation

Add Ensembles to your project via Swift Package Manager. Two paths:

- **Free binary distribution** (most apps): add [`https://github.com/mentalfaculty/Ensembles3`](https://github.com/mentalfaculty/Ensembles3) (pre-built XCFrameworks, Swift 5.9+).
- **Source license holders**: use the source-distribution URL provided with your license (Swift 6.1+).

Platforms: iOS 15+ / macOS 12+ / tvOS 15+ / watchOS 8+ / visionOS 1+.

### Xcode

1. Select _Add Package Dependencies..._ from the _File_ menu
2. Enter `https://github.com/mentalfaculty/Ensembles3` (or the source URL above)
3. Add the products you need (e.g. `Ensembles`, `EnsemblesCloudKit`)

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/mentalfaculty/Ensembles3", from: "3.0.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Ensembles", package: "Ensembles3"),
            .product(name: "EnsemblesCloudKit", package: "Ensembles3"),
        ]
    ),
]
```

With a source license, use the source-distribution URL and package name provided with your license.

### Optional Backends (Package Traits)

In the source distribution, backends that depend on third-party SDKs are gated behind [package traits](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md) (Swift 6.1+), so unused dependencies are never fetched:

| Trait | Backend | External Dependency |
|-------|---------|---------------------|
| `Dropbox` | `EnsemblesDropbox` | SwiftyDropbox |
| `S3` | `EnsemblesS3` | aws-sdk-swift |
| `Box` | `EnsemblesBox` | BoxSDK |
| `Zip` | `EnsemblesZip` | ZIPFoundation |
| `Multipeer` | `EnsemblesMultipeer` | ZIPFoundation (auto-enabled via `Zip`) |

All other backends have no external dependencies and are always available.

### Binary Distribution (XCFrameworks)

If you use the [binary distribution](https://github.com/mentalfaculty/Ensembles3) (`Ensembles3` package), all backends are included as pre-built XCFrameworks. However, the five backends listed above still require their external SDK at compile time. Add the external SDK as a separate Swift package dependency in your project:

| Backend | Add This Package |
|---------|-----------------|
| `EnsemblesDropbox` | [SwiftyDropbox](https://github.com/dropbox/SwiftyDropbox) |
| `EnsemblesS3` | [aws-sdk-swift](https://github.com/awslabs/aws-sdk-swift) (`AWSS3` product) |
| `EnsemblesBox` | [BoxSDK](https://github.com/box/box-ios-sdk.git) |
| `EnsemblesZip` | [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) |
| `EnsemblesMultipeer` | [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) |

With the source distribution, enabling a package trait resolves the external dependency automatically via SPM — no extra steps needed.

If a major SDK update introduces breaking API changes, pin to the line you have tested. If you would rather not manage these SDK versions yourself, use the [source distribution](https://ensembles.io) instead; there, Swift Package Manager resolves each SDK transitively, so there is nothing to pin.

## Develop with Claude Code

We ship a [Claude Code](https://claude.com/claude-code) skill that teaches Claude the API, the cloud backends, the seed policy, Ensembles 2 → 3 migration, and the pitfalls that generate support tickets. Install it once:

```
/plugin marketplace add mentalfaculty/Ensembles3
/plugin install ensembles@ensembles
```

(Working inside a clone of this repo? The skill is auto-discovered from `.claude/skills/`, so no install is needed.)

## Available Backends

| Module | Description | External SDK |
|--------|-------------|--------------|
| `EnsemblesCloudKit` | Syncs via iCloud using CloudKit | — |
| `EnsemblesDropbox` | Dropbox via SwiftyDropbox SDK (trait: `Dropbox`) | [SwiftyDropbox](https://github.com/dropbox/SwiftyDropbox) |
| `EnsemblesS3` | Amazon S3 and compatible services — MinIO, R2, Backblaze B2 (trait: `S3`) | [aws-sdk-swift](https://github.com/awslabs/aws-sdk-swift) (`AWSS3`) |
| `EnsemblesGoogleDrive` | Google Drive via REST API v3 | — |
| `EnsemblesOneDrive` | Microsoft OneDrive via Microsoft Graph API | — |
| `EnsemblesBox` | Box via BoxSDK (trait: `Box`) | [BoxSDK](https://github.com/box/box-ios-sdk.git) |
| `EnsemblesPCloud` | pCloud via REST API | — |
| `EnsemblesSupabase` | Supabase Storage with built-in email/password auth | — |
| `EnsemblesWebDAV` | Any WebDAV server | — |
| `EnsemblesMultipeer` | Peer-to-peer via MultipeerConnectivity (trait: `Multipeer`) | [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) |
| `EnsemblesiCloudDrive` | iCloud Drive via `NSFileCoordinator` (legacy; prefer CloudKit) | — |
| `EnsemblesLocalFile` | Local directory — for testing or shared-folder sync | — |
| `EnsemblesMemory` | Actor-based in-memory store — for unit testing | — |
| `EnsemblesZip` | Compression wrapper for any backend (trait: `Zip`) | [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) |
| `EnsemblesEncrypted` | Encryption wrapper for any backend | — |

The Zip and Encrypted backends are wrappers: they wrap another `CloudFileSystem` to add compression or encryption before files are transferred to the cloud.

## Authentication

Each backend handles authentication differently. Backends that communicate via REST API include built-in authenticator classes; SDK-based backends delegate auth to their SDK.

| Backend | Auth Method | Credentials From |
|---------|------------|-----------------|
| CloudKit | Implicit iCloud account | No setup needed |
| Google Drive | `GoogleDriveAuthenticator` (OAuth 2.0) | [Google Cloud Console](https://console.cloud.google.com/) |
| OneDrive | `OneDriveAuthenticator` (OAuth 2.0) | [Azure Portal](https://portal.azure.com/) |
| pCloud | `PCloudAuthenticator` (OAuth 2.0 token flow) | [my.pcloud.com](https://my.pcloud.com/) |
| Supabase | `SupabaseAuthenticator` (email/password) | [supabase.com](https://supabase.com) |
| Dropbox | SwiftyDropbox SDK (OAuth 2.0) | [Dropbox App Console](https://www.dropbox.com/developers/apps) |
| Box | `BoxClient` injection (multiple auth methods) | [developer.box.com](https://developer.box.com/) |
| S3 | AWS SDK credential chain | [AWS Console](https://console.aws.amazon.com/) |
| WebDAV | Username / password | Your WebDAV server |

### Authenticator-Based Backends (Google Drive, OneDrive, pCloud, Supabase)

These backends include a companion `*Authenticator` class that handles sign-in (OAuth for Google Drive / OneDrive / pCloud, email + password for Supabase), stores tokens in the Keychain, and (for Google Drive / OneDrive / Supabase) automatically refreshes expired tokens. pCloud tokens do not expire.

```swift
// Example: pCloud
let config = PCloudAuthenticator.Configuration(
    clientID: "your-app-key",
    redirectURI: "com.yourapp://pcloud/callback"
)
let authenticator = PCloudAuthenticator(configuration: config)
try await authenticator.authorize(presenting: window) // One-time interactive auth

let cloudFS = PCloudCloudFileSystem(authenticator: authenticator)
```

Supabase uses email/password directly via GoTrue — no OAuth round-trip, no `ASWebAuthenticationSession`. Works on iOS, macOS, tvOS, and watchOS:

```swift
// Example: Supabase
let auth = SupabaseAuthenticator(configuration: .init(
    projectURL: URL(string: "https://abcd1234.supabase.co")!,
    anonKey: "your-publishable-anon-key"
))
try await auth.signIn(email: "user@example.com", password: "...")

let cloudFS = SupabaseCloudFileSystem(
    configuration: .init(
        projectURL: auth.configuration.projectURL,
        anonKey: auth.configuration.anonKey,
        bucket: "ensembles"
    ),
    authenticator: auth
)
```

All four also accept a static access token for cases where you manage tokens externally:

```swift
let cloudFS = GoogleDriveCloudFileSystem(accessToken: "your-token")
```

### SDK-Based Backends (Dropbox, Box, S3)

These backends wrap a third-party SDK client. You create and configure the client with your own auth, then inject it:

```swift
// Dropbox: uses SwiftyDropbox SDK's built-in auth
let cloudFS = DropboxCloudFileSystem()
cloudFS.delegate = self  // Delegate handles the link flow

// Box: inject a BoxClient with any supported auth method
let auth = BoxDeveloperTokenAuth(token: "your-token")
let cloudFS = BoxCloudFileSystem(client: BoxClient(auth: auth))

// S3: inject an S3Client (credentials auto-resolved from environment)
let cloudFS = S3CloudFileSystem(
    client: try await S3Client(),
    bucketName: "my-bucket",
    keyPrefix: "ensembles/"
)
```

See each backend's class documentation for detailed setup instructions and code examples.

## Custom Cloud Backends

Any storage that can hold files at paths can serve as a backend. Implement the `CloudFileSystem` protocol — just 8 methods covering connection, file existence, directory listing, upload, download, and deletion. See the DocC documentation for a full guide and reference implementations.

## Backward Compatibility

Ensembles 3 is fully backward compatible with Ensembles 2 *cloud* data, including cloud file formats and directory structure, CloudKit record structures, and property change value archives.

The local event store does not carry across: E3 uses a different on-disk format and resets the event store on first attach. Your app's persistent store (your own Core Data or SwiftData SQLite) is unaffected, and the cloud is the source of truth, so the migrated device re-syncs from there. See the [Migrating from Ensembles 2](https://mentalfaculty.github.io/Ensembles3/Ensembles/documentation/ensembles/migratingfromensembles2) guide for the full migration story.

### Compatibility Mode

If you're transitioning from Ensembles 2 and some users may still be running the E2 version, set the compatibility mode to restrict exports to E2-parseable formats:

```swift
// With a container
let config = EnsembleContainerConfiguration(
    compatibilityMode: .ensembles2Compatible
)
let container = CoreDataEnsembleContainer(
    name: "MainStore",
    storeURL: storeURL,
    modelURL: modelURL,
    cloudFileSystem: cloudFS,
    configuration: config
)

// Or directly on an ensemble
ensemble.compatibilityMode = .ensembles2Compatible
```

Once your E2 fleet is gone, switch to `.ensembles3` (the default) so future E3-only features become available. Today the two modes produce essentially identical exports; the only wire-level difference is behind an opt-in `compressModelHashes` flag. Switching modes early is safe between E3 peers. Once compressed-hash exports appear, remaining E2 devices cannot read them, which effectively forces those users to upgrade. Two E3 devices in different modes sync with each other normally; the mode only restricts what each device *writes*.

If your existing E2 fleet uses CloudKit, your E3 build must use the same `CloudKitFileSystem` initializer your E2 build did — the two private-database initializers write to different CloudKit zones, and devices in different zones cannot see each other's records. The migration guide above has the details.

## Example Apps

The `Examples/` directory includes three sample apps:

- **SimpleSyncCoreData** — Core Data + LocalCloudFileSystem, SwiftUI, dual-panel sync demo
- **SimpleSyncSwiftData** — SwiftData + LocalCloudFileSystem, SwiftUI, dual-panel sync demo
- **Idiomatic** — A full-featured SwiftData note-taking app syncing via CloudKit

The SimpleSync apps show two side-by-side panels simulating different devices syncing via a shared local directory. Each uses a container class (`CoreDataEnsembleContainer` / `SwiftDataEnsembleContainer`) that handles all the setup and auto-sync.

## Licensing

CloudKit, iCloud Drive, LocalFile, Memory, and Zip backends are **free to use** with no license required, for both Core Data and SwiftData apps. All other backends (Google Drive, OneDrive, Dropbox, S3, Box, pCloud, Supabase, WebDAV, Encrypted, Multipeer), and custom `CloudFileSystem` implementations, require a license key.

Activate a license key at app launch:

```swift
import Ensembles

EnsemblesLicense.activate("your-license-key")
```

A subscription covers all SDK versions released during the subscription period. Deployed apps keep working indefinitely: there is no runtime expiry.

Free trials are available at [ensembles.io](https://ensembles.io).

## Testing

The package includes a runnable test suite that links against the shipped XCFrameworks:

```bash
swift test
```

## Documentation

[**Browse the documentation online**](https://mentalfaculty.github.io/Ensembles3/Ensembles/documentation/ensembles/)

The complete guide, *Ensembles 3 — The Complete Guide*, is included in the [`Manual/`](Manual/) directory as PDF, EPUB, and Markdown.

Full API documentation is generated with DocC and includes articles on getting started, architecture, conflict resolution, custom cloud backends, SwiftData integration, and migrating from Ensembles 2. Each backend target has its own DocC catalog with authentication setup and API details.

## Support

Questions and bug reports: [support@mentalfaculty.com](mailto:support@mentalfaculty.com), or open an issue on the [Ensembles3 repository](https://github.com/mentalfaculty/Ensembles3/issues).

## License

Ensembles 3 Support Agreement — The Mental Faculty B.V. See [LICENSE](LICENSE) for details.
