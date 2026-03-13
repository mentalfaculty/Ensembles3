import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

extension SyncTests {
@Suite("EmptyStoreSync", .serialized)
@MainActor
struct EmptyStoreSyncTests {

    let stack: SyncTestStack

    init() {
        stack = SyncTestStack()
    }

    // MARK: - Helpers

    private func prepareDevice1WithDataDevice2Empty() async throws {
        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("bob", forKey: "name")
        stack.save(stack.context1)
        try await stack.attachStores()
        try await stack.syncEnsemble(stack.ensemble1)
    }

    private func prepareDevice1WithDataDevice2Merged() async throws {
        try await prepareDevice1WithDataDevice2Empty()
        try await stack.syncEnsemble(stack.ensemble2)
    }

    private func prepareBothDevicesEmpty() async throws {
        try await stack.attachStores()
    }

    /// Insert a Parent with a unique name in contextA, sync, check it appears in contextB.
    private func changeInContext(_ contextA: NSManagedObjectContext, appearsInContext contextB: NSManagedObjectContext) async throws -> Bool {
        let uniqueString = ProcessInfo.processInfo.globallyUniqueString
        let newParent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: contextA)
        newParent.setValue(uniqueString, forKey: "name")
        stack.save(contextA)

        try await stack.syncChangesAndSuppressRebase()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents = (try? contextB.fetch(fetch)) ?? []
        let parentNames = parents.compactMap { $0.value(forKey: "name") as? String }
        return parentNames.contains(uniqueString)
    }

    // MARK: - Tests

    @Test("Changes from empty store are detected")
    func changesFromEmptyStoreAreDetected() async throws {
        try await prepareDevice1WithDataDevice2Merged()
        let result = try await changeInContext(stack.context2, appearsInContext: stack.context1)
        #expect(result)
    }

    @Test("Changes from non-empty store are detected")
    func changesFromNonEmptyStoreAreDetected() async throws {
        try await prepareDevice1WithDataDevice2Merged()
        let result = try await changeInContext(stack.context1, appearsInContext: stack.context2)
        #expect(result)
    }

    @Test("Sync works after rebase from device with original data")
    func syncWorksAfterRebaseFromDeviceWithOriginalData() async throws {
        try await prepareDevice1WithDataDevice2Merged()
        #expect(try await changeInContext(stack.context2, appearsInContext: stack.context1))
        #expect(try await changeInContext(stack.context1, appearsInContext: stack.context2))
        #expect(try await changeInContext(stack.context2, appearsInContext: stack.context1))

        try await stack.ensemble1.sync(options: .forceRebase)
        try await stack.syncChanges()

        let fetchParents = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        #expect(try stack.context1.fetch(fetchParents).count == 4)
        #expect(try stack.context2.fetch(fetchParents).count == 4)

        #expect(try await changeInContext(stack.context1, appearsInContext: stack.context2))
        #expect(try await changeInContext(stack.context2, appearsInContext: stack.context1))
    }

    @Test("Sync works after rebase from device originally empty")
    func syncWorksAfterRebaseFromDeviceOriginallyEmpty() async throws {
        try await prepareDevice1WithDataDevice2Merged()
        #expect(try await changeInContext(stack.context2, appearsInContext: stack.context1))
        #expect(try await changeInContext(stack.context1, appearsInContext: stack.context2))
        #expect(try await changeInContext(stack.context2, appearsInContext: stack.context1))

        try await stack.ensemble2.sync(options: .forceRebase)
        try await stack.syncChanges()

        let fetchParents = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        #expect(try stack.context1.fetch(fetchParents).count == 4)
        #expect(try stack.context2.fetch(fetchParents).count == 4)

        #expect(try await changeInContext(stack.context1, appearsInContext: stack.context2))
        #expect(try await changeInContext(stack.context2, appearsInContext: stack.context1))
    }

    @Test("Sync works after rebasing while other device still empty")
    func syncWorksAfterRebasingWhileOtherDeviceStillEmpty() async throws {
        try await prepareDevice1WithDataDevice2Merged()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("dave", forKey: "name")
        stack.save(stack.context1)

        try await stack.ensemble1.sync(options: .forceRebase)
        try await stack.syncEnsemble(stack.ensemble2)

        let fetchParents = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        #expect(try stack.context1.fetch(fetchParents).count == 2)
        #expect(try stack.context2.fetch(fetchParents).count == 2)

        #expect(try await changeInContext(stack.context1, appearsInContext: stack.context2))
        #expect(try await changeInContext(stack.context2, appearsInContext: stack.context1))
    }

    @Test("Sync works starting from merged empty baselines")
    func syncWorksStartingFromMergedEmptyBaselines() async throws {
        try await prepareBothDevicesEmpty()
        try await stack.syncChanges()

        #expect(try await changeInContext(stack.context1, appearsInContext: stack.context2))
        #expect(try await changeInContext(stack.context2, appearsInContext: stack.context1))
    }

    @Test("Sync works after rebasing from merged empty baselines")
    func syncWorksAfterRebasingFromMergedEmptyBaselines() async throws {
        try await prepareBothDevicesEmpty()
        try await stack.syncChanges()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("dave", forKey: "name")
        stack.save(stack.context1)

        try await stack.ensemble1.sync(options: .forceRebase)
        try await stack.syncEnsemble(stack.ensemble2)

        let fetchParents = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        #expect(try stack.context1.fetch(fetchParents).count == 1)
        #expect(try stack.context2.fetch(fetchParents).count == 1)

        #expect(try await changeInContext(stack.context1, appearsInContext: stack.context2))
        #expect(try await changeInContext(stack.context2, appearsInContext: stack.context1))
    }
}
}
