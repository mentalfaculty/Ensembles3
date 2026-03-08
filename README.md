# Ensembles 3

**Core Data and SwiftData sync framework for Apple platforms.**

Ensembles synchronizes Core Data and SwiftData persistent stores across devices using an event-sourcing architecture. Your data is stored as opaque files in any cloud service — CloudKit, Google Drive, OneDrive, WebDAV, and more — with optional end-to-end encryption. No custom server required.

## Requirements

- iOS 16+, macOS 13+, tvOS 16+, watchOS 9+
- Swift 5.9+
- Xcode 15+
- SwiftData features require iOS 17+ / macOS 14+

## Installation

Add Ensembles 3 to your project using Swift Package Manager:

```
https://github.com/mentalfaculty/Ensembles3
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

The easiest way to add sync is with `CoreDataEnsembleContainer`. It creates the Core Data stack, sets up a delegate, and auto-syncs on save:

```swift
import Ensembles
import EnsemblesCloudKit

let container = CoreDataEnsembleContainer(
    name: "MainStore",
    storeURL: storeURL,
    modelURL: modelURL,
    cloudFileSystem: CloudKitFileSystem(
        ubiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp"
    )
)

// Supply global identifiers for deduplication
container?.globalIdentifiers = { objects in
    objects.map { $0.value(forKey: "uniqueID") as? String }
}
```

That's it. The container automatically attaches to the cloud, syncs on save, on app activation, and on a timer. Remote changes are merged into the container's `viewContext` automatically.

For more control, use `CoreDataEnsemble` directly:

```swift
let ensemble = CoreDataEnsemble(
    ensembleIdentifier: "MainStore",
    persistentStoreURL: storeURL,
    managedObjectModelURL: modelURL,
    cloudFileSystem: CloudKitFileSystem(
        ubiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp"
    )
)
ensemble?.delegate = self

try await ensemble?.attachPersistentStore()
try await ensemble?.sync()
```

## Quick Start — SwiftData

```swift
import EnsemblesSwiftData
import EnsemblesCloudKit

let container = SwiftDataEnsembleContainer(
    name: "MainStore",
    storeURL: storeURL,
    modelTypes: [Item.self, Tag.self],
    cloudFileSystem: CloudKitFileSystem(
        ubiquityContainerIdentifier: "iCloud.com.yourcompany.yourapp"
    )
)
```

SwiftData models can declare a global identifier for automatic deduplication by conforming to the `Syncable` protocol:

```swift
@Model
class Tag: Syncable {
    static let globalIdentifierKey = "name"
    var name: String
}
```

SwiftData support requires iOS 17+ / macOS 14+.

## Global Identifiers

When two devices independently create the "same" object (e.g., a tag with the same name), Ensembles needs a **global identifier** to recognize they represent the same entity and merge them instead of duplicating. Without global identifiers, each device's copy is treated as a separate object.

Global identifiers are essential for reference data, categories, and any entity where independent creation of "the same" object is likely. Entities that are always created explicitly by the user (notes, photos) typically don't need them.

## Licensing

Free backends (CloudKit, LocalFile, Memory) work without any license activation.

Paid backends require a valid subscription license from [Mental Faculty](https://mentalfaculty.com). Activate once at app launch:

```swift
import Ensembles

EnsemblesLicense.activate("your-license-key")
```

Without a valid license, paid backends will refuse to attach.

## Backward Compatibility

Ensembles 3 is fully backward compatible with Ensembles 2 sync data. Existing apps can migrate without a data reset.

If some users may still be running the Ensembles 2 version of your app, set compatibility mode to restrict exports to E2-parseable formats:

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

## Documentation

Full API documentation, architecture guides, backend setup, and migration guides are available in the [documentation](https://ensembles.io/docs).

## Support

- Email: support@mentalfaculty.com
- Issues: https://github.com/mentalfaculty/Ensembles3/issues
