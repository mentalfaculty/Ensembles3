---
title: "Ensembles 3: The Complete Guide"
author: "Drew McCormack"
date: "2026"
---

\newpage

# Preface

Ensembles has been a local-first sync framework for Core Data since 2013 — "local-first" meaning your app's data lives on the device as the primary copy, and the cloud is just a way to exchange changes between peers. It was born out of frustration with Apple's iCloud-Core Data integration, which had a habit of silently losing data and creating duplicates. I needed something better for my own apps, and when I released it, it turned out other developers needed it too. Hundreds of apps on the App Store have shipped with Ensembles over the years, from personal finance apps to music tools to productivity software.

The first two versions were written in Objective-C. They worked well, but the Apple development landscape has changed a lot since then. Swift is now the language. Structured concurrency has replaced completion handler pyramids. SwiftData has arrived alongside Core Data. The Objective-C codebase was increasingly hard to maintain, and every time I wanted to fix a threading issue or add a feature, I found myself fighting the language rather than the problem.

So I rewrote it from scratch in pure Swift.

Ensembles 3 preserves everything that made the framework valuable — the event-sourcing architecture, the pluggable backends, the deterministic conflict resolution, the philosophy of keeping your data under your control — while taking full advantage of modern Swift. Async/await replaces completion handlers. Actors and structured concurrency replace dispatch queues and operation queues. Swift Package Manager replaces CocoaPods. And SwiftData support sits right alongside Core Data, as a first-class citizen.

If you're coming from Ensembles 2, the migration is straightforward — the cloud data format is fully backward compatible, and a compatibility mode lets old and new peers coexist during the transition. There's a chapter at the end of this book dedicated to the migration process.

If you're new to Ensembles, welcome. This book will walk you through everything: the mental model, the API, the gotchas, and the strategies that experienced Ensembles developers have learned over the years.

\newpage

# Introducing Ensembles

## What's in a Name?

The name "Ensembles" comes from music. In a musical ensemble, independent musicians play their own parts, listening to each other and adjusting in real time to produce a coherent performance. No single musician controls the others. There's no central conductor dictating every note. Each player has autonomy, but through a shared understanding of the piece, they converge on a coherent whole.

That's the model behind Ensembles. Each device is an independent player. It has its own complete copy of the data — it can read, write, and operate entirely on its own, even offline. When devices come into contact (through a shared cloud backend), they exchange their recent changes, listen to what the others have done, and adjust to reach a consistent state. No central server owns the truth. No device is subordinate to another. They are peers in an ensemble.

This is what's known as *local-first* architecture, and it's the idea at the core of everything Ensembles does.

## What Is Ensembles?

Ensembles is a local-first sync framework for Core Data and SwiftData apps on Apple platforms. You add it to your project, point it at a cloud storage backend, and it handles the mechanics of keeping your persistent store in sync across devices.

Under the hood, it works by recording every change to your persistent store as an *event* — a compact representation of what was inserted, updated, or deleted. These events are exchanged between devices through files stored in the cloud. When a device receives new events from other peers, it replays them into the local store, resolving any conflicts along the way.

The key insight is that Ensembles never touches your cloud data in a way that requires server-side logic. It stores opaque files — the cloud backend is just a dumb file system. This means you can use *any* storage service: iCloud (via CloudKit), Google Drive, OneDrive, Dropbox, pCloud, Amazon S3, Box, WebDAV, or even a shared local folder. You can encrypt everything end-to-end before it ever leaves the device. You can switch backends without losing data. And because the cloud is just file storage, there's no vendor lock-in and no server to maintain.

## Design Goals

I designed Ensembles with a specific set of goals in mind. Understanding these goals will help you understand why the framework works the way it does, and will guide you when you encounter design decisions in your own app.

### Minimal Changes to Your App

Adding local-first sync to an existing Core Data or SwiftData app should require as little code as possible. You shouldn't need to change your data model, restructure your view controllers, or adopt a new persistence layer. Ensembles works with your existing `NSPersistentStore` or `ModelContainer` — you create an ensemble, attach it, and sync. The rest of your app stays the same.

### Peer-to-Peer Intelligence

Ensembles is peer-to-peer: there is no central server that understands your data. Every device is equal. Each device independently decides how to merge incoming changes with its local state. The cloud is just a transport mechanism — a shared folder where devices drop off and pick up files. This means sync works the same whether you have two devices or twenty, and the system scales naturally without any server-side infrastructure.

### Backend Agnostic

A local-first framework shouldn't lock your data into any particular cloud service. Ensembles defines a `CloudFileSystem` protocol — a simple interface for uploading, downloading, and listing files — and every backend implements it. Want to switch from CloudKit to Google Drive? Change one line of code. Want to let users choose their own backend? Give them a picker. The sync logic doesn't care where the files live.

### Future Proof

Cloud services come and go. APIs change. Companies get acquired. A local-first framework should protect you from that churn. By keeping the cloud layer as simple as possible (just files and directories), Ensembles insulates your data from the cloud industry's instability. Even if a backend disappears, you can migrate to another service simply by attaching the ensemble to a new cloud file system.

### Immutable Cloud Files

Once Ensembles writes a file to the cloud, it never modifies it in place. Files are either created or deleted, never updated. This eliminates an entire class of sync bugs related to partial writes, race conditions, and file locking. It also means the cloud data is inherently safe: even if something goes wrong during a sync, the existing files are untouched.

### Real-Time Testability

Sync is notoriously hard to test, but Ensembles is designed to make it straightforward. The in-memory backend (`MemoryCloudFileSystem`) lets you set up multi-device simulations in unit tests with no disk I/O and no network calls. You can create two ensembles sharing the same in-memory cloud, make changes on each, sync them, and verify the results — all in milliseconds.

### Eventual Consistency

Ensembles guarantees *eventual consistency*: if all devices sync, they will all converge on the same state. It does not guarantee immediate consistency — there's always a window where devices may have different views of the data. This is an inherent property of any distributed system without a central coordinator, and it's a reasonable trade-off for a local-first framework.

### Conflict Resolution in the Spirit of Core Data

Core Data has a built-in merge policy system (e.g., `NSMergeByPropertyObjectTrumpMergePolicy`) that resolves conflicts at the attribute level. Ensembles follows the same philosophy: conflicts are resolved per-attribute, not per-object, so a change to `title` on one device and a change to `body` on another are both preserved. For truly concurrent changes to the same attribute, the most recent value wins. This matches what Core Data developers already expect.

### The Store Is Never Invalid

During integration, Ensembles carefully stages its operations (inserts, then updates, then deletes) and validates the result before committing. If the merge would produce an invalid state (e.g., a validation error), the delegate is called and given a chance to repair the data. The save to your persistent store is atomic — it either succeeds completely or not at all.

### Efficient Handling of Binary Data

Large binary attributes (photos, documents) are stored as separate data files in the cloud, not inlined into event data. Ensembles ensures all required data files are present before integrating changes, so your app never sees a reference to a file that hasn't been downloaded yet.

### Small Cloud Footprint

Event history doesn't grow without bound. Ensembles periodically consolidates old events into *baselines* — compact snapshots that represent the full state at a point in time. Once a baseline is established, the events it supersedes can be deleted from the cloud. This keeps storage costs low and sync times fast.

### Graceful Model Versioning

When a device running a newer model version syncs with one running an older version, Ensembles handles it gracefully. Events from unknown model versions are stored but not integrated — no data is lost. When the older device eventually updates, those events are seamlessly incorporated. You can even use the error code to prompt users to update the app.

## How Does It Work?

Let me walk you through the mechanics of how Ensembles keeps data in sync. Don't worry about memorizing all of this — the framework handles it automatically. But understanding the big picture will help you reason about sync behavior in your app.

### Transaction Logs

The core idea is simple: every save to your persistent store is recorded as a *transaction log entry* (which Ensembles calls a *store modification event*). An event captures the complete set of changes from a single save — every inserted object, every updated attribute, every deleted object — along with metadata about which device made the change and what it knew about other devices' changes at the time.

Here's a simplified view of what an event looks like internally:

```json
{
  "type": 0,
  "globalCount": 42,
  "timestamp": 1710500000.0,
  "modelVersion": "abc123",
  "revisions": [
    {"persistentStoreIdentifier": "device-A", "revisionNumber": 12},
    {"persistentStoreIdentifier": "device-B", "revisionNumber": 7}
  ],
  "changes": [
    {
      "entity": "Note",
      "type": "insert",
      "globalIdentifier": "note-uuid-1",
      "propertyChanges": {
        "title": {"value": "Meeting Notes"},
        "body": {"value": "Discussed Q3 roadmap..."},
        "createdAt": {"value": 1710500000.0}
      }
    },
    {
      "entity": "Tag",
      "type": "update",
      "globalIdentifier": "work",
      "propertyChanges": {
        "notes": {"addedIdentifiers": ["note-uuid-1"]}
      }
    }
  ]
}
```

The `revisions` array is the key to conflict resolution. It records which events from each peer this device had seen at the time of the save. This creates a *causal ordering* — if device B's event includes device A's revision 12, then B's event "happened after" A's event 12, and B's values should take precedence over A's for any conflicting attributes.

### The Big Picture

Here's how data flows through the system:

![Data flow diagram](dataflow.png){width=100%}\

**Saving** (left to center): When your app saves to the persistent store, Ensembles intercepts the save notification and records the changes in the event store — a separate SQLite database that Ensembles manages.

**Exporting** (center to right): During a sync, new events are serialized to files and uploaded to the cloud backend.

**Importing** (right to center): The sync also checks for new files in the cloud from other devices and downloads them into the local event store.

**Integrating** (center to left): Finally, remote events are replayed into your persistent store — inserting new objects, updating changed attributes, and deleting removed objects. The merge save triggers a notification so your UI can refresh.

### The Event Store

The event store is a SQLite database that Ensembles manages alongside your app's persistent store. It lives in a separate directory (by default, inside Application Support) and stores:

- **Events** — The transaction log entries for local and remote changes.
- **Data files** — Binary blobs referenced by events (e.g., external storage data).
- **Baselines** — Compact snapshots used to compress history.
- **Revision metadata** — Tracking information for each known peer.

You never interact with the event store directly. Ensembles creates, migrates, and manages it automatically.

### Cloud File Systems

The cloud backend is just a file system. Ensembles creates a directory structure in the cloud:

```
/ensembles/{ensemble-identifier}/
    /events/        — Event files from all devices
    /baselines/     — Baseline snapshots
    /data/          — Binary data files
    /stores/        — Device registrations
```

Every backend — CloudKit, Google Drive, your custom backend — stores files in this same structure. The sync logic doesn't know or care what's underneath.

### Attaching

Before an ensemble can sync, it must be *attached*. Attaching is a one-time setup step that:

1. Creates the event store database.
2. Sets up the cloud directory structure.
3. Imports the existing contents of your persistent store as the first event.
4. Registers this device as a peer in the cloud.

After attaching, the ensemble stays attached across app launches. You only need to attach once (unless a forced detach occurs).

### Syncing

A sync is the main operation that keeps devices in step. It runs through several phases: connecting to the cloud, importing new files, consolidating baselines, integrating remote events into your store, exporting local events, and cleaning up old files. All of this happens in a single `await ensemble.sync()` call.

### Baselining

Over time, the event history grows. If every event since the beginning of time had to be replayed on a new device, sync would become slower and slower. Baselines solve this by capturing a complete snapshot of the store at a point in time. Once all devices have acknowledged a baseline, the events it covers can be deleted. This keeps sync data compact and sync times fast, regardless of how long the app has been in use.

## Ensembles vs. The Rest

You might be wondering how Ensembles compares to other sync solutions. Let me give you a brief tour of the landscape.

**Apple's iCloud-Core Data Integration** — This was Apple's original attempt at syncing Core Data over iCloud, introduced in iOS 5. It was deprecated and removed because it was unreliable. If you were burned by it, you're not alone — it's one of the reasons Ensembles exists.

**CloudKit Direct (CKRecord)** — You can use CloudKit's record-based API directly, mapping your model to `CKRecord` instances. This works, but you're building a sync engine from scratch: conflict resolution, relationship handling, offline support, migration — all on you. It also locks you into iCloud.

**NSPersistentCloudKitContainer / SwiftData CloudKit Sync** — Apple's built-in Core Data and SwiftData sync with CloudKit (SwiftData uses `NSPersistentCloudKitContainer` under the hood). Convenient if it fits your needs, but it's a black box: you can't customize conflict resolution, you can't switch backends, you can't encrypt data, and debugging sync issues can be difficult. CloudKit only.

**CloudKit Sync Engine** — Introduced at WWDC 2023, `CKSyncEngine` is Apple's lower-level alternative to `NSPersistentCloudKitContainer`. It gives you more control over the sync process — you handle the mapping between your model and `CKRecord` yourself — but it's still CloudKit-only, still server-mediated, and still requires you to implement conflict resolution and relationship handling. It's a better building block than raw CloudKit, but you're still building a sync engine on top of it.

**Firebase / Firestore** — Google's real-time database. Powerful, but it's server-mediated (Google sees all your data), requires a Google account, and uses its own data model — you can't use Core Data or SwiftData natively.

**Realm / Atlas Device Sync (MongoDB)** — Realm provides its own persistence layer with built-in sync to MongoDB Atlas. Adopting it means replacing Core Data entirely, and your data lives on MongoDB's servers.

**Ensembles** — Local-first and peer-to-peer. Works with your existing Core Data or SwiftData stack. Pluggable backends (14 built in). End-to-end encryption. No server-side logic. No vendor lock-in. Full control over conflict resolution. You own your data.

The trade-off with any local-first system is that Ensembles is *eventually* consistent, not real-time. Changes propagate on sync, not instantly. For most apps — note-taking, task management, personal databases, creative tools — this is perfectly fine. If you need sub-second real-time collaboration (like a multiplayer game or collaborative text editor), you need a different tool.

\newpage

# Getting Started

## Installation

Ensembles 3 is distributed as a Swift package. Add it to your Xcode project or `Package.swift`:

**Xcode:** File > Add Package Dependencies > enter the repository URL.

**Package.swift:**

```swift
dependencies: [
    .package(
        url: "https://github.com/mentalfaculty/Ensembles3",
        from: "3.0.0"
    )
]
```

Then add the targets you need to your app target's dependencies:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "EnsemblesCloudKit", package: "Ensembles3"),
    ]
)
```

Each backend is a separate target. You only import what you use — the rest is never compiled or linked. The available targets are:

| Target | Backend | External Deps |
|--------|---------|---------------|
| `Ensembles` | Core framework | None |
| `EnsemblesSwiftData` | SwiftData integration | None |
| `EnsemblesCloudKit` | CloudKit (iCloud) | None |
| `EnsemblesiCloudDrive` | iCloud Drive (legacy) | None |
| `EnsemblesLocalFile` | Local filesystem | None |
| `EnsemblesMemory` | In-memory (testing) | None |
| `EnsemblesGoogleDrive` | Google Drive | None |
| `EnsemblesOneDrive` | OneDrive | None |
| `EnsemblesPCloud` | pCloud | None |
| `EnsemblesWebDAV` | WebDAV | None |
| `EnsemblesEncrypted` | Encryption wrapper | None |
| `EnsemblesDropbox` | Dropbox | SwiftyDropbox |
| `EnsemblesS3` | Amazon S3 | aws-sdk-swift |
| `EnsemblesBox` | Box | BoxSDK |
| `EnsemblesZip` | Zip compression | ZIPFoundation |
| `EnsemblesMultipeer` | Multipeer Connectivity | ZIPFoundation |

Every submodule re-exports the core `Ensembles` module, so a single import like `import EnsemblesCloudKit` gives you access to everything: `CoreDataEnsemble`, `Syncable`, `CloudFileSystem`, and all the rest.

### Package Traits

The last five targets in the table above (Dropbox, S3, Box, Zip, Multipeer) depend on external packages. To avoid downloading those dependencies when you don't need them, they're gated behind Swift Package Manager *traits* (SE-0450, Swift 6.1+).

To enable a trait:

```swift
.package(
    url: "https://github.com/mentalfaculty/Ensembles3",
    from: "3.0.0",
    traits: ["Dropbox", "Zip"]
)
```

If you don't specify any traits, only the core targets (no external dependencies) are available.

### Platform Requirements

Ensembles 3 supports iOS 16+, macOS 13+, tvOS 16+, and watchOS 9+. SwiftData support requires iOS 17+ / macOS 14+ / tvOS 17+ / watchOS 10+.

The package requires Swift 6.1+ for traits. Swift 6.0+ is sufficient for strict concurrency if you don't use trait-gated targets.

## Example Apps

The repository includes three example apps that demonstrate different integration patterns:

**SimpleSyncCoreData** — A minimal Core Data app using `LocalCloudFileSystem`. Two side-by-side panels simulate different devices syncing through a shared folder. Great for understanding the basics.

**SimpleSyncSwiftData** — The same concept, but with SwiftData. Shows how `SwiftDataEnsembleContainer` integrates with SwiftUI's `@Query`.

**Idiomatic** — A full-featured SwiftData note-taking app that syncs via CloudKit. This is the closest to what a real shipping app looks like: proper error handling, background sync, UI feedback during sync, and a polished user experience.

I recommend running the simple sync examples first. They use a local filesystem backend, so there's no cloud setup required — just build and run.

\newpage

# Quick Start

You don't like to waste time. I get it. So what's keeping you?

## Ensemble, Attach, Sync, Enjoy

The core workflow has four steps — **EASE**:

1. **Ensemble** — Create an ensemble (or a container that wraps one)
2. **Attach** — Connect it to the persistent store and cloud
3. **Sync** — Exchange changes with other devices
4. **Enjoy** — That's it. You're syncing.

Let's see both ways of doing this.

## The Container Way (Recommended)

The simplest path is to use a container class. It creates the Core Data or SwiftData stack for you, sets up a delegate internally, and syncs automatically on save, on app activation, and on a timer. For most apps, this is all you need.

### Core Data Container

```swift
import EnsemblesCloudKit

let container = CoreDataEnsembleContainer(
    name: "MainStore",
    modelURL: Bundle.main.url(
        forResource: "Model", withExtension: "momd"
    )!,
    cloudFileSystem: CloudKitFileSystem(
        privateDatabaseForUbiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp",
        schemaVersion: .v2
    )
)!

// Use container.viewContext for your UI
```

That's it. The container creates an `NSPersistentStoreCoordinator`, loads your model, adds a persistent store, creates a `CoreDataEnsemble`, attaches it, and starts syncing — all from those five lines. Remote changes are merged into `viewContext` automatically.

### SwiftData Container

```swift
import EnsemblesSwiftData
import EnsemblesCloudKit

let container = SwiftDataEnsembleContainer(
    name: "MainStore",
    modelTypes: [Note.self, Tag.self],
    cloudFileSystem: CloudKitFileSystem(
        privateDatabaseForUbiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp",
        schemaVersion: .v2
    )
)!

// Use container.modelContainer with SwiftUI
ContentView()
    .modelContainer(container.modelContainer)
```

SwiftData support requires iOS 17+ / macOS 14+. Your `@Query` properties update automatically when remote changes arrive, because the container enables persistent history tracking under the hood.

### Configuring the Container

Both containers accept an `EnsembleContainerConfiguration` for fine-tuning:

```swift
let config = EnsembleContainerConfiguration(
    autoSyncPolicy: [.onSave, .onActivation, .onTimer],
    timerInterval: 120,           // seconds between timer syncs
    seedPolicy: .mergeAllData,
    compatibilityMode: .ensembles3
)

let container = CoreDataEnsembleContainer(
    name: "MainStore",
    modelURL: modelURL,
    cloudFileSystem: cloudFS,
    configuration: config
)!
```

Set `autoSyncPolicy` to `.manual` if you want to control sync timing yourself and call `container.sync()` explicitly.

## The Manual Way (CoreDataEnsemble)

For more control over the sync lifecycle — when to attach, when to sync, how to handle delegate callbacks — use `CoreDataEnsemble` directly.

### Create

```swift
import EnsemblesCloudKit

let cloudFS = CloudKitFileSystem(
    privateDatabaseForUbiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp",
    schemaVersion: .v2
)

let ensemble = CoreDataEnsemble(
    ensembleIdentifier: "MainStore",
    persistentStoreURL: storeURL,
    managedObjectModelURL: modelURL,
    cloudFileSystem: cloudFS
)
ensemble?.delegate = self
```

The `ensembleIdentifier` must be the same string on all devices that should sync together. If your app has multiple persistent stores, create one ensemble per store with a unique identifier.

### Attach

```swift
try await ensemble?.attachPersistentStore()
```

Attaching is typically a one-time operation. It sets up local sync metadata and performs an initial import of data in the persistent store. Once attached, an ensemble stays attached across app relaunches.

You can check the current state with `ensemble?.isAttached`.

> **Important:** Avoid saving to the persistent store while attaching. If a save is detected during attachment, the operation will fail with an error and you'll need to retry.

### Sync

```swift
try await ensemble?.sync()
```

A sync downloads new events from the cloud, integrates remote changes into the persistent store, and uploads new local events. When remote changes are integrated, the ensemble saves them to the persistent store and calls the delegate so you can update your UI:

```swift
extension SyncController: CoreDataEnsembleDelegate {
    func coreDataEnsemble(
        _ ensemble: CoreDataEnsemble,
        didSaveMergeChangesWith notification: Notification
    ) {
        viewContext.perform {
            self.viewContext.mergeChanges(
                fromContextDidSave: notification
            )
        }
    }
}
```

### SwiftData (Manual Way)

If you want manual control with SwiftData, use `SwiftDataEnsemble`:

```swift
import EnsemblesSwiftData
import EnsemblesCloudKit

let ensemble = SwiftDataEnsemble(
    ensembleIdentifier: "MainStore",
    persistentStoreURL: storeURL,
    modelTypes: [Note.self, Tag.self],
    cloudFileSystem: cloudFS
)

try await ensemble?.attachPersistentStore()
try await ensemble?.sync()
```

`SwiftDataEnsemble` wraps a `CoreDataEnsemble` internally and provides closure-based callbacks instead of a delegate protocol:

```swift
ensemble?.didSaveMergeChanges = { notification in
    // SwiftData with persistent history tracking
    // handles this automatically in most cases
}
```

## Global Identifiers

The steps above are all you need for basic sync. But there's one more concept that's important to understand early: global identifiers.

By default, Ensembles generates random identifiers for every object. This means if two devices each create a "Work" tag independently, you'll end up with two "Work" tags after sync. Global identifiers tell Ensembles that these are the same logical object, so it can merge them instead of duplicating.

### The Syncable Protocol

The simplest way to provide identifiers is through the `Syncable` protocol:

```swift
// Core Data
class Tag: NSManagedObject, Syncable {
    static let globalIdentifierKey = "uniqueID"
    @NSManaged var uniqueID: String
    @NSManaged var name: String
}

// SwiftData
@Model
class Tag: Syncable {
    static let globalIdentifierKey = "uniqueID"
    var uniqueID: String
    var name: String

    init(name: String) {
        self.uniqueID = name  // Use the name as the identifier
        self.name = name
    }
}
```

The ensemble discovers `Syncable` conformances automatically at initialization — no registration needed.

### Choosing Identifiers

For most objects, a random UUID assigned at creation is the best choice. But for certain entities, a *meaningful* identifier works better:

- **Singleton objects** (e.g., settings): Use a fixed string like `"AppSettings"`.
- **Tags or categories**: Use the name as the identifier. Two "Work" tags merge into one.
- **Reference data from a fixed set**: Use the canonical name (e.g., `"Red"`, `"Blue"`).

The rule: global identifiers must be **immutable**. Once assigned, never change them. If you need a different identifier, delete the object and create a new one.

### The Delegate Method

If `Syncable` doesn't fit (e.g., the identifier depends on multiple properties), use the delegate:

```swift
func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    globalIdentifiersForManagedObjects objects: [NSManagedObject]
) -> [String?] {
    objects.map { object in
        if let tag = object as? Tag {
            return tag.name
        }
        return (object as? Note)?.uniqueID
    }
}
```

Return `nil` for any object that should get a random identifier.

### Identifiers Must Be Unique Per Entity

Global identifiers need to be unique *within* an entity. You can reuse the same identifier across different entities. A `Cat` and a `Dog` can both have the identifier `"snoopy"`, but you shouldn't have two `Dog` objects with that identifier.

\newpage

# The Ensemble

The most important class in the framework is `CoreDataEnsemble`. Everything else exists to support it. This chapter covers the ensemble's lifecycle, states, and the delegate protocol in detail.

## Creating an Ensemble

An ensemble is created for a specific persistent store. The designated initializer takes:

- **`ensembleIdentifier`** — A string that identifies this sync group. All devices that should sync together must use the same identifier.
- **`persistentStoreURL`** — The URL of the SQLite store file.
- **`managedObjectModel`** — The `NSManagedObjectModel` for the store.
- **`cloudFileSystem`** — The backend to use for cloud storage.

```swift
let ensemble = CoreDataEnsemble(
    ensembleIdentifier: "MainStore",
    persistentStoreURL: storeURL,
    managedObjectModel: model,
    managedObjectModels: [modelV1, modelV2],
    cloudFileSystem: cloudFS
)
```

The `managedObjectModels` parameter is optional but recommended. It provides all known model versions so Ensembles can recognize events from peers running different schema versions. For URL-based models, the convenience initializers load all versions from the `.momd` bundle automatically:

```swift
let ensemble = CoreDataEnsemble(
    ensembleIdentifier: "MainStore",
    persistentStoreURL: storeURL,
    managedObjectModelURL: modelURL,
    cloudFileSystem: cloudFS
)
```

You can also pass `persistentStoreOptions` (e.g., to set migration options) and `localDataRootDirectoryURL` (to control where event store data is kept).

The initializer is failable — it returns `nil` if the model can't be loaded or the configuration is invalid.

## Lifecycle and States

An ensemble moves through a clear lifecycle:

```
Created -- Attaching -- Attached -- Syncing / Idle -- Detaching -- Detached
```

You can query the current state through several properties:

- **`isAttached`** — `true` once attaching completes successfully.
- **`isAttaching`** — `true` during the attach operation.
- **`isSyncing`** — `true` during a sync operation.
- **`isDetaching`** — `true` during the detach operation.
- **`currentActivity`** — Returns `.none`, `.attaching`, `.syncing`, or `.detaching`.
- **`activityProgress`** — A float from 0.0 to 1.0 indicating progress.

Operations are serialized internally via an `AsyncStream`. You never need to worry about concurrent attaches and syncs — the ensemble queues them and executes them in order.

## The Delegate

The `CoreDataEnsembleDelegate` protocol provides hooks into the sync lifecycle. All methods have default (no-op) implementations, so you only need to implement the ones you care about.

### Merge Notifications

The most commonly implemented delegate method:

```swift
func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    didSaveMergeChangesWith notification: Notification
)
```

Called after the ensemble saves merged changes to the persistent store. Merge this notification into your main context to update the UI:

```swift
func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    didSaveMergeChangesWith notification: Notification
) {
    viewContext.perform {
        self.viewContext.mergeChanges(
            fromContextDidSave: notification
        )
    }
}
```

### Store Import

```swift
func coreDataEnsembleWillImportStore(_ ensemble: CoreDataEnsemble)
func coreDataEnsembleDidImportStore(_ ensemble: CoreDataEnsemble)
```

Called during the initial attach, before and after the persistent store's contents are imported as the first event. Useful if you need to prepare or clean up data before the initial import.

### Merge Inspection and Reparation

```swift
func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    shouldSaveMergedChangesIn savingContext: NSManagedObjectContext,
    reparationContext: NSManagedObjectContext
) -> Bool
```

Called before the merge save. You can inspect `savingContext` to see what will be committed, and make corrections in `reparationContext`. Return `false` to abort the merge entirely. See the Conflict Resolution chapter for details.

### Merge Failure

```swift
func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    didFailToSaveMergedChangesIn savingContext: NSManagedObjectContext,
    error: Error,
    reparationContext: NSManagedObjectContext
) -> Bool
```

Called if the merge save fails (e.g., validation error). Make corrections in `reparationContext` and return `true` to retry.

### Entity-Level Callbacks

```swift
func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    willMergeChangesFor entity: NSEntityDescription
)

func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    didMergeChangesFor entity: NSEntityDescription
)
```

Called before and after each entity is processed during integration. Useful for progress tracking in large stores.

### Forced Detach

```swift
func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    didDetachWithError error: Error
)
```

Called when the ensemble is forced to detach due to an exceptional condition (cloud identity change, data corruption, registration removal). Update your UI and consider re-attaching.

### Global Identifiers

```swift
func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    globalIdentifiersForManagedObjects objects: [NSManagedObject]
) -> [String?]
```

Provides global identifiers for deduplication. Return `nil` for objects that should get random identifiers. See the Quick Start chapter for details.

## Notifications

In addition to the delegate, ensembles post notifications that any part of your app can observe:

- **`.coreDataEnsembleDidBeginActivity`** — An activity (attaching, syncing, detaching) has started.
- **`.coreDataEnsembleDidMakeProgressWithActivity`** — Progress was made. The `userInfo` dictionary contains the current phase (`SyncingPhase` or `AttachingPhase`) and progress fraction.
- **`.coreDataEnsembleWillEndActivity`** — An activity is about to finish. May contain an error in `userInfo`.

These are useful for displaying sync status in your UI — a spinner, a progress bar, or a status label.

## Dismantling

When you're completely done with an ensemble (e.g., the user signed out and you want to release all resources), call `dismantle()`:

```swift
ensemble?.dismantle()
```

This stops internal processing and releases the event store. After dismantling, the ensemble cannot be used again. This is called automatically by `SwiftDataEnsemble`'s `deinit` to prevent resource leaks.

\newpage

# Attaching and Detaching

## What Attaching Does

When you call `attachPersistentStore()`, Ensembles performs a sequence of steps to prepare the device for syncing:

1. **Connects to the cloud** — Calls `connect()` on the cloud file system and verifies the user identity.
2. **Sets up cloud structure** — Creates the directory hierarchy in the cloud if it doesn't exist.
3. **Sets up local structure** — Creates the event store database if it's the first time.
4. **Imports the persistent store** — Walks through every object in your persistent store and records them as the initial event. This is how Ensembles learns about your existing data.
5. **Registers the peer** — Records this device in the cloud so other peers know it exists.

The import step is the most significant. For a large store with thousands of objects, it may take a noticeable amount of time. Subsequent launches skip this step — the ensemble remembers that it's already attached.

## Seed Policies

The `seedPolicy` parameter controls what happens with existing local data during the initial attach:

```swift
try await ensemble?.attachPersistentStore(seedPolicy: .mergeAllData)
```

- **`.mergeAllData`** (default) — All existing objects in the persistent store are imported as the first event. This is almost always what you want. Whether the store is empty (fresh install), already has data (existing app adding sync), or data exists both locally and in the cloud from another device — `.mergeAllData` handles it correctly. If you have global identifiers set up, duplicates are deduplicated automatically.

- **`.excludeLocalData`** — The existing local data is *not* imported. The store starts empty from the ensemble's perspective, and only data from the cloud will be integrated. This is a rarely used option for special cases where you want to discard local data and start fresh from the cloud.

## Detaching

Detaching is the reverse of attaching. Call it when the user wants to stop syncing:

```swift
try await ensemble?.detachPersistentStore()
```

Detaching:

1. Unregisters this device from the cloud.
2. Removes the local event store.
3. Leaves the user's persistent store untouched — their data is still there, just no longer syncing.

After detaching, the ensemble can be re-attached with `attachPersistentStore()` to resume syncing.

## Forced Detaches

In exceptional circumstances, the ensemble may detach itself without being asked:

- **Cloud identity changed** — The user signed out of iCloud or switched accounts. The ensemble can't continue syncing to the wrong account.
- **Data corruption** — The event store or cloud data is in an irrecoverable state.
- **Registration removed** — Another device (or a cleanup operation) removed this device's registration from the cloud.

When a forced detach occurs, the delegate method `coreDataEnsemble(_:didDetachWithError:)` is called. You should update your UI to reflect the detached state and, if appropriate, offer to re-attach.

For containers, set the `didForceDetach` callback:

```swift
container.didForceDetach = { error in
    // Update UI, offer to re-attach
}
```

## Re-Attaching

After a detach (forced or explicit), you can re-attach at any time:

```swift
try await ensemble?.attachPersistentStore()
```

The attach process runs again from scratch — the local data is re-imported, a new registration is created, and syncing resumes. Any data in the persistent store is preserved; only the sync metadata is rebuilt.

\newpage

# Syncing

Syncing is the core operation. A single call to `sync()` orchestrates a sequence of operations that downloads remote changes, merges them with local changes, resolves conflicts, and uploads new data to the cloud. This chapter explains what happens inside that call and how to control the sync process.

## What Happens During a Sync

A sync proceeds through several phases, reported via the `SyncingPhase` enum:

### 1. Preparation

The ensemble connects to the cloud backend (if not already connected), verifies the user identity, and checks that this device is still registered as a peer.

### 2. Data File Retrieval

Binary data files referenced by remote events are downloaded. Ensembles ensures all data files are present *before* integrating changes, so your app never encounters a reference to data that hasn't arrived yet.

### 3. Baseline Retrieval

Baseline snapshots are downloaded from the cloud. Baselines represent the full state of the store at a point in time, allowing old events to be discarded.

### 4. Event Retrieval

New event files from other devices are downloaded and imported into the local event store.

### 5. Baseline Consolidation

If multiple baselines exist (from different peers or different consolidation points), they're merged into a single, more recent baseline. Events that all peers have seen are folded into the baseline.

### 6. Rebasing

As events accumulate, the sync data grows. Rebasing compresses the history by folding old events into the baseline. This runs automatically when Ensembles estimates a significant space saving.

### 7. Event Integration

This is the core merge step. Remote events are replayed into the persistent store in three stages:

- **Insert** — New objects are created.
- **Update** — Attributes and relationships are updated. Conflicts are resolved per-attribute using causal ordering.
- **Delete** — Deleted objects are removed.

After integration, the ensemble saves the merged changes to the persistent store and calls the delegate's `didSaveMergeChangesWith` method.

### 8. Data File Deposition

New local binary data files are uploaded to the cloud.

### 9. Baseline Deposition

If a new baseline was consolidated, it's uploaded.

### 10. Event Deposition

New local events are serialized and uploaded to the cloud.

### 11. File Deletion (Cleanup)

Old cloud files that have been superseded by baselines are deleted to reclaim storage.

### 12. File Contents Merge

If `alwaysMergeFileContent` has been configured, specified local directories are synced with their cloud counterparts. This is an advanced feature for syncing arbitrary file content alongside event data.

## When to Sync

### Automatic Sync (Containers)

`CoreDataEnsembleContainer` and `SwiftDataEnsembleContainer` handle sync timing for you through `AutoSyncPolicy`:

- **`.onSave`** — Syncs after each save to the persistent store. Triggers on the `.monitoredManagedObjectContextSaveChangesWereStored` notification.
- **`.onActivation`** — Syncs when the app comes to the foreground (observes `UIApplication.didBecomeActiveNotification`; iOS and tvOS only).
- **`.onTimer`** — Syncs on a repeating timer. The interval is configurable via `timerInterval` (default: 60 seconds).

The default policy is `.all` (all three), which is appropriate for most apps. You can mix and match:

```swift
let config = EnsembleContainerConfiguration(
    autoSyncPolicy: [.onSave, .onTimer],
    timerInterval: 30
)
```

Set `autoSyncPolicy` to `.manual` to disable all automatic syncing and call `container.sync()` yourself.

### Manual Sync (CoreDataEnsemble)

When using `CoreDataEnsemble` directly, you decide when to sync. Common triggers:

- **App foreground** — Sync when the user returns to the app.
- **Push notification** — If you set up CloudKit push notifications or silent pushes, sync in response.
- **Timer** — A repeating timer ensures regular sync even without user interaction.
- **After saves** — Sync after each save to push changes to the cloud promptly.
- **User request** — A manual "Sync Now" button or pull-to-refresh gesture.

A simple pattern that covers most cases:

```swift
// On app activation
NotificationCenter.default.addObserver(
    forName: UIApplication.didBecomeActiveNotification,
    object: nil, queue: nil
) { _ in
    Task { try? await ensemble?.sync() }
}

// After saves
NotificationCenter.default.addObserver(
    forName: .monitoredManagedObjectContextSaveChangesWereStored,
    object: nil, queue: nil
) { _ in
    Task { try? await ensemble?.sync() }
}
```

Sync errors are typically transient (network issues, temporary cloud outages). Don't alert the user on every error — just retry on the next trigger.

## Sync Options

The `SyncOptions` option set lets you customize individual sync operations:

```swift
// Only download — don't integrate or upload
try await ensemble?.sync(options: .cloudFileRetrievalOnly)

// Only upload — don't download or integrate
try await ensemble?.sync(options: .cloudFileDepositionOnly)

// Force a rebase to compact event history
try await ensemble?.sync(options: .forceRebase)

// Prevent rebasing (e.g., on low battery)
try await ensemble?.sync(options: .suppressRebase)

// Download and integrate, but don't upload
try await ensemble?.sync(options: .suppressCloudFileDeposition)
```

Options can be combined:

```swift
let options: SyncOptions = [.forceRebase, .suppressCloudFileDeposition]
try await ensemble?.sync(options: options)
```

## Background Tasks and Suspend/Resume

On iOS, the system may suspend your app at any time. If this happens during a sync, the work is lost and must be restarted. For apps with large stores or slow networks, this is a real problem.

Ensembles provides suspend/resume support to handle this gracefully:

```swift
let task = UIApplication.shared.beginBackgroundTask {
    // System is about to suspend us — pause the sync
    ensemble?.suspendSync()
}

Task {
    try await ensemble?.sync()
    UIApplication.shared.endBackgroundTask(task)
}
```

When the app gets background time again (or returns to the foreground), resume:

```swift
ensemble?.resumeSync()
```

The sync resumes from where it left off rather than restarting from scratch. This is critical for large syncs — a 50 MB baseline upload that's 80% complete can finish in the next background session rather than starting over.

You can check whether sync is currently suspended via `isSyncSuspended`.

## Monitoring Progress

### Activity Properties

```swift
ensemble?.currentActivity  // .none, .attaching, .syncing, .detaching
ensemble?.activityProgress // 0.0 ... 1.0
```

### Notifications

For real-time UI updates, observe notifications:

```swift
NotificationCenter.default.addObserver(
    forName: .coreDataEnsembleDidBeginActivity,
    object: ensemble, queue: .main
) { notification in
    showSyncSpinner()
}

NotificationCenter.default.addObserver(
    forName: .coreDataEnsembleDidMakeProgressWithActivity,
    object: ensemble, queue: .main
) { notification in
    let phase = notification.userInfo?[EnsembleNotificationKey.activityPhase]
        as? SyncingPhase
    let progress = notification.userInfo?[EnsembleNotificationKey.progressFraction]
        as? Float ?? 0
    updateProgressBar(progress, phase: phase)
}

NotificationCenter.default.addObserver(
    forName: .coreDataEnsembleWillEndActivity,
    object: ensemble, queue: .main
) { notification in
    let error = notification.userInfo?[EnsembleNotificationKey.activityError]
        as? Error
    hideSyncSpinner(error: error)
}
```

\newpage

# Saving

Every time your app saves to the persistent store, Ensembles records the changes. Understanding how this works will help you avoid subtle bugs and design your save strategy for optimal sync performance.

## How Saves Are Monitored

Ensembles tracks changes by observing `NSManagedObjectContextDidSave` notifications for any context that saves directly to the monitored persistent store.

When a save occurs, the framework:

1. **Captures pre-save state** — Before the save, Ensembles snapshots to-many relationships. This is necessary because post-save notifications don't provide enough information about relationship changes (they only tell you which objects changed, not the before-and-after of the relationship).

2. **Records changes** — On `NSManagedObjectContextDidSave`, Ensembles generates property change records for all inserted, updated, and deleted objects.

3. **Stores the event** — The changes are written to the event store with a timestamp and revision number.

The saved changes don't become available to other devices until the next `sync()`, when they're exported to the cloud.

## The Cost of Saving

Because Ensembles records every change, saves are more expensive than without sync. Effectively, data is written twice: once to your persistent store and once to the event store. For most apps, the impact is negligible — the event data is compact (just property names and values, not full object graphs).

However, if your app performs very frequent saves (multiple times per second) or very large saves (thousands of objects at once), you should be aware of the overhead. Strategies to manage it:

- **Batch updates into fewer saves.** Ten changes in one save produce one compact event. Ten individual saves produce ten events.
- **Don't save on every keystroke.** Debounce text input and save when editing ends.
- **Use `CDEIgnoredKey`** on properties that change frequently but don't need to sync (see the Models chapter).

## Changes Don't Exist Until Saved

This is important: Ensembles only sees changes when they're *saved* to the persistent store. An object that exists in memory but hasn't been saved is invisible to the sync system.

This creates a potential race condition. Imagine: the user creates a "Work" tag on device A but hasn't saved yet. Meanwhile, device A syncs and imports a "Work" tag from device B. Now there are two "Work" tags — one in memory (unsaved) and one just imported. When device A finally saves, it creates a second event with a "Work" tag, and you end up with duplicates.

This race condition only affects objects with meaningful global identifiers (tags, categories, singletons) where the same logical object might be created on multiple devices. For objects with random UUID identifiers, duplicates are harmless because they'll never match.

**Strategies to avoid race conditions:**

- **Save promptly** after creating objects with meaningful identifiers.
- **Use containers**, which handle sync timing to minimize the window.
- **If using `CoreDataEnsemble` directly**, avoid triggering a sync while there are unsaved changes with meaningful identifiers.

## Accidental Duplicates

Another subtle issue: if you delete an object with global identifier "work" and then — in the same save — insert a new object with the same identifier, the save produces both a deletion and an insertion with the same identifier. Ensembles can't determine the intended ordering within a single save.

The solution is to save between the delete and the insert:

```swift
context.delete(oldTag)
try context.save()

let newTag = Tag(context: context)
newTag.uniqueID = "work"
newTag.name = "Work"
try context.save()
```

## Notifications

Ensembles fires two additional notifications related to saves:

- **`.monitoredManagedObjectContextWillSave`** — Fired when Ensembles determines the saving context will modify the persistent store, before it captures pre-save state. The notification object is the saving context.

- **`.monitoredManagedObjectContextSaveChangesWereStored`** — Fired after Ensembles has finished writing the event to the event store. This is the ideal trigger for an automatic sync, because at this point the changes are fully recorded and ready to export.

Both notifications include the saving context as the notification object.

## Processing Pending Changes

On iOS, the app may be suspended before Ensembles finishes writing event data. Call `processPendingChanges()` — for example, in a background task — to ensure all changes are fully stored before the app goes to sleep:

```swift
let task = UIApplication.shared.beginBackgroundTask { }
Task {
    try await ensemble?.processPendingChanges()
    UIApplication.shared.endBackgroundTask(task)
}
```

This is less of a concern if you're using containers, which handle this automatically through their auto-sync policies.

## Termination Handling

If the app is terminated abruptly (force quit, crash, system kill), any unsaved changes in your context are lost — that's normal Core Data behavior. But what about events that were recorded in the event store but not yet exported to the cloud?

Those events are safe. They're stored in the event store's SQLite database, which is flushed to disk on each write. The next time the app launches and syncs, those events will be exported normally. No data is lost.

\newpage

# Models

Not all data models sync equally well. Some patterns that work fine in a single-device app can cause subtle problems with sync. This chapter covers how to design models that work well with Ensembles, handle binary data, manage migrations, and provide global identifiers.

## Designing for Sync

### Avoid Cross-Attribute Invariants

If two attributes must satisfy an invariant — say, `startDate` must be before `endDate` — concurrent changes to those attributes on different devices can violate it. Device A changes `startDate` to March 15. Device B changes `endDate` to March 10. After sync, you have `startDate = March 15` and `endDate = March 10`. Neither change was wrong in isolation, but the combination is invalid.

The solution is to restructure the data so each attribute is independent:

- Store `startDate` and `duration` instead of `startDate` and `endDate`.
- Use a computed property for `endDate`.

In general, if two attributes have a dependency, find a representation where each attribute can change independently without violating the constraint.

### Avoid Accumulating Attributes

I like to call these "counter attributes." An attribute like `totalCount` that gets incremented on every change doesn't sync well. If device A increments from 5 to 6 and device B also increments from 5 to 6, the merged result is 6 — not 7. Ensembles uses last-writer-wins for attribute conflicts, which means one increment is silently lost.

The solution is to model each change as a separate object:

```swift
// Instead of this:
class Account: NSManagedObject {
    @NSManaged var balance: Double  // Doesn't sync well
}

// Do this:
class Account: NSManagedObject {
    @NSManaged var transactions: Set<Transaction>
    var balance: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }
}

class Transaction: NSManagedObject {
    @NSManaged var amount: Double
    @NSManaged var account: Account
}
```

Each transaction is an independent object that syncs cleanly. The balance is computed from the set of all transactions, and to-many relationships use add-wins semantics, so no transactions are lost.

### Be Careful with Custom Setters

Property accessors on managed objects may be called during sync integration, on a background context. This means:

- Don't access `UIApplication.shared` or other main-thread-only APIs in setters.
- Don't post notifications from setters.
- Don't trigger side effects (like logging, analytics, or file writes) in setters.
- Don't assume `self.managedObjectContext` is your main context.

If you need side effects when a property changes, use an explicit method rather than a setter, and call it from your UI code — not from the model layer.

### Handle Orphaned Objects

Consider this scenario: device A deletes a `Folder` object. Meanwhile, device B adds a new `Note` to that folder. After sync, device A has the note but no folder. The note is an orphan.

Core Data's cascade delete rules don't help here, because the deletion and the insertion happened on different devices at different times.

Strategies for handling orphans:

- **Optional relationships** — Make the parent relationship optional. In your UI, treat orphaned objects as belonging to a default container (e.g., an "Unfiled" folder).
- **Reparation context** — Use the delegate's `shouldSaveMergedChangesIn:reparationContext:` to detect and fix orphans before the merge save (see Conflict Resolution).
- **Cleanup on launch** — Periodically scan for objects with nil parent relationships and handle them (delete, move to a default container, etc.).

## Excluding Entities and Properties

Sometimes you have data that shouldn't sync: local caches, UI state, device-specific preferences. You can exclude entities or individual properties from sync.

Add the key **`CDEIgnoredKey`** with a non-zero integer value (e.g., `1`) to the **User Info** dictionary of any entity or property in the Core Data model editor. Ensembles will skip it during event recording and integration.

This is also useful for properties that change very frequently but don't carry meaningful data (e.g., a `lastViewedDate` timestamp).

## External Files

For large binary data like photos or documents, you have two approaches:

### Binary Data with External Storage

Core Data's "Allows External Storage" option stores large binary data as separate files on disk. Ensembles syncs these as data files alongside events, ensuring they're available before integration.

```
// In the model editor, set the attribute:
// Type: Binary Data
// [x] Allows External Storage
```

Pros: Ensembles handles everything automatically. Cons: Most APIs expect file URLs, so you may need to write the data to a temporary file.

### Store Filenames as Strings

The alternative is to manage files yourself. Store the filename as a string attribute, and handle file transfer separately — either through the same `CloudFileSystem` or through your own mechanism.

```swift
class Photo: NSManagedObject {
    @NSManaged var imageFilename: String  // e.g., "photo-abc123.jpg"
}
```

Your app should gracefully handle the case where the file isn't available yet (e.g., display a placeholder). Use `alwaysMergeFileContent(inLocalDirectory:withCloudDirectory:)` on the ensemble to sync a local directory with a cloud directory alongside the event data.

## Migrations

Ensembles works with lightweight Core Data migrations. Each event is stamped with a model version hash, so Ensembles can tell which schema version produced each event.

### Why Model Versions Matter

When a device receives a sync event, Ensembles checks whether the event's model version matches one the device knows about. If it doesn't recognize the version, it stores the event but won't try to integrate it — it can't replay changes against a schema it doesn't understand. This means every device in a sync group needs to know about all the model versions that could appear in the cloud data.

### Providing Model Versions

How you provide model versions depends on whether you use Core Data or SwiftData, and whether your schema has evolved.

**Core Data with `.xcdatamodeld` bundles:** The URL-based initializers on `CoreDataEnsemble` automatically load all versions from the bundle:

```swift
let ensemble = CoreDataEnsemble(
    ensembleIdentifier: "MainStore",
    persistentStoreURL: storeURL,
    managedObjectModelURL: modelURL,  // Points to .momd bundle
    cloudFileSystem: cloudFS
)
```

The `.momd` bundle contains all `.mom` files — one per version — so Ensembles gets the full history automatically.

**SwiftData — single version:** When your app has only ever had one schema (or you haven't shipped an update yet), pass your `@Model` types directly:

```swift
let ensemble = SwiftDataEnsemble(
    ensembleIdentifier: "MainStore",
    persistentStoreURL: storeURL,
    modelTypes: [Note.self, Tag.self],
    cloudFileSystem: cloudFS
)
```

This is the simplest path and the one shown in the Quick Start chapter.

**SwiftData — multiple versions:** When your schema evolves, you need to tell Ensembles about all versions so it can accept events recorded against any of them. Do this by switching from `modelTypes:` to `migrationPlan:`:

```swift
enum SchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Note.self] }

    @Model final class Note {
        var title: String
        var timestamp: Date
        // ...
    }
}

enum SchemaV2: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Note.self] }

    @Model final class Note {
        var title: String
        var timestamp: Date
        var priority: Int?  // New in V2
        // ...
    }
}

enum MyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }
    static var stages: [MigrationStage] { [] }
}
```

Then pass the migration plan when creating the ensemble:

```swift
let ensemble = SwiftDataEnsemble(
    ensembleIdentifier: "MainStore",
    persistentStoreURL: storeURL,
    migrationPlan: MyMigrationPlan.self,
    cloudFileSystem: cloudFS
)
```

Ensembles uses the last schema in the plan as the current model, and builds version hashes from all schemas. A device running this code will accept events from peers still on V1, because it knows both versions. You need a `SchemaMigrationPlan` for SwiftData schema evolution anyway, so Ensembles just reuses what you already have.

The same pattern works with `SwiftDataEnsembleContainer`:

```swift
let container = SwiftDataEnsembleContainer(
    name: "MainStore",
    storeURL: storeURL,
    migrationPlan: MyMigrationPlan.self,
    cloudFileSystem: cloudFS
)
```

**In-memory models (advanced):** If you're building `NSManagedObjectModel` instances yourself, pass them directly:

```swift
let ensemble = CoreDataEnsemble(
    ensembleIdentifier: "MainStore",
    persistentStoreURL: storeURL,
    managedObjectModel: currentModel,
    managedObjectModels: [modelV1, modelV2, currentModel],
    cloudFileSystem: cloudFS
)
```

### What Happens with Unknown Versions

When Ensembles encounters an event stamped with a model version it doesn't recognize, it:

1. Reports an `unknownModelVersion` error.
2. Stores the event anyway — no data is lost.
3. Excludes the event from integration (it can't replay changes it doesn't understand).
4. Integrates the event automatically once the app is updated with the new model.

This is the correct behavior: a device on an older app version shouldn't try to apply changes it can't understand. You can use this error to prompt users to update: "A device in your sync group is using a newer version. Please update to see all changes."

### Restrictions

- **Lightweight migrations only.** Ensembles can't track the semantic meaning of heavy migrations. If you need a complex migration, create a new ensemble with a different identifier (e.g., `"MainStore.v2"`) and migrate data manually.
- **No entity/property renames.** Ensembles can't map renamed entities or properties to their old names. If you rename `Note` to `Memo`, Ensembles sees them as different entities.
- **New attributes should be optional.** If you add a non-optional attribute with a default value, the default is never saved as an event. Remote objects created before the migration won't have the attribute set. Making new attributes optional avoids validation errors during sync.

## Batched Traversals

When integrating changes, Ensembles processes entities one at a time. For large stores with thousands of objects per entity, this can use significant memory. Batched traversals let you control the processing order and insert intermediate saves to release memory.

Add these keys to an entity's User Info in the model editor:

- **`CDEMigrationPriorityKey`** — A positive integer. Higher-priority entities are processed first (default 0).
- **`CDEMigrationBatchSizeKey`** — A positive integer. After this many objects are processed, an intermediate save occurs (default 0 = no batching).

**Important restrictions for batched entities:**

- Don't add relationship validation rules to batched entities — relationships may be incomplete during intermediate saves.
- Entities processed before a batched entity shouldn't validate relationships to the batched entity.

The right batch size depends on your entity's object size and will require profiling to find the balance between memory usage and performance.

## Global Identifiers in Depth

We covered the basics in the Quick Start chapter. Here are the finer points.

### How Discovery Works

When you create a `CoreDataEnsemble` (or a container creates one for you), it calls `discoverSyncableConformances(from:)` to find all `NSManagedObject` or `@Model` subclasses that conform to `Syncable`. This happens once at initialization and the results are cached.

If a SwiftData type conforms to `Syncable` but has an empty `globalIdentifierKey`, Ensembles logs a warning — you've declared intent to provide identifiers but haven't specified which property to use.

### Priority: Delegate vs. Syncable

If both the delegate method and `Syncable` are available, the delegate takes priority. This lets you override `Syncable` for specific entities if needed.

### The `globalIdentifier(from:)` Alternative

For Core Data, `Syncable` offers a second approach: instead of naming a property with `globalIdentifierKey`, you can compute the identifier:

```swift
class Tag: NSManagedObject, Syncable {
    @NSManaged var name: String
    @NSManaged var category: String

    static func globalIdentifier(from instance: Tag) -> String {
        "\(instance.category)/\(instance.name)"
    }
}
```

This is useful when the identifier depends on multiple properties. Note that this approach isn't available for SwiftData — use `globalIdentifierKey` with a single dedicated property instead.

\newpage

# Conflict Resolution

Conflicts are inevitable in a distributed system. When two devices change the same data without seeing each other's changes, Ensembles must decide which version to keep. This chapter explains how automatic resolution works and how to customize it.

## How Automatic Resolution Works

### Causal Ordering

Every event carries a *revision set* — a compact record of which events from other peers this device had seen at the time of the save. This creates a partial ordering of events across all devices.

When integrating an attribute change, Ensembles checks the revision sets:

- If change A's revision set includes change B's revision, then A happened after B. A wins.
- If change B's revision set includes change A's revision, then B happened after A. B wins.
- If neither includes the other, they're truly concurrent. The event with the highest `globalCount` (a monotonically increasing counter) wins as a deterministic tiebreaker.

This is more sophisticated than a simple timestamp comparison. Timestamps can be wrong (clock skew, timezone changes). Revision sets capture the actual causal relationship between changes, regardless of wall clock time.

### Attribute-Level Resolution

Conflicts are resolved per-attribute, not per-object. If device A changes a note's `title` and device B changes the same note's `body`, both changes are preserved — there's no conflict at all. A conflict only occurs when two devices change the *same attribute* of the *same object*.

Compare this with object-level merge policies (like Core Data's built-in `NSMergeByPropertyStoreTrumpMergePolicy`), which would discard one device's changes entirely.

### To-Many Relationships: Add-Wins Sets

To-many relationships use an *add-wins set* strategy:

- **Additions** from both sides are preserved.
- **Removals** are only applied if they were explicit.

Example: Device A adds note X to a tag's notes. Device B adds note Y to the same tag's notes. After sync, the tag contains both X and Y.

Example: Device A removes note X from the tag. Device B (which hasn't seen A's removal) adds note Z. After sync, note X is removed and note Z is added.

This strategy biases toward preserving data, which tends to be a good default for user-facing apps.

### To-One Relationships

To-one relationships are resolved the same way as attributes — last writer wins based on causal ordering.

## The Reparation Context

For cases where automatic resolution isn't sufficient, the delegate provides a two-context pattern. I call this the "reparation context" because it lets you *repair* the merged data before it's committed.

### Inspecting the Merge

Before saving merged changes, the ensemble calls:

```swift
func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    shouldSaveMergedChangesIn savingContext: NSManagedObjectContext,
    reparationContext: NSManagedObjectContext
) -> Bool
```

The `savingContext` contains all the merged changes about to be committed. You can walk through its inserted, updated, and deleted objects to see exactly what will happen:

```swift
func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    shouldSaveMergedChangesIn savingContext: NSManagedObjectContext,
    reparationContext: NSManagedObjectContext
) -> Bool {
    // Check for orphaned items
    savingContext.performAndWait {
        for object in savingContext.insertedObjects {
            if let item = object as? Item, item.folder == nil {
                // Fix in reparation context
                reparationContext.performAndWait {
                    let rItem = reparationContext.object(with: item.objectID) as! Item
                    rItem.folder = getDefaultFolder(in: reparationContext)
                }
            }
        }
    }
    return true
}
```

Return `false` to abort the merge entirely. The remote events stay in the event store and will be re-integrated on the next sync.

### Making Repairs

This is the critical part: **do not modify the `savingContext` directly.** The saving context contains Ensembles' carefully merged result. If you modify it, you'll interfere with the merge tracking.

Instead, make all corrections in the `reparationContext`. Changes you make there are captured as new events and propagated to all peers on the next sync. This ensures your repairs are distributed consistently across all devices.

```swift
reparationContext.performAndWait {
    let item = reparationContext.object(with: objectID) as! Item
    item.total = item.quantity * item.price  // Recompute invariant
}
return true
```

### Deadlock Warning

The saving context and reparation context have a parent-child relationship. **Never nest `perform` or `performAndWait` calls between them.** This pattern deadlocks:

```swift
// WARNING: DEADLOCK -- don't do this
savingContext.performAndWait {
    reparationContext.performAndWait {
        // ...
    }
}
```

Instead, access each context separately:

```swift
savingContext.performAndWait {
    // Read from saving context
}
reparationContext.performAndWait {
    // Write to reparation context
}
```

## Handling Save Failures

If the merge save fails (e.g., a validation error that wasn't caught by the inspection), the ensemble calls:

```swift
func coreDataEnsemble(
    _ ensemble: CoreDataEnsemble,
    didFailToSaveMergedChangesIn savingContext: NSManagedObjectContext,
    error: Error,
    reparationContext: NSManagedObjectContext
) -> Bool
```

Inspect the error, make corrections in the reparation context, and return `true` to retry the save. Return `false` to abort.

Common causes of save failures:

- **Validation errors** — An attribute or relationship doesn't meet the model's validation rules after merge.
- **Non-optional nil** — A required relationship is nil because the related object was deleted on another device.
- **Unique constraint violations** — Two objects with the same unique constraint were merged.

## Conflict Resolution with SwiftData

The reparation context operates on `NSManagedObjectContext` and `NSManagedObject`, which means it isn't directly usable from SwiftData `@Model` types. You have two options:

**Design away the problem.** Structure your SwiftData model so that attribute-level merging always produces valid results. Follow the guidelines in the Models chapter (avoid cross-attribute invariants, avoid accumulating attributes) and you may never need custom conflict resolution.

**Use the Core Data escape hatch.** Access the underlying `CoreDataEnsemble` and set its delegate:

```swift
let swiftDataEnsemble = SwiftDataEnsemble(...)
swiftDataEnsemble?.coreDataEnsemble.delegate = myDelegate
```

Your delegate will work with `NSManagedObject` instances, but you can use the same entity names and attribute names as your `@Model` types.

\newpage

# Cloud Backends

Ensembles exchanges sync data through a `CloudFileSystem` protocol — an abstraction for file storage with a path-based API. The framework ships with 14 built-in backends, covering a wide range of cloud services and use cases.

## CloudKit

The recommended backend for most apps. Uses iCloud, which is available on all Apple devices with no setup from the user. No authentication UI required — it uses the device's iCloud account.

```swift
import EnsemblesCloudKit

let cloudFS = CloudKitFileSystem(
    privateDatabaseForUbiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp",
    schemaVersion: .v2
)
```

**Setup:**

1. Enable the "iCloud" capability in your Xcode project.
2. Check "CloudKit" under iCloud services.
3. Create a CloudKit container with the identifier matching your `ubiquityContainerIdentifier`.

CloudKit is free for most apps (Apple provides generous storage quotas per user). It doesn't require a license key.

## iCloud Drive

> **Deprecated.** This backend exists for backward compatibility with Ensembles 2 apps that used `CDEICloudFileSystem`. For new projects, use CloudKit instead — it's faster and more reliable.

Syncs via Apple's iCloud Drive service using the Ubiquity Container document storage. Not available on watchOS.

```swift
import EnsemblesiCloudDrive

let cloudFS = ICloudDriveFileSystem(
    ubiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp"
)
```

**Setup:**

1. Enable the "iCloud" capability.
2. Check "iCloud Documents" under iCloud services.

This stores files in the user's iCloud Drive ubiquity container. It doesn't require a license key.

## Google Drive

Syncs via the Google Drive REST API v3. Ensembles calls the API directly using `URLSession` — no Google SDK dependency.

```swift
import EnsemblesGoogleDrive

let authenticator = GoogleDriveAuthenticator(configuration: .init(
    clientID: "your-client-id.apps.googleusercontent.com",
    redirectURI: "com.yourapp:/google/callback"
))
try await authenticator.authorize(presenting: window)

let cloudFS = GoogleDriveCloudFileSystem(authenticator: authenticator)
```

**Setup:**

1. Create a project in the Google Cloud Console.
2. Enable the Google Drive API.
3. Create OAuth 2.0 credentials (iOS application type).
4. Add the redirect URI scheme to your app's Info.plist under `CFBundleURLSchemes`.

The authenticator handles token storage (Keychain) and refresh automatically.

## OneDrive

Syncs via the Microsoft Graph API v1.0.

```swift
import EnsemblesOneDrive

let authenticator = OneDriveAuthenticator(configuration: .init(
    clientID: "your-client-id",
    redirectURI: "msauth.com.yourapp://auth"
))
try await authenticator.authorize(presenting: window)

let cloudFS = OneDriveCloudFileSystem(authenticator: authenticator)
```

**Setup:**

1. Register an app in the Microsoft Azure portal.
2. Add the "Files.ReadWrite" permission.
3. Configure the redirect URI (iOS/macOS platform).

## pCloud

Syncs via the pCloud REST API. pCloud is a Swiss cloud provider with strong privacy guarantees.

```swift
import EnsemblesPCloud

let authenticator = PCloudAuthenticator(configuration: .init(
    clientID: "your-app-key",
    redirectURI: "com.yourapp://pcloud/callback"
))
try await authenticator.authorize(presenting: window)

let cloudFS = PCloudCloudFileSystem(authenticator: authenticator)
```

pCloud tokens don't expire, so users only need to authorize once. The authenticator automatically detects the correct API endpoint (US or EU) based on the user's account region.

## WebDAV

Syncs via any WebDAV-compatible server — Nextcloud, ownCloud, Synology NAS, or your own.

```swift
import EnsemblesWebDAV

let cloudFS = WebDAVCloudFileSystem(
    baseURL: URL(string: "https://cloud.example.com/remote.php/dav/files/user/")!,
    username: "user",
    password: "pass"
)
```

This is the go-to backend for self-hosted sync. No third-party dependencies, no OAuth dance — just a URL and credentials. Users who care deeply about data sovereignty love this option.

## Dropbox

Syncs via the Dropbox API. Requires the SwiftyDropbox SDK (trait-gated).

```swift
// Package.swift
.package(url: "...", from: "3.0.0", traits: ["Dropbox"])
```

```swift
import EnsemblesDropbox

let cloudFS = DropboxCloudFileSystem(...)
```

## Amazon S3

Syncs via the Amazon S3 API. Requires the aws-sdk-swift package (trait-gated).

```swift
// Package.swift
.package(url: "...", from: "3.0.0", traits: ["S3"])
```

## Box

Syncs via the Box API. Requires the BoxSDK package (trait-gated).

```swift
// Package.swift
.package(url: "...", from: "3.0.0", traits: ["Box"])
```

## Local File System

Uses a local directory. Ideal for testing, for syncing between apps on the same device via a shared App Group container, or for syncing between a macOS app and its iOS companion via a shared folder.

```swift
import EnsemblesLocalFile

let cloudFS = LocalCloudFileSystem(rootDirectory: sharedDirectoryURL)
```

No authentication, no network, no cloud account. This backend is free.

## Memory

An actor-based, in-memory backend with no disk I/O. Designed for unit testing.

```swift
import EnsemblesMemory

let cloudFS = MemoryCloudFileSystem()
```

Create one instance and share it between multiple ensembles to simulate multi-device sync in tests. See the Testing chapter for details. This backend is free.

## Encrypted

A wrapper that encrypts all data before passing it to another backend. See the Encryption chapter.

## Zip

A wrapper that compresses cloud files using ZIP compression. Useful for backends with limited storage or slow upload speeds.

```swift
// Package.swift — requires trait
.package(url: "...", from: "3.0.0", traits: ["Zip"])
```

```swift
import EnsemblesZip

let innerFS = CloudKitFileSystem(
    privateDatabaseForUbiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp",
    schemaVersion: .v2
)
let cloudFS = ZipCloudFileSystem(cloudFileSystem: innerFS)
```

## Multipeer

Syncs over local network using Multipeer Connectivity. Useful for device-to-device transfer without any cloud service. Uses Zip compression for transfer efficiency.

```swift
// Package.swift — requires trait
.package(url: "...", from: "3.0.0", traits: ["Multipeer"])
```

## Choosing a Backend

| If you want... | Use... |
|----------------|--------|
| Simplest setup, Apple only | CloudKit |
| User's own storage | Google Drive, OneDrive, pCloud, Dropbox |
| Self-hosted | WebDAV |
| Enterprise | S3, Box |
| No cloud at all (local) | LocalFile |
| Unit tests | Memory |
| Maximum privacy | Any backend + Encrypted |
| Device-to-device | Multipeer |

You can also let users choose. Since all backends implement the same protocol, switching is just a matter of creating a different `CloudFileSystem` instance.

\newpage

# Building a Custom Backend

If none of the built-in backends fit your needs, you can implement your own. Any storage system that can hold files at paths can serve as an Ensembles backend.

## The CloudFileSystem Protocol

The core protocol has just 8 required methods:

```swift
public protocol CloudFileSystem: AnyObject, Sendable {
    var isConnected: Bool { get }
    func connect() async throws
    func fetchUserIdentity() async throws
        -> sending (any NSObjectProtocol & NSCoding & NSCopying)?
    func fileExists(atPath path: String) async throws -> FileExistence
    func createDirectory(atPath path: String) async throws
    func contentsOfDirectory(atPath path: String) async throws
        -> [any CloudItem]
    func removeItem(atPath path: String) async throws
    func uploadLocalFile(atPath localPath: String,
                         toPath remotePath: String) async throws
    func downloadFile(atPath remotePath: String,
                      toLocalFile localPath: String) async throws
}
```

Let me walk through each:

**`isConnected`** — Returns whether the backend is ready to handle file operations. Ensembles checks this before starting operations.

**`connect()`** — Establishes a connection to the backend. Called at the start of attach and sync operations. This is where you'd authenticate, verify credentials, or open a connection.

**`fetchUserIdentity()`** — Returns an opaque identity object that Ensembles uses to detect account changes. If the identity changes between syncs (e.g., the user signed into a different account), Ensembles triggers a forced detach. Return `nil` if your backend doesn't have user accounts.

**`fileExists(atPath:)`** — Returns a `FileExistence` value indicating whether a file or directory exists at the given path. Paths are relative to the ensemble's root directory.

**`createDirectory(atPath:)`** — Creates a directory at the given path. Should be idempotent — creating an existing directory is not an error.

**`contentsOfDirectory(atPath:)`** — Returns the immediate children of a directory as `CloudItem` instances (`CloudFile` or `CloudDirectory`).

**`removeItem(atPath:)`** — Deletes a file or directory. Should be idempotent.

**`uploadLocalFile(atPath:toPath:)`** — Copies a local file to the cloud. The local path is an absolute filesystem path. The remote path is relative to the ensemble root.

**`downloadFile(atPath:toLocalFile:)`** — Copies a cloud file to the local filesystem.

## Batch Operations

For backends that can handle multiple files per request, adopt `CloudFileSystemBatchOperations`:

```swift
public protocol CloudFileSystemBatchOperations: CloudFileSystem {
    var fileUploadMaximumBatchSize: Int { get }
    var fileDownloadMaximumBatchSize: Int { get }
    func uploadLocalFiles(atPaths localPaths: [String],
                          toPaths remotePaths: [String]) async throws
    func downloadFiles(atPaths remotePaths: [String],
                       toLocalFiles localPaths: [String]) async throws
    func removeItems(atPaths paths: [String]) async throws
}
```

Default batch sizes are 10. Ensembles automatically batches operations when your backend conforms to this protocol.

## Setup Protocol

For backends that need one-time initialization or special preparation, adopt `CloudFileSystemSetup`:

```swift
public protocol CloudFileSystemSetup: CloudFileSystem {
    func performInitialPreparation() async throws
    func primeForActivity() async throws
    func directoryExists(atPath path: String) async throws -> Bool
    func repairEnsembleDirectory(atPath path: String) async throws
}
```

## Starting Points

I recommend studying these implementations as templates:

- **`MemoryCloudFileSystem`** — The simplest implementation. An actor with in-memory dictionaries. Great for understanding the protocol contract.
- **`LocalCloudFileSystem`** — A real file-based implementation using `FileManager`. Shows the basic pattern for disk-backed storage.
- **`PCloudCloudFileSystem`** — A REST API implementation. Shows how to map HTTP calls to the protocol, handle authentication, and manage OAuth tokens.

The source code for all backends is in `Sources/Ensembles*/` directories.

\newpage

# Encryption

Privacy matters. Local-first means your data belongs to the user, but if you're syncing through a third-party cloud service, privacy is only as strong as that service's policies. Ensembles includes built-in encryption so you can offer true end-to-end encryption without trusting the cloud provider.

## How It Works

`EncryptedCloudFileSystem` is a wrapper: it sits between the ensemble and any other backend, encrypting files before upload and decrypting after download. The cloud provider sees only opaque, encrypted blobs.

```swift
import EnsemblesEncrypted
import EnsemblesCloudKit

let innerFS = CloudKitFileSystem(
    privateDatabaseForUbiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp",
    schemaVersion: .v2
)

let cloudFS = EncryptedCloudFileSystem(
    cloudFileSystem: innerFS,
    password: userPassword
)!
```

All sync data — events, baselines, and data files — is encrypted before it leaves the device.

## Encryption Formats

Ensembles supports two encryption formats:

**Modern (default)** — AES-256-GCM with PBKDF2 key derivation. This is the recommended format for new apps.

**Legacy** — Compatible with Ensembles 2's `CDEEncryptedCloudFileSystem`, which used RNCryptor v3. Use this only for backward compatibility with E2 peers:

```swift
let cloudFS = EncryptedCloudFileSystem(
    cloudFileSystem: innerFS,
    vaultInfo: vaultInfo,
    encryptionFormat: .legacy
)
```

## Vault Info

For more control over encryption, use `VaultInfo` directly:

```swift
let vaultInfo = VaultInfo(password: userPassword)!
let cloudFS = EncryptedCloudFileSystem(
    cloudFileSystem: innerFS,
    vaultInfo: vaultInfo
)
```

`VaultInfo` derives a password-dependent path component so that data encrypted with different passwords is stored in different "vaults" in the cloud. This allows password changes without re-encrypting everything — old vaults remain readable with the old password.

You can manage vaults with:

```swift
// Find vaults this password can't read
let unreadable = try await cloudFS.unreadableVaults(for: [currentVault])

// Delete an old vault
try await cloudFS.deleteVault(oldVault)
```

## Password Management

> **Warning:** If the user loses their password, their sync data is **unrecoverable**. There is no backdoor, no recovery key, no way for you or the cloud provider to decrypt the data.

Practical advice:

- **Store the password in the Keychain** so the user doesn't need to enter it on every launch.
- **Provide a way to export/backup the password** (e.g., a "Show Recovery Key" screen).
- **Consider a key derivation approach** where the password is derived from the user's account credentials, so they can't lose it independently.
- **If the password changes**, create a new vault with the new password. Old vaults remain readable with the old password until you delete them.

\newpage

# Testing and Debugging

Sync is inherently complex — multiple devices, asynchronous operations, conflict resolution. Good testing practices are essential. This chapter covers strategies for testing sync in your app and debugging common issues.

## Testing with MemoryCloudFileSystem

The `MemoryCloudFileSystem` is ideal for testing. It's an actor-based, in-memory backend with no disk I/O and no network calls. Tests run in milliseconds, are fully deterministic, and can simulate multi-device scenarios.

### Basic Two-Device Test

```swift
import Testing
import Ensembles
import EnsemblesMemory

@Suite(.serialized)
@MainActor
struct SyncTests {
    let sharedCloud = MemoryCloudFileSystem()

    @Test func twoDeviceSync() async throws {
        // Set up two ensembles sharing the same cloud
        let ensemble1 = CoreDataEnsemble(
            ensembleIdentifier: "Test",
            persistentStoreURL: store1URL,
            managedObjectModel: model,
            cloudFileSystem: sharedCloud
        )!

        let ensemble2 = CoreDataEnsemble(
            ensembleIdentifier: "Test",
            persistentStoreURL: store2URL,
            managedObjectModel: model,
            cloudFileSystem: sharedCloud
        )!

        // Attach both
        try await ensemble1.attachPersistentStore()
        try await ensemble2.attachPersistentStore()

        // Make a change on device 1
        let context1 = NSManagedObjectContext(.mainQueue)
        context1.persistentStoreCoordinator = coordinator1
        let note = Note(context: context1)
        note.title = "Hello"
        try context1.save()

        // Sync: device 1 exports, device 2 imports
        try await ensemble1.sync()
        try await ensemble2.sync()

        // Verify device 2 has the note
        let context2 = NSManagedObjectContext(.mainQueue)
        context2.persistentStoreCoordinator = coordinator2
        let request = NSFetchRequest<Note>(entityName: "Note")
        let notes = try context2.fetch(request)
        #expect(notes.count == 1)
        #expect(notes.first?.title == "Hello")
    }
}
```

### Important Testing Patterns

**Serialization:** Mark sync test suites with `.serialized`. This prevents `NotificationCenter` cross-talk between `SaveMonitor` instances, which observe `NSManagedObjectContextDidSave` with `object: nil`.

**Main actor:** If your test creates `.mainQueueConcurrencyType` contexts, mark the suite with `@MainActor`. Swift Testing runs tests on arbitrary threads, and Core Data contexts are picky about which thread they're used on.

**Two-round sync:** To reliably transfer data between two ensembles, you often need: sync device 1 (exports), then sync device 2 (imports device 1's data). If device 2 also has changes, sync device 1 again to pick those up.

## Testing with LocalCloudFileSystem

For integration tests that need real file I/O (e.g., testing with your actual persistent store setup), use `LocalCloudFileSystem`:

```swift
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
let cloudFS = LocalCloudFileSystem(rootDirectory: tempDir)
```

Clean up the directory in your test's teardown.

## Testing with Containers

If your app uses containers, you can test with them too:

```swift
let sharedCloud = MemoryCloudFileSystem()

let container1 = CoreDataEnsembleContainer(
    name: "Test",
    storeURL: store1URL,
    modelURL: modelURL,
    cloudFileSystem: sharedCloud,
    configuration: .init(autoSyncPolicy: .manual)
)!

let container2 = CoreDataEnsembleContainer(
    name: "Test",
    storeURL: store2URL,
    modelURL: modelURL,
    cloudFileSystem: sharedCloud,
    configuration: .init(autoSyncPolicy: .manual)
)!

// Wait for attachment, then manually trigger syncs
try await container1.sync(options: .none)
try await container2.sync(options: .none)
```

Set `autoSyncPolicy: .manual` in tests to control sync timing precisely.

## Enabling Logging

Ensembles has an internal logging system. Enable it to see what's happening during sync:

```swift
setLoggingLevel(.verbose)
```

Log levels:

- **`.none`** — No output.
- **`.error`** — Only errors (default).
- **`.warning`** — Errors and warnings.
- **`.trace`** — Errors, warnings, and major operations.
- **`.verbose`** — Everything, including detailed internal state.

In debug builds, `.trace` is a good choice. In production, the default `.error` is usually fine.

## Common Issues and Solutions

### Sync Completes but Changes Don't Appear in UI

**Cause:** You're not merging the save notification into your main context.

**Fix:** Implement `didSaveMergeChangesWith` in your delegate and call `mergeChanges(fromContextDidSave:)` on your view context. If using SwiftData with a container, ensure persistent history tracking is enabled (it is by default with `SwiftDataEnsembleContainer`).

### Duplicate Objects After Sync

**Cause:** Objects created on multiple devices don't have matching global identifiers.

**Fix:** Conform your model types to `Syncable` and provide meaningful identifiers for entities that can be logically identical (tags, categories, singletons). For entities where every instance is unique (notes, tasks), use UUIDs.

### Unknown Model Version Errors

**Cause:** A peer is running a newer model version that this device doesn't know about.

**Fix:** Ensure all model versions are included in the `managedObjectModels` array (or use URL-based initializers that load all versions automatically). Use the error to prompt users to update.

### Forced Detach on Launch

**Cause:** Usually an iCloud account change, or the device's registration was cleaned up by another peer.

**Fix:** Handle the `didDetachWithError` delegate callback (or `didForceDetach` on containers). Offer to re-attach. This is a normal part of the lifecycle — don't treat it as a fatal error.

### Slow Sync with Large Stores

**Cause:** Too many events accumulated, or large binary data.

**Fix:**
- Trigger a rebase with `sync(options: .forceRebase)` to compact event history.
- Use batched traversals for entities with many objects.
- Consider whether all entities need to sync — use `CDEIgnoredKey` for local-only data.
- Move large binary data to external files managed separately.

### Core Data Threading Crashes in Tests

**Cause:** Accessing Core Data contexts from the wrong thread.

**Fix:** Use `@MainActor` on test suites that create `.mainQueueConcurrencyType` contexts. Wrap all context access in `performAndWait` blocks.

\newpage

# Migrating from Ensembles 2

Ensembles 3 is fully backward compatible with Ensembles 2 cloud data. You can migrate without a data reset — existing peers continue syncing seamlessly.

## What's Backward Compatible

- **Cloud files** — The directory structure and file formats are identical. An E3 device can read files written by E2, and vice versa (in compatibility mode).
- **Event store** — E3 automatically migrates from E2's Core Data event store to E3's SQLite format on first launch. This migration is transparent and non-destructive.
- **JSON format** — Property change values use the same serialization format.
- **CloudKit records** — Record types and field names are preserved.
- **Encryption** — E3's `.legacy` encryption format matches E2's `CDEEncryptedCloudFileSystem`.

## Step-by-Step Migration

### 1. Swap the Dependency

Replace the Ensembles 2 CocoaPod or framework with the Ensembles 3 Swift package.

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/mentalfaculty/Ensembles3", from: "3.0.0")
]
```

### 2. Enable Compatibility Mode

If some users may still be running Ensembles 2:

```swift
let config = EnsembleContainerConfiguration(
    compatibilityMode: .ensembles2Compatible
)
```

Or on a bare ensemble:

```swift
ensemble?.compatibilityMode = .ensembles2Compatible
```

Compatibility mode restricts E3 to features and formats that E2 can understand. Most notably, it disables compressed model hashes (which E2 can't decode).

### 3. Update API Names

| Ensembles 2 (Objective-C) | Ensembles 3 (Swift) |
|---|---|
| `CDEPersistentStoreEnsemble` | `CoreDataEnsemble` |
| `CDEPersistentStoreEnsembleDelegate` | `CoreDataEnsembleDelegate` |
| `leechPersistentStore(...)` | `attachPersistentStore()` |
| `deleechPersistentStore(...)` | `detachPersistentStore()` |
| `mergeWithCompletion:` | `sync()` / `sync(options:)` |
| `CDECloudFileSystem` | `CloudFileSystem` |
| `CDEICloudFileSystem` | `ICloudDriveFileSystem` |
| `CDECloudKitFileSystem` | `CloudKitFileSystem` |
| `CDEDropboxCloudFileSystem` | `DropboxCloudFileSystem` |
| `CDEEncryptedCloudFileSystem` | `EncryptedCloudFileSystem` |
| `CDENodeCloudFileSystem` | (WebDAV) `WebDAVCloudFileSystem` |
| Completion handler callbacks | `async throws` |
| `NSMergePolicy` on delegate | `shouldSaveMergedChangesIn` delegate |
| `CDEPersistentStoreEnsembleDelegate` globalIDs: `[NSObject]` | `[String?]` |

### 4. Update Concurrency Patterns

E2 used completion handlers everywhere:

```objc
// E2 (Objective-C)
[ensemble mergeWithCompletion:^(NSError *error) {
    if (error) NSLog(@"Merge failed: %@", error);
}];
```

E3 uses async/await:

```swift
// E3 (Swift)
do {
    try await ensemble?.sync()
} catch {
    print("Sync failed: \(error)")
}
```

### 5. Test Thoroughly

Before releasing to users:

- Verify your app can read existing E2 cloud data.
- Verify that E2 peers can read data exported by E3 (in `.ensembles2Compatible` mode).
- Test the event store migration (launch on a device that had E2 data).
- Test with encrypted data if you used `CDEEncryptedCloudFileSystem` (use `.legacy` format).

### 6. Switch to Full E3 Mode

Once all users have upgraded (or when you drop E2 support):

```swift
ensemble?.compatibilityMode = .ensembles3  // The default
```

Or simply remove the `compatibilityMode` parameter from your configuration — `.ensembles3` is the default.

Full E3 mode enables compressed model hashes and any future optimizations that aren't backward compatible with E2.

\newpage

# Licensing

## Free and Licensed Backends

Ensembles uses a simple licensing model. Some backends are free; others require a license key.

**Free backends (no license required):**

- CloudKit (`CloudKitFileSystem`)
- iCloud Drive (`ICloudDriveFileSystem`)
- Local File System (`LocalCloudFileSystem`)
- Memory (`MemoryCloudFileSystem`)
- Zip (`ZipCloudFileSystem`)

**Licensed backends (require activation):**

- Google Drive, OneDrive, pCloud, Dropbox, S3, Box, WebDAV
- Encrypted, Multipeer
- Any custom `CloudFileSystem` implementation

## Activation

Activate your license at app launch, before creating any ensembles:

```swift
import Ensembles

EnsemblesLicense.activate("your-license-key")
```

You can check the license status at any time:

```swift
if EnsemblesLicense.isActive {
    // Licensed backends are available
}
```

If you attempt to attach an ensemble with a licensed backend without activating a license, the attach will fail with an `EnsembleError.unlicensed` error.

## Subscription Model

A license subscription covers all SDK versions released during the subscription period. Your deployed apps continue working forever — there is no runtime expiry. The license key is checked against the SDK's build date, not the current date. This means:

- If your subscription covers the SDK version you're shipping, it works.
- If you update to a newer SDK released after your subscription expired, you'll need to renew.
- Users of your app are never affected by license expiry.

## Getting a License

Visit [ensembles.io](https://ensembles.io) for pricing and to purchase a license. Free trials are available.
