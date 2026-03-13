import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

#if canImport(SwiftData)
import SwiftData
import EnsemblesSwiftData

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
@Model
final class SDItem {
    var title: String
    var timestamp: Date
    var uniqueID: String

    init(title: String, timestamp: Date = .now, uniqueID: String = UUID().uuidString) {
        self.title = title
        self.timestamp = timestamp
        self.uniqueID = uniqueID
    }
}
#endif

@Suite("SwiftDataSync", .serialized)
@MainActor
struct SwiftDataSyncTests {

    @Test("Insert syncs to second device")
    func insertSyncsToSecondDevice() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let stack = SwiftDataSyncTestStack(modelTypes: [SDItem.self])
        try await stack.attachStores()

        let item = NSEntityDescription.insertNewObject(forEntityName: "SDItem", into: stack.context1)
        item.setValue("Hello", forKey: "title")
        item.setValue(Date(), forKey: "timestamp")
        item.setValue(UUID().uuidString, forKey: "uniqueID")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let items2 = stack.fetchObjects(entity: "SDItem", in: stack.context2)
        #expect(items2.count == 1)
        #expect(items2.first?.value(forKey: "title") as? String == "Hello")
        #endif
    }

    @Test("Update attribute syncs")
    func updateAttributeSyncs() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let stack = SwiftDataSyncTestStack(modelTypes: [SDItem.self])
        try await stack.attachStores()

        let item = NSEntityDescription.insertNewObject(forEntityName: "SDItem", into: stack.context1)
        item.setValue("Original", forKey: "title")
        item.setValue(Date(), forKey: "timestamp")
        item.setValue(UUID().uuidString, forKey: "uniqueID")
        stack.save(stack.context1)

        try await stack.syncChanges()

        // Update on device 2
        let items2 = stack.fetchObjects(entity: "SDItem", in: stack.context2)
        #expect(items2.count == 1)
        items2.first?.setValue("Updated", forKey: "title")
        stack.save(stack.context2)

        try await stack.syncChanges()

        // Verify on device 1
        let items1 = stack.fetchObjects(entity: "SDItem", in: stack.context1)
        #expect(items1.count == 1)
        #expect(items1.first?.value(forKey: "title") as? String == "Updated")
        #endif
    }

    @Test("Conflicting attribute updates")
    func conflictingAttributeUpdates() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let stack = SwiftDataSyncTestStack(modelTypes: [SDItem.self])
        try await stack.attachStores()

        let item1 = NSEntityDescription.insertNewObject(forEntityName: "SDItem", into: stack.context1)
        item1.setValue("Original", forKey: "title")
        item1.setValue(Date(), forKey: "timestamp")
        item1.setValue(UUID().uuidString, forKey: "uniqueID")
        stack.save(stack.context1)

        try await stack.syncChanges()

        // Update on device 1
        item1.setValue("FromDevice1", forKey: "title")
        stack.save(stack.context1)

        // Concurrent update on device 2 (later timestamp wins)
        let items2 = stack.fetchObjects(entity: "SDItem", in: stack.context2)
        items2.first?.setValue("FromDevice2", forKey: "title")
        stack.save(stack.context2)

        try await stack.syncChanges()

        // Last writer (device 2) wins
        let finalItems1 = stack.fetchObjects(entity: "SDItem", in: stack.context1)
        let finalItems2 = stack.fetchObjects(entity: "SDItem", in: stack.context2)
        #expect(finalItems1.count == 1)
        #expect(finalItems2.count == 1)
        #expect(finalItems1.first?.value(forKey: "title") as? String == finalItems2.first?.value(forKey: "title") as? String)
        #endif
    }

    @Test("Delete syncs")
    func deleteSyncs() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let stack = SwiftDataSyncTestStack(modelTypes: [SDItem.self])
        try await stack.attachStores()

        let item = NSEntityDescription.insertNewObject(forEntityName: "SDItem", into: stack.context1)
        item.setValue("ToDelete", forKey: "title")
        item.setValue(Date(), forKey: "timestamp")
        item.setValue(UUID().uuidString, forKey: "uniqueID")
        stack.save(stack.context1)

        try await stack.syncChanges()

        // Verify it arrived
        let items2Before = stack.fetchObjects(entity: "SDItem", in: stack.context2)
        #expect(items2Before.count == 1)

        // Delete on device 1
        nonisolated(unsafe) let itemToDelete = item
        stack.context1.performAndWait {
            stack.context1.delete(itemToDelete)
        }
        stack.save(stack.context1)

        try await stack.syncChanges()

        // Verify deleted on device 2
        let items2After = stack.fetchObjects(entity: "SDItem", in: stack.context2)
        #expect(items2After.count == 0)
        #endif
    }

    @Test("Concurrent inserts with same global ID deduplicate")
    func concurrentInsertsWithSameGlobalID() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let sharedID = "shared-unique-id"
        let stack = SwiftDataSyncTestStack(modelTypes: [SDItem.self])
        stack.globalIdentifiersBlock = { objects in
            objects.map { $0.value(forKey: "uniqueID") as? String }
        }
        try await stack.attachStores()

        // Insert same logical object on both devices
        let item1 = NSEntityDescription.insertNewObject(forEntityName: "SDItem", into: stack.context1)
        item1.setValue("Device1", forKey: "title")
        item1.setValue(Date(), forKey: "timestamp")
        item1.setValue(sharedID, forKey: "uniqueID")
        stack.save(stack.context1)

        let item2 = NSEntityDescription.insertNewObject(forEntityName: "SDItem", into: stack.context2)
        item2.setValue("Device2", forKey: "title")
        item2.setValue(Date(), forKey: "timestamp")
        item2.setValue(sharedID, forKey: "uniqueID")
        stack.save(stack.context2)

        try await stack.syncChanges()

        // Should deduplicate to a single object
        let finalItems1 = stack.fetchObjects(entity: "SDItem", in: stack.context1)
        let finalItems2 = stack.fetchObjects(entity: "SDItem", in: stack.context2)
        #expect(finalItems1.count == 1)
        #expect(finalItems2.count == 1)
        #endif
    }

    @Test("Multiple objects sync")
    func multipleObjectsSync() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let stack = SwiftDataSyncTestStack(modelTypes: [SDItem.self])
        try await stack.attachStores()

        // Insert on device 1
        for i in 1...3 {
            let item = NSEntityDescription.insertNewObject(forEntityName: "SDItem", into: stack.context1)
            item.setValue("D1_Item\(i)", forKey: "title")
            item.setValue(Date(), forKey: "timestamp")
            item.setValue(UUID().uuidString, forKey: "uniqueID")
        }
        stack.save(stack.context1)

        // Insert on device 2
        for i in 1...2 {
            let item = NSEntityDescription.insertNewObject(forEntityName: "SDItem", into: stack.context2)
            item.setValue("D2_Item\(i)", forKey: "title")
            item.setValue(Date(), forKey: "timestamp")
            item.setValue(UUID().uuidString, forKey: "uniqueID")
        }
        stack.save(stack.context2)

        try await stack.syncChanges()

        // Both devices should have all 5 objects
        let items1 = stack.fetchObjects(entity: "SDItem", in: stack.context1)
        let items2 = stack.fetchObjects(entity: "SDItem", in: stack.context2)
        #expect(items1.count == 5)
        #expect(items2.count == 5)

        let titles1 = Set(items1.map { $0.value(forKey: "title") as! String })
        let titles2 = Set(items2.map { $0.value(forKey: "title") as! String })
        #expect(titles1 == titles2)
        #endif
    }

    @Test("Attach with excludeLocalData")
    func attachWithExcludeLocalData() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let stack = SwiftDataSyncTestStack(modelTypes: [SDItem.self])

        // Insert on device 1 before attaching
        let item1 = NSEntityDescription.insertNewObject(forEntityName: "SDItem", into: stack.context1)
        item1.setValue("FromDevice1", forKey: "title")
        item1.setValue(Date(), forKey: "timestamp")
        item1.setValue(UUID().uuidString, forKey: "uniqueID")
        stack.save(stack.context1)

        // Insert on device 2 before attaching
        let item2 = NSEntityDescription.insertNewObject(forEntityName: "SDItem", into: stack.context2)
        item2.setValue("FromDevice2", forKey: "title")
        item2.setValue(Date(), forKey: "timestamp")
        item2.setValue(UUID().uuidString, forKey: "uniqueID")
        stack.save(stack.context2)

        // Attach device 1 normally, device 2 with excludeLocalData
        try await stack.attachStoresExcludingDevice2Data()

        try await stack.syncChanges()

        // Device 2 should only have device 1's item (its own was excluded from seed)
        let items2 = stack.fetchObjects(entity: "SDItem", in: stack.context2)
        #expect(items2.count == 1)
        #expect(items2.first?.value(forKey: "title") as? String == "FromDevice1")

        // Device 1 should still have just its own item
        let items1 = stack.fetchObjects(entity: "SDItem", in: stack.context1)
        #expect(items1.count == 1)
        #expect(items1.first?.value(forKey: "title") as? String == "FromDevice1")
        #endif
    }
}
