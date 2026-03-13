import Foundation
@preconcurrency import CoreData
@_spi(Testing) import Ensembles

/// Sets up a real `EventIntegrator` with a disk-backed test store and event store.
/// Used by integration tests that need to merge events into a persistent store.
final class IntegratorTestStack: @unchecked Sendable {
    let setup: TestEventStoreSetup
    let integrator: EventIntegrator
    let testMOC: NSManagedObjectContext
    let eventMOC: NSManagedObjectContext
    let testModel: NSManagedObjectModel

    let ensemble: TestEnsemble

    init() throws {
        let s = try TestEventStoreSetup(useDiskTestStore: true, loadTestModel: true)
        let model = s.testModel!
        let integr = EventIntegrator(storeURL: s.testStoreURL!, managedObjectModel: model, eventStore: s.eventStore)

        let ens = TestEnsemble()
        if let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd") {
            ens.managedObjectModels = CoreDataEnsemble.loadAllModelVersions(from: modelURL)
        }
        integr.ensemble = ens

        // didSaveBlock merges integrator's changes back into the test MOC
        let weakTestMOC = s.testManagedObjectContext!
        integr.didSaveBlock = { context, info in
            weakTestMOC.performAndWait {
                weakTestMOC.mergeChanges(fromContextDidSave: Notification(name: .NSManagedObjectContextDidSave, object: context, userInfo: info))
            }
        }

        setup = s
        integrator = integr
        ensemble = ens
        testMOC = s.testManagedObjectContext!
        eventMOC = s.context
        testModel = model
    }

    // MARK: - Merge

    func mergeEvents() async throws {
        try await integrator.mergeEvents()
    }

    // MARK: - JSON Fixture Loading

    func addEventsFromJSONFile(_ filename: String, subdirectory: String? = nil) {
        let url: URL?
        if let subdirectory {
            url = Bundle.module.url(forResource: filename, withExtension: "json", subdirectory: "Integrator Test Fixtures/\(subdirectory)")
        } else {
            url = Bundle.module.url(forResource: filename, withExtension: "json", subdirectory: "Integrator Test Fixtures")
        }
        guard let url, let data = try? Data(contentsOf: url) else {
            preconditionFailure("Could not load JSON fixture: \(filename)")
        }
        guard let eventDicts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            preconditionFailure("Could not parse JSON fixture: \(filename)")
        }

        eventMOC.performAndWait {
            var globalIds: [String: GlobalIdentifier] = [:]

            for eventDict in eventDicts {
                let store = eventDict["store"] as? String ?? ""
                let revision = (eventDict["revision"] as? NSNumber)?.int64Value ?? 0
                let globalCount = (eventDict["globalCount"] as? NSNumber)?.int64Value ?? 0
                let timestamp = (eventDict["timestamp"] as? NSNumber)?.doubleValue ?? 0

                let modEvent = setup.addModEvent(store: store, revision: revision, globalCount: globalCount, timestamp: timestamp)

                // Other stores' revisions
                if let otherStores = eventDict["otherstores"] as? [[String: Any]] {
                    var otherRevs = Set<EventRevision>()
                    for revDict in otherStores {
                        let otherStore = revDict["store"] as? String ?? ""
                        let otherRev = (revDict["revision"] as? NSNumber)?.int64Value ?? 0
                        otherRevs.insert(setup.addEventRevision(store: otherStore, revision: otherRev))
                    }
                    modEvent.eventRevisionsOfOtherStores = otherRevs
                }

                // Changes
                if let changes = eventDict["changes"] as? [[String: Any]] {
                    for changeDict in changes {
                        let typeString = changeDict["type"] as? String ?? ""
                        let changeType: ObjectChangeType
                        switch typeString {
                        case "insert": changeType = .insert
                        case "update": changeType = .update
                        case "delete": changeType = .delete
                        default: continue
                        }

                        let entityName = changeDict["entity"] as? String ?? ""
                        let idString = changeDict["id"] as? String ?? ""

                        // Reuse existing global identifiers
                        let key = "\(entityName):\(idString)"
                        let globalId: GlobalIdentifier
                        if let existing = globalIds[key] {
                            globalId = existing
                        } else {
                            globalId = setup.addGlobalIdentifier(idString, entity: entityName)
                            globalIds[key] = globalId
                        }

                        let change = setup.addObjectChange(type: changeType, globalIdentifier: globalId, event: modEvent)

                        // Properties
                        if let properties = changeDict["properties"] as? [String: Any] {
                            let entity = testModel.entitiesByName[entityName]
                            var propertyChangeValues: [PropertyChangeValue] = []

                            for (propName, propValue) in properties {
                                let property = entity?.propertiesByName[propName]

                                if property is NSRelationshipDescription {
                                    let rel = property as! NSRelationshipDescription
                                    if rel.isToMany {
                                        if let dict = propValue as? [String: [String]] {
                                            let added = dict["add"] ?? []
                                            let removed = dict["remove"] ?? []
                                            propertyChangeValues.append(setup.toManyRelationshipChange(name: propName, added: added, removed: removed))
                                        }
                                    } else {
                                        let identifier = (propValue is NSNull) ? nil : propValue
                                        propertyChangeValues.append(setup.toOneRelationshipChange(name: propName, relatedIdentifier: identifier))
                                    }
                                } else {
                                    var value: Any? = propValue
                                    if propValue is NSNull { value = nil }

                                    // Date conversion: JSON stores as timeIntervalSinceReferenceDate
                                    if let attrDesc = property as? NSAttributeDescription, attrDesc.attributeType == .dateAttributeType, let num = value as? NSNumber {
                                        value = NSDate(timeIntervalSinceReferenceDate: num.doubleValue)
                                    }

                                    propertyChangeValues.append(setup.attributeChange(name: propName, value: value))
                                }
                            }
                            change.propertyChangeValues = propertyChangeValues as NSArray
                        }
                    }
                }
            }
            try? eventMOC.save()
        }
    }

    // MARK: - Fetch Helpers

    func fetchObjects(entity: String) -> [NSManagedObject] {
        nonisolated(unsafe) var result: [NSManagedObject] = []
        testMOC.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: entity)
            result = (try? testMOC.fetch(fetch)) ?? []
        }
        return result
    }

    func fetchParents() -> [NSManagedObject] {
        fetchObjects(entity: "Parent")
    }

    func fetchChildren() -> [NSManagedObject] {
        fetchObjects(entity: "Child")
    }
}
