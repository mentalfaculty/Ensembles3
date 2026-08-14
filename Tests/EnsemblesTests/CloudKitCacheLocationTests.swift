import Testing
import Foundation
@_spi(Testing) import EnsemblesCloudKit

/// The listing cache must live inside the event store directory so that removing the
/// store removes the cache.
///
/// Before 3.0.8 it lived in the system caches directory, keyed only by the CloudKit
/// zone. That location outlives the event store: it survives app deletion, and it
/// survives removing and recreating the zone. Priming would then resume an incremental
/// fetch using a change token minted against the old zone, and CloudKit would report
/// only what had changed since that cursor. Anything predating it was never mentioned
/// again, so a device could download data files while never learning about the baseline
/// that referenced them — and report success over an empty store.
///
/// Reported by Keith (Writing Shed Pro), 2026-08-14. His phone's cache still listed a
/// store registration from its own pre-deletion incarnation, which is what proved the
/// cache had outlived the store.
@Suite("CloudKitCacheLocation")
struct CloudKitCacheLocationTests {

    private let zoneChecksum = "testzonechecksum"

    private func makeStoreDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-location-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sampleSnapshot(_ marker: String) -> CloudKitListingCache.Snapshot {
        .init(tokenData: Data([1, 2, 3]), files: ["/\(marker)": .init(isDirectory: false, fileSize: 1)])
    }

    @Test("Cache is located inside the event store directory")
    func cacheLivesInStoreDirectory() throws {
        let storeDir = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let url = CloudKitListingCache.url(inStoreDirectory: storeDir.path, zoneChecksum: zoneChecksum)

        #expect(url.deletingLastPathComponent().standardizedFileURL == storeDir.standardizedFileURL)
        #expect(url.lastPathComponent == "\(zoneChecksum).cdecloudkitcache.v3")
    }

    @Test("Cache is never placed in a directory with a lifetime of its own")
    func cacheIsNotInSystemCaches() throws {
        let storeDir = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let url = CloudKitListingCache.url(inStoreDirectory: storeDir.path, zoneChecksum: zoneChecksum)
        let systemCaches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first

        #expect(url.deletingLastPathComponent().standardizedFileURL != systemCaches?.standardizedFileURL)
    }

    @Test("Removing the event store removes the cache with it")
    func removingStoreRemovesCache() throws {
        let storeDir = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let cacheURL = CloudKitListingCache.url(inStoreDirectory: storeDir.path, zoneChecksum: zoneChecksum)
        CloudKitListingCache.save(sampleSnapshot("a"), to: cacheURL)
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))

        // Exactly what EventStore.removeEventStore() does.
        try FileManager.default.removeItem(at: storeDir)

        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
        #expect(CloudKitListingCache.load(from: cacheURL) == nil)
    }

    @Test("Two stores on one device get separate caches")
    func distinctStoresDoNotShareACache() throws {
        let firstDir = try makeStoreDirectory()
        let secondDir = try makeStoreDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
        }

        // Same zone: under the old scheme both stores resolved to one shared file.
        let first = CloudKitListingCache.url(inStoreDirectory: firstDir.path, zoneChecksum: zoneChecksum)
        let second = CloudKitListingCache.url(inStoreDirectory: secondDir.path, zoneChecksum: zoneChecksum)
        #expect(first != second)

        CloudKitListingCache.save(sampleSnapshot("first"), to: first)
        #expect(CloudKitListingCache.load(from: second) == nil)
    }

    /// The recovery path for devices upgrading from 3.0.7 and earlier, and the reason
    /// Keith's phone saw a partial cloud: a cache from a previous incarnation.
    @Test("A cache left in the pre-3.0.8 location is discarded, not adopted")
    func strayCacheIsDiscarded() throws {
        let strayURLs = CloudKitListingCache.strayURLs(forZoneChecksum: zoneChecksum)
        #expect(strayURLs.count == 2)
        defer { strayURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

        for url in strayURLs {
            CloudKitListingCache.save(sampleSnapshot("stale"), to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }

        #expect(CloudKitListingCache.discardStrayCaches(forZoneChecksum: zoneChecksum))

        for url in strayURLs {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("Discarding stray caches reports nothing to do when the location is clean")
    func noStrayCachesIsNotReported() {
        let strayURLs = CloudKitListingCache.strayURLs(forZoneChecksum: "checksum-with-no-stray-file")
        strayURLs.forEach { try? FileManager.default.removeItem(at: $0) }

        #expect(!CloudKitListingCache.discardStrayCaches(forZoneChecksum: "checksum-with-no-stray-file"))
    }

    /// A rebuilt store must start from a full fetch even if a cache file is sitting in
    /// the directory. Previously this held only because the event store happened to
    /// delete its directory before recreating it, leaving nothing to load — a guarantee
    /// resting on another type's internal ordering. The discard is now explicit, so this
    /// test pins the behaviour against that ordering changing.
    @Test("A cache in a rebuilt store directory is deleted, not loaded")
    func rebuiltStoreDiscardsCacheLeftInPlace() throws {
        let storeDir = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let cacheURL = CloudKitListingCache.url(inStoreDirectory: storeDir.path, zoneChecksum: zoneChecksum)
        CloudKitListingCache.save(sampleSnapshot("from-previous-incarnation"), to: cacheURL)
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))

        CloudKitListingCache.discardCache(inStoreDirectory: storeDir.path, zoneChecksum: zoneChecksum)

        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
        #expect(CloudKitListingCache.load(from: cacheURL) == nil)
    }

    @Test("Discarding a stray cache leaves the store's own cache untouched")
    func discardingStraysDoesNotTouchStoreCache() throws {
        let storeDir = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let cacheURL = CloudKitListingCache.url(inStoreDirectory: storeDir.path, zoneChecksum: zoneChecksum)
        let snapshot = sampleSnapshot("keepme")
        CloudKitListingCache.save(snapshot, to: cacheURL)

        let strayURLs = CloudKitListingCache.strayURLs(forZoneChecksum: zoneChecksum)
        defer { strayURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
        CloudKitListingCache.save(sampleSnapshot("stale"), to: strayURLs[0])

        CloudKitListingCache.discardStrayCaches(forZoneChecksum: zoneChecksum)

        #expect(CloudKitListingCache.load(from: cacheURL) == snapshot)
    }
}
