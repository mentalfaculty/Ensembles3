import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

extension SyncTests {
@Suite("SaveMonitor", .serialized)
struct SaveMonitorTests {

    let setup: TestEventStoreSetup
    let saveMonitor: SaveMonitor
    let ensemble: TestEnsemble
    let testMOC: NSManagedObjectContext

    init() throws {
        let s = try TestEventStoreSetup(useDiskTestStore: true, loadTestModel: true)
        let storePath = s.testStoreURL!.path
        let ens = TestEnsemble()
        if let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd") {
            ens.managedObjectModels = CoreDataEnsemble.loadAllModelVersions(from: modelURL)
        }
        let monitor = SaveMonitor(storePath: storePath)
        monitor.eventStore = s.eventStore
        monitor.ensemble = ens
        setup = s
        saveMonitor = monitor
        ensemble = ens
        testMOC = s.testManagedObjectContext!
    }

    private func saveTestContext() {
        testMOC.performAndWait {
            try! testMOC.save()
        }
    }

    private func fetchModEvents() throws -> [StoreModificationEvent] {
        let events = try setup.eventStore.fetchCompleteEvents()
        return events.sorted()
    }

    private func insertParent(name: String = "bob") -> NSManagedObject {
        var parent: NSManagedObject!
        testMOC.performAndWait {
            parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: testMOC)
            parent.setValue(name, forKey: "name")
            parent.setValue(NSDate(timeIntervalSinceReferenceDate: 0.0), forKey: "date")
        }
        return parent
    }

    // MARK: - Basic Tests

    @Test("No save triggers no event creation")
    func noSaveTriggersNoEventCreation() throws {
        let count = try setup.eventStore.countAllEvents()
        #expect(count == 0)
    }

    @Test("Save triggers event creation")
    func saveTriggersEventCreation() throws {
        let _ = insertParent()
        saveTestContext()
        let count = try setup.eventStore.countAllEvents()
        #expect(count == 1)
    }

    @Test("Insert generates object change")
    func insertGeneratesObjectChange() throws {
        let _ = insertParent()
        saveTestContext()
        let modEvents = try fetchModEvents()
        #expect(modEvents.count == 1)
    }

    @Test("Insert store modification event type is correct")
    func insertEventTypeIsCorrect() throws {
        let _ = insertParent()
        saveTestContext()
        let modEvents = try fetchModEvents()
        let modEvent = modEvents.last!
        #expect(modEvent.type == .save)
    }

    @Test("Object change count for insert")
    func objectChangeCountForInsert() throws {
        let _ = insertParent()
        saveTestContext()
        let modEvents = try fetchModEvents()
        let modEvent = modEvents.last!
        let changes = try setup.eventStore.fetchObjectChanges(eventId: modEvent.id)
        #expect(changes.count == 1)
    }

    @Test("Object change type for insert")
    func objectChangeTypeForInsert() throws {
        let _ = insertParent()
        saveTestContext()
        let modEvents = try fetchModEvents()
        let modEvent = modEvents.last!
        let changes = try setup.eventStore.fetchObjectChanges(eventId: modEvent.id)
        let change = changes.first!
        #expect(change.type == .insert)
    }

    @Test("Global identifier is generated for insert")
    func globalIdentifierIsGeneratedForInsert() throws {
        let _ = insertParent()
        saveTestContext()
        let modEvents = try fetchModEvents()
        let modEvent = modEvents.last!
        let changes = try setup.eventStore.fetchObjectChanges(eventId: modEvent.id)
        let change = changes.first!
        let gid = try setup.eventStore.fetchGlobalIdentifier(id: change.globalIdentifierId)
        #expect(gid != nil)
        #expect(!gid!.globalIdentifier.isEmpty)
        #expect(gid!.storeURI != nil)
    }

    @Test("Global count for one save")
    func globalCountForOneSave() throws {
        let _ = insertParent()
        saveTestContext()
        let modEvents = try fetchModEvents()
        let modEvent = modEvents.last!
        #expect(modEvent.globalCount == 0)
    }

    @Test("Global count for two saves")
    func globalCountForTwoSaves() throws {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            parent.setValue(NSDate(timeIntervalSinceReferenceDate: 0.1), forKey: "date")
        }
        saveTestContext()

        let modEvents = try fetchModEvents()
        let modEvent = modEvents.last!
        #expect(modEvent.globalCount == 1)
    }

    @Test("Update generates mod event")
    func updateGeneratesModEvent() throws {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            parent.setValue(NSDate(timeIntervalSinceReferenceDate: 0.1), forKey: "date")
        }
        saveTestContext()

        let modEvents = try fetchModEvents()
        #expect(modEvents.count == 2)
    }

    @Test("Update with nil value")
    func updateWithNilValue() throws {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            parent.setValue(nil, forKey: "name")
        }
        saveTestContext()

        let modEvents = try fetchModEvents()
        let modEvent = modEvents.last!
        let changes = try setup.eventStore.fetchObjectChanges(eventId: modEvent.id)
        let change = changes.first!
        let propertyChanges = change.propertyChangeValues ?? []
        #expect(propertyChanges.count == 1)
        let newValue = propertyChanges.last!
        #expect(newValue.value == nil || newValue.value == .null)
        #expect(newValue.type == PropertyChangeType.attribute.rawValue)
    }

    @Test("Save revision numbers")
    func saveRevisionNumbers() throws {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            parent.setValue(NSDate(timeIntervalSinceReferenceDate: 0.1), forKey: "date")
        }
        saveTestContext()

        let modEvents = try fetchModEvents()
        let firstEvent = modEvents[0]
        let secondEvent = modEvents[1]
        let firstRev = try setup.eventStore.fetchEventRevision(eventId: firstEvent.id)
        let secondRev = try setup.eventStore.fetchEventRevision(eventId: secondEvent.id)
        #expect(firstRev?.revisionNumber == 0)
        #expect(secondRev?.revisionNumber == 1)
    }

    @Test("Revision numbers of other stores for a single store")
    func revisionNumbersOfOtherStoresForSingleStore() throws {
        let _ = insertParent()
        saveTestContext()
        let modEvents = try fetchModEvents()
        let firstEvent = modEvents[0]
        let otherRevisions = try setup.eventStore.fetchOtherStoreRevisions(eventId: firstEvent.id)
        #expect(otherRevisions.count == 0)
    }

    @Test("Update generates object changes")
    func updateGeneratesObjectChanges() throws {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            parent.setValue(NSDate(timeIntervalSinceReferenceDate: 0.1), forKey: "date")
        }
        saveTestContext()

        let modEvents = try fetchModEvents()
        let modEvent = modEvents.last!
        let objectChanges = try setup.eventStore.fetchObjectChanges(eventId: modEvent.id)
        #expect(objectChanges.count == 1)

        let change = objectChanges.first!
        #expect(change.type == .update)

        let propertyChanges = change.propertyChangeValues ?? []
        #expect(propertyChanges.count == 1)
    }

    @Test("Deletion generates object change")
    func deletionGeneratesObjectChange() throws {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            testMOC.delete(parent)
        }
        saveTestContext()

        let modEvents = try fetchModEvents()
        #expect(modEvents.count == 2)

        let modEvent = modEvents.last!
        let objectChanges = try setup.eventStore.fetchObjectChanges(eventId: modEvent.id)
        #expect(objectChanges.count == 1)
        let change = objectChanges.first!
        #expect(change.type == .delete)
    }
}
}
