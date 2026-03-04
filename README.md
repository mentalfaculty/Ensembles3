# Ensembles 3

**Core Data and SwiftData sync framework for Apple platforms.**

Ensembles 3 synchronizes Core Data and SwiftData persistent stores across devices using an event-sourcing architecture. It supports multiple cloud backends and is backwards compatible with Ensembles 2 cloud data.

## Requirements

- iOS 16+, macOS 13+, tvOS 16+, watchOS 9+
- Swift 5.9+
- Xcode 15+

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

```swift
import Ensembles
import EnsemblesCloudKit

let ensemble = CoreDataEnsemble(
    ensembleIdentifier: "MyStore",
    persistentStoreURL: storeURL,
    managedObjectModel: model,
    cloudFileSystem: CloudKitFileSystem()
)

// Attach to start syncing
try await ensemble?.attachPersistentStore()

// Merge remote changes
try await ensemble?.merge()

// Detach when done
try await ensemble?.detachPersistentStore()
```

## Quick Start — SwiftData

```swift
import EnsemblesSwiftData
import EnsemblesCloudKit

let ensemble = SwiftDataEnsemble(
    ensembleIdentifier: "MyStore",
    persistentStoreURL: storeURL,
    modelTypes: [Item.self],
    cloudFileSystem: CloudKitFileSystem()
)

try await ensemble?.attachPersistentStore()
try await ensemble?.merge()
```

## Licensing

Free backends work without any license activation. Paid backends require a valid
subscription license from [Mental Faculty](https://mentalfaculty.com).

Activate your license once at app launch:

```swift
import Ensembles

EnsemblesLicense.activate("your-license-key")
```

Without a valid license, paid backends will log a warning and refuse to connect.
Free backends are unaffected.

## Documentation

Full API documentation, architecture guides, and conflict resolution strategies
are available in the [Documentation](https://mentalfaculty.com/ensembles/docs).

## Support

- Email: support@mentalfaculty.com
- Issues: https://github.com/mentalfaculty/Ensembles3/issues
