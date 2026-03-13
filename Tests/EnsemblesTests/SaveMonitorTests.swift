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
    let eventMOC: NSManagedObjectContext

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
        eventMOC = s.context
    }

    private func saveTestContext() {
        testMOC.performAndWait {
            try! testMOC.save()
        }
        // Wait for the async event creation to complete
        eventMOC.performAndWait { /* force synchronization */ }
    }

    private func fetchModEvents() -> [StoreModificationEvent] {
        nonisolated(unsafe) var result: [StoreModificationEvent] = []
        eventMOC.performAndWait {
            let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            fetch.sortDescriptors = [
                NSSortDescriptor(key: "eventRevision.persistentStoreIdentifier", ascending: true),
                NSSortDescriptor(key: "eventRevision.revisionNumber", ascending: true)
            ]
            result = (try? eventMOC.fetch(fetch)) ?? []
        }
        return result
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
    func noSaveTriggersNoEventCreation() {
        eventMOC.performAndWait {
            let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            let count = (try? eventMOC.count(for: fetch)) ?? -1
            #expect(count == 0)
        }
    }

    @Test("Save triggers event creation")
    func saveTriggersEventCreation() {
        let _ = insertParent()
        saveTestContext()
        eventMOC.performAndWait {
            let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            let count = (try? eventMOC.count(for: fetch)) ?? -1
            #expect(count == 1)
        }
    }

    @Test("Insert generates object change")
    func insertGeneratesObjectChange() {
        let _ = insertParent()
        saveTestContext()
        let modEvents = fetchModEvents()
        #expect(modEvents.count == 1)
    }

    @Test("Insert store modification event type is correct")
    func insertEventTypeIsCorrect() {
        let _ = insertParent()
        saveTestContext()
        eventMOC.performAndWait {
            let modEvents = fetchModEvents()
            let modEvent = modEvents.last!
            #expect(modEvent.storeModificationEventType == .save)
        }
    }

    @Test("Object change count for insert")
    func objectChangeCountForInsert() {
        let _ = insertParent()
        saveTestContext()
        eventMOC.performAndWait {
            let modEvents = fetchModEvents()
            let modEvent = modEvents.last!
            #expect(modEvent.objectChanges.count == 1)
        }
    }

    @Test("Object change type for insert")
    func objectChangeTypeForInsert() {
        let _ = insertParent()
        saveTestContext()
        eventMOC.performAndWait {
            let modEvents = fetchModEvents()
            let modEvent = modEvents.last!
            let change = modEvent.objectChanges.first!
            #expect(change.objectChangeType == .insert)
        }
    }

    @Test("Global identifier is generated for insert")
    func globalIdentifierIsGeneratedForInsert() {
        let _ = insertParent()
        saveTestContext()
        eventMOC.performAndWait {
            let modEvents = fetchModEvents()
            let modEvent = modEvents.last!
            let change = modEvent.objectChanges.first!
            #expect(change.globalIdentifier != nil)
            #expect(change.globalIdentifier?.globalIdentifier != nil)
            #expect(change.globalIdentifier?.storeURI != nil)
        }
    }

    @Test("Global count for one save")
    func globalCountForOneSave() {
        let _ = insertParent()
        saveTestContext()
        eventMOC.performAndWait {
            let modEvents = fetchModEvents()
            let modEvent = modEvents.last!
            #expect(modEvent.globalCount == 0)
        }
    }

    @Test("Global count for two saves")
    func globalCountForTwoSaves() {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            parent.setValue(NSDate(timeIntervalSinceReferenceDate: 0.1), forKey: "date")
        }
        saveTestContext()

        eventMOC.performAndWait {
            let modEvents = fetchModEvents()
            let modEvent = modEvents.last!
            #expect(modEvent.globalCount == 1)
        }
    }

    @Test("Update generates mod event")
    func updateGeneratesModEvent() {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            parent.setValue(NSDate(timeIntervalSinceReferenceDate: 0.1), forKey: "date")
        }
        saveTestContext()

        let modEvents = fetchModEvents()
        #expect(modEvents.count == 2)
    }

    @Test("Update with nil value")
    func updateWithNilValue() {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            parent.setValue(nil, forKey: "name")
        }
        saveTestContext()

        eventMOC.performAndWait {
            let modEvents = fetchModEvents()
            let modEvent = modEvents.last!
            let change = modEvent.objectChanges.first!
            let propertyChanges = change.propertyChangeValues as? [PropertyChangeValue] ?? []
            #expect(propertyChanges.count == 1)
            let newValue = propertyChanges.last!
            #expect(newValue.value == nil)
            #expect(newValue.type == .attribute)
        }
    }

    @Test("Save revision numbers")
    func saveRevisionNumbers() {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            parent.setValue(NSDate(timeIntervalSinceReferenceDate: 0.1), forKey: "date")
        }
        saveTestContext()

        eventMOC.performAndWait {
            let modEvents = fetchModEvents()
            let firstEvent = modEvents[0]
            let secondEvent = modEvents[1]
            #expect(firstEvent.eventRevision?.revisionNumber == 0)
            #expect(secondEvent.eventRevision?.revisionNumber == 1)
        }
    }

    @Test("Revision numbers of other stores for a single store")
    func revisionNumbersOfOtherStoresForSingleStore() {
        let _ = insertParent()
        saveTestContext()
        eventMOC.performAndWait {
            let modEvents = fetchModEvents()
            let firstEvent = modEvents[0]
            #expect(firstEvent.eventRevisionsOfOtherStores.count == 0)
        }
    }

    @Test("Update generates object changes")
    func updateGeneratesObjectChanges() {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            parent.setValue(NSDate(timeIntervalSinceReferenceDate: 0.1), forKey: "date")
        }
        saveTestContext()

        eventMOC.performAndWait {
            let modEvents = fetchModEvents()
            let modEvent = modEvents.last!
            let objectChanges = modEvent.objectChanges
            #expect(objectChanges.count == 1)

            let change = objectChanges.first!
            #expect(change.objectChangeType == .update)

            let propertyChanges = change.propertyChangeValues as? [PropertyChangeValue] ?? []
            #expect(propertyChanges.count == 1)
        }
    }

    @Test("Deletion generates object change")
    func deletionGeneratesObjectChange() {
        let parent = insertParent()
        saveTestContext()

        testMOC.performAndWait {
            testMOC.delete(parent)
        }
        saveTestContext()

        let modEvents = fetchModEvents()
        #expect(modEvents.count == 2)

        eventMOC.performAndWait {
            let modEvent = modEvents.last!
            #expect(modEvent.objectChanges.count == 1)
            let change = modEvent.objectChanges.first!
            #expect(change.objectChangeType == .delete)
        }
    }
}
}
