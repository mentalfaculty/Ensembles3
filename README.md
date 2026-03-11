# Ensembles 3 — Local-First Sync for Core Data and SwiftData

[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue)](https://mentalfaculty.github.io/Ensembles3/Ensembles/documentation/ensembles/)

Ensembles is the only [local-first](https://www.inkandswitch.com/local-first/) sync framework for Core Data and SwiftData. Unlike most sync frameworks, it requires no custom server — your data syncs as opaque files through storage your users already have: CloudKit, Google Drive, OneDrive, WebDAV, or any custom backend.

No server can read, interpret, or control your data. It stays in your users' own accounts, and with built-in AES-256-GCM encryption it can be fully end-to-end encrypted before it ever leaves the device.

Because your users already pay for their storage, there are no server costs for you — no infrastructure team, no cloud bills, no scaling headaches.

Ensembles 3 is a modern rewrite of the Ensembles Objective-C framework in pure Swift, with async/await concurrency and Swift Package Manager distribution. It is fully backward compatible with Ensembles 2 cloud data.

## Why Ensembles?

- **Truly local-first** — not just offline-first. Cloud data is opaque files, not structured records a server can read. No vendor can inspect, lock, or hold your data hostage.
- **No custom server, no cloud costs, no cloud team** — unlike other sync frameworks, there's no server to deploy or pay for. Users sync through their own storage accounts, so there are no cloud bills for you.
- **Any cloud backend** — 10 built-in backends including CloudKit, Google Drive, OneDrive, pCloud, and WebDAV. Not locked to iCloud. Implement the `CloudFileSystem` protocol (8 methods) to add your own.
- **End-to-end encrypted** — AES-256-GCM encryption before data leaves the device. No need to rely on Apple's Advanced Data Protection.
- **Full Core Data fidelity** — ordered relationships work. Validation rules preserved. No model compromises required.
- **Transparent to your app** — Ensembles observes your existing `NSManagedObjectContext` saves. You don't need to change your data model or your save logic.
- **Automatic conflict resolution** — causal revision tracking determines the correct merge. Delegate hooks let you inspect and repair merged data before it's committed.

## Ensembles vs Apple CloudKit Sync

| Feature | Ensembles | Core Data + CloudKit | SwiftData + CloudKit |
|---------|-----------|---------------------|---------------------|
| Architecture | Local-first | Offline-first | Offline-first |
| Cloud data format | Opaque files | Structured CKRecords | Structured CKRecords |
| Cloud backends | Any (10 built-in + custom) | CloudKit only | CloudKit only |
| Custom server required | No — uses existing storage | No — but locked to Apple | No — but locked to Apple |
| Decentralized | Yes — no central authority | No — Apple servers mediate | No — Apple servers mediate |
| Ordered relationships | Yes | No | No |
| Validation rules | Fully preserved | Relaxed | All relationships optional |
| E2E encryption | Built-in (AES-256-GCM) | Requires ADP | Requires ADP |
| Custom backends | Yes (8-method protocol) | No | No |
| Conflict resolution | Revision tracking + delegate | Last-writer-wins | Last-writer-wins |
| Core Data support | Yes | Yes | N/A |
| SwiftData support | Yes | N/A | Yes |

Apple's CloudKit sync is **offline-first**: it works without a network connection, but Apple's servers are the central authority. Your data is stored as structured CloudKit records that Apple indexes and manages. Most other local-first frameworks avoid vendor lock-in but still require you to deploy and maintain a custom sync server — the way git requires a git server. Ensembles is different: it needs no server infrastructure at all. Any existing storage service that can hold files — Google Drive, a WebDAV share, pCloud — is enough. Data is opaque files that no server can interpret. You can encrypt everything end-to-end.

## Requirements

- iOS 16+ / macOS 13+ / tvOS 16+ / watchOS 9+
- Swift 5.9+, Xcode 15+
- SwiftData features require iOS 17+ / macOS 14+

## Installation

Add Ensembles 3 to your project using Swift Package Manager:

### Xcode

1. Select _Add Package Dependencies..._ from the _File_ menu
2. Enter `https://github.com/mentalfaculty/Ensembles3.git`
3. Add the products you need (e.g. `Ensembles`, `EnsemblesCloudKit`)

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/mentalfaculty/Ensembles3.git", from: "3.0.0"),
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

Then import only the targets you need:

```swift
import Ensembles
import EnsemblesCloudKit  // or another backend
```

## Backends

### Free (no license required)

| Backend | Import | Description |
|---------|--------|-------------|
| **Core** | `Ensembles` | Core sync framework |
| **CloudKit** | `EnsemblesCloudKit` | Apple CloudKit backend |
| **Local File** | `EnsemblesLocalFile` | Local filesystem (testing/development) |
| **Memory** | `EnsemblesMemory` | In-memory backend (unit testing) |
| **SwiftData** | `EnsemblesSwiftData` | SwiftData integration |

### Paid (subscription license required)

| Backend | Import | Description |
|---------|--------|-------------|
| **Google Drive** | `EnsemblesGoogleDrive` | Google Drive REST API v3 |
| **OneDrive** | `EnsemblesOneDrive` | Microsoft Graph API v1.0 |
| **pCloud** | `EnsemblesPCloud` | pCloud REST API |
| **WebDAV** | `EnsemblesWebDAV` | Any WebDAV server |
| **Encrypted** | `EnsemblesEncrypted` | Encryption wrapper for any backend |

## Quick Start — Core Data

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
        ubiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp"
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

Set `autoSyncPolicy` to `.manual` to disable all automatic syncing and call `sync()` yourself.

For more control, use `CoreDataEnsemble` directly — see the [Getting Started guide](https://mentalfaculty.github.io/Ensembles3/Ensembles/documentation/ensembles/gettingstarted).

## Quick Start — SwiftData

```swift
import EnsemblesSwiftData
import EnsemblesCloudKit

// The store is placed automatically at Application Support/MainStore.sqlite
let container = SwiftDataEnsembleContainer(
    name: "MainStore",
    modelTypes: [Item.self, Tag.self],
    cloudFileSystem: CloudKitFileSystem(
        ubiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp"
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

## How It Works

Ensembles uses an event-sourcing architecture. Every save to your Core Data store is recorded as an event. Events are exported to the cloud as files, downloaded on other devices, and replayed into each local store.

1. **Attach** — `attachPersistentStore()` sets up local sync metadata, imports the persistent store contents into an event log, and registers the device in the cloud.

2. **Save** — When the app saves to the monitored store, Ensembles automatically captures the inserted, updated, and deleted objects as a `StoreModificationEvent`.

3. **Sync** — `sync()` downloads remote events from the cloud, replays them into the local store (resolving conflicts via revision tracking), and uploads new local events.

4. **Delegate** — Implement `CoreDataEnsembleDelegate` to merge save notifications into your main context, handle forced detaches, provide global identifiers for deduplication, and repair data before merge saves.

5. **Detach** — `detachPersistentStore()` removes local sync data and unregisters from the cloud. The persistent store itself is not affected.

## Authentication

Each backend handles authentication differently. Backends that communicate via REST API include built-in authenticator classes.

| Backend | Auth Method | Credentials From |
|---------|------------|-----------------|
| CloudKit | Implicit iCloud account | No setup needed |
| Google Drive | `GoogleDriveAuthenticator` (OAuth 2.0) | [Google Cloud Console](https://console.cloud.google.com/) |
| OneDrive | `OneDriveAuthenticator` (OAuth 2.0) | [Azure Portal](https://portal.azure.com/) |
| pCloud | `PCloudAuthenticator` (OAuth 2.0 token flow) | [my.pcloud.com](https://my.pcloud.com/) |
| WebDAV | Username / password | Your WebDAV server |

### Authenticator-Based Backends (Google Drive, OneDrive, pCloud)

These backends include a companion `*Authenticator` class that handles the full OAuth flow, stores tokens in the Keychain, and (for Google/OneDrive) automatically refreshes expired tokens. pCloud tokens do not expire.

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

All three also accept a static access token for cases where you manage tokens externally:

```swift
let cloudFS = GoogleDriveCloudFileSystem(accessToken: "your-token")
```

See each backend's class documentation for detailed setup instructions and code examples.

## Custom Cloud Backends

Any storage that can hold files at paths can serve as a backend. Implement the `CloudFileSystem` protocol — just 8 methods covering connection, file existence, directory listing, upload, download, and deletion. See the [DocC documentation](https://mentalfaculty.github.io/Ensembles3/Ensembles/documentation/ensembles/customcloudbackends) for a full guide and reference implementations.

## Global Identifiers

When two devices independently create the "same" object (e.g., a tag with the same name), Ensembles needs a **global identifier** to recognize they represent the same entity and merge them instead of duplicating. Without global identifiers, each device's copy is treated as a separate object.

Global identifiers are essential for reference data, categories, and any entity where independent creation of "the same" object is likely. Entities that are always created explicitly by the user (notes, photos) typically don't need them.

## Backward Compatibility

Ensembles 3 is fully backward compatible with Ensembles 2 sync data, including:
- Core Data event store model
- Cloud file formats and directory structure
- CloudKit record structures
- Property change value archives

Existing Ensembles 2 apps can migrate to Ensembles 3 without a data reset.

### Compatibility Mode

If you're transitioning from Ensembles 2 and some users may still be running the E2 version, set the compatibility mode to restrict exports to E2-parseable formats:

```swift
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
```

Once all users have upgraded to E3, switch to `.ensembles3` (the default) to unlock future E3-only features.

## Example Apps

The source repository includes three sample apps demonstrating different integration patterns:

- **[SimpleSyncCoreData](https://github.com/mentalfaculty/Ensembles3-Source/tree/main/Examples/SimpleSyncCoreData)** — Core Data + LocalCloudFileSystem. Two side-by-side panels simulate different devices syncing via a shared local directory. Shows `CoreDataEnsembleContainer` setup, `Syncable` conformance, and manual sync triggers. Minimal SwiftUI.

- **[SimpleSyncSwiftData](https://github.com/mentalfaculty/Ensembles3-Source/tree/main/Examples/SimpleSyncSwiftData)** — SwiftData + LocalCloudFileSystem. Same dual-panel design as above, using `SwiftDataEnsembleContainer` and `@Model` types with `Syncable`. Demonstrates how to inject the synced `ModelContainer` into SwiftUI.

- **[Idiomatic](https://github.com/mentalfaculty/Ensembles3-Source/tree/main/Examples/Idiomatic)** — A full-featured SwiftData note-taking app syncing via CloudKit. Shows a realistic production setup: CloudKit entitlements, container configuration, error handling, and user-visible sync status.

## Licensing

CloudKit, LocalFile, Memory, and SwiftData backends are **free to use** with no license required. All other backends (Google Drive, OneDrive, pCloud, WebDAV, Encrypted) require a license key.

Activate a license key at app launch:

```swift
import Ensembles

EnsemblesLicense.activate("your-license-key")
```

A subscription covers all SDK versions released during the subscription period. Deployed apps continue working forever — there is no runtime expiry.

Free trials are available at [ensembles.io](https://ensembles.io).

## Documentation

[**Browse the documentation online**](https://mentalfaculty.github.io/Ensembles3/Ensembles/documentation/ensembles/)

Full API documentation is generated with DocC and includes articles on getting started, architecture, conflict resolution, custom cloud backends, and SwiftData integration.

## Support

- Email: support@mentalfaculty.com
- Issues: https://github.com/mentalfaculty/Ensembles3/issues
