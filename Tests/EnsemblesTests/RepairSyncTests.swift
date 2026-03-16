import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

extension SyncTests {
@Suite("RepairSync", .serialized)
@MainActor
struct RepairSyncTests {

    let stack: SyncTestStack

    init() {
        stack = SyncTestStack()
    }

    @Test("Deletion repair")
    func deletionRepair() async throws {
        try await stack.attachStores()

        let parent = stack.insertParent(name: "bob", in: stack.context1)
        parent.setValue(NSNumber(value: 10.0), forKey: "doubleProperty")
        stack.save(stack.context1)

        try await stack.syncEnsemble(stack.ensemble1)

        stack.shouldSaveBlock = { ensemble, savingContext, repairContext in
            savingContext.performAndWait {
                if let inserted = savingContext.insertedObjects.first {
                    let parentID = inserted.objectID
                    repairContext.performAndWait {
                        if let parentToDelete = try? repairContext.existingObject(with: parentID) {
                            repairContext.delete(parentToDelete)
                        }
                    }
                }
            }
        }

        try await stack.syncEnsemble(stack.ensemble2)
        stack.shouldSaveBlock = nil

        try await stack.syncEnsemble(stack.ensemble1)

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents = try stack.context1.fetch(fetch)
        #expect(parents.count == 0)
    }
}
}
