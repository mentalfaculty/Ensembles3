import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

/// A value class that adopts only `NSCoding`, as an app's scheduler or rule object might.
/// Core Data stores it in a transformable attribute with no transformer name using the
/// non-secure keyed archiver; the secure archiver refuses it.
@objc(CDEPlainCodingValue)
final class PlainCodingValue: NSObject, NSCoding {
    let number: Int
    init(number: Int) { self.number = number }
    func encode(with coder: NSCoder) { coder.encode(number, forKey: "number") }
    required init?(coder: NSCoder) { number = coder.decodeInteger(forKey: "number") }
}

/// Minimal data-file store that only carries the archiving setting, for property-level tests.
private final class ArchivingStore: DataFileStoring {
    let unnamedTransformableArchiving: UnnamedTransformableArchiving
    init(_ archiving: UnnamedTransformableArchiving) { unnamedTransformableArchiving = archiving }
    func storeData(inFile data: Data) -> String? { nil }
    func data(forFile filename: String) -> Data? { nil }
}

/// `TransformableContainer.attributedString` in the test model is a transformable attribute
/// with NO transformer name, the case these tests cover.
private let unnamedAttributeName = "attributedString"

private func makeInMemoryContext(declaringValueClass valueClass: AnyClass? = nil) -> NSManagedObjectContext {
    let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
    var model = TestModelCache.model(for: modelURL)!
    if let valueClass {
        // Copy before editing: the cached model is shared with other tests.
        model = model.copy() as! NSManagedObjectModel
        model.entitiesByName["TransformableContainer"]!.attributesByName[unnamedAttributeName]!.attributeValueClassName = NSStringFromClass(valueClass)
    }
    let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
    try! psc.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
    let ctx = NSManagedObjectContext(.mainQueue)
    ctx.persistentStoreCoordinator = psc
    return ctx
}

@Suite("Unnamed transformable archiving", .serialized)
@MainActor
struct UnnamedTransformableArchivingTests {

    /// Saves `value` in the unnamed transformable and captures it as an event would.
    private func capture(_ value: Any?, store: DataFileStoring?, declaringValueClass valueClass: AnyClass? = nil) -> (PropertyChangeValue, NSAttributeDescription) {
        let ctx = makeInMemoryContext(declaringValueClass: valueClass)
        let obj = NSEntityDescription.insertNewObject(forEntityName: "TransformableContainer", into: ctx)
        obj.setValue(value, forKey: unnamedAttributeName)
        try! ctx.save()
        let attribute = obj.entity.attributesByName[unnamedAttributeName]!
        #expect(attribute.valueTransformerName == nil, "test model changed: attribute must name no transformer")
        let pcv = PropertyChangeValue(object: obj, propertyDescription: attribute, eventStore: store, isPreSave: false, storeValues: true)
        return (pcv, attribute)
    }

    /// Stores the captured change as JSON (what the event store does) and decodes it again.
    private func reload(_ pcv: PropertyChangeValue) throws -> StoredPropertyChange {
        try StoredPropertyChange.decode(from: StoredPropertyChange.encode([pcv.toStoredPropertyChange()]))[0]
    }

    private func e2Wire(_ data: Data) -> [Any] { ["data", data.base64EncodedString()] }

    // MARK: Default (.secureCoding): unchanged, except it never aborts

    /// The Studies crash: before the fix the secure transformer raised an uncatchable
    /// NSInvalidArchiveOperationException here and the process aborted.
    @Test("Default: an NSCoding-only value is left out of the event, not a crash")
    func defaultRefusesNSCodingOnlyValueWithoutAborting() {
        let (pcv, _) = capture(PlainCodingValue(number: 7), store: ArchivingStore(.secureCoding))
        #expect(pcv.valueCaptureFailed)
        #expect(pcv.value == nil)
        #expect(pcv.filename == nil)
    }

    /// The secure ARCHIVER accepts these (they adopt NSSecureCoding), but the secure read
    /// side allows only plist classes plus the declared value class, so a peer would decode
    /// nil and blank its own value. They must be refused at capture instead.
    @Test("Default: secure-coding values a peer cannot decode are left out", arguments: ["predicate", "attributedString", "nestedAttributedString"])
    func defaultRefusesValuesPeersCannotDecode(kind: String) {
        let value: NSObject = switch kind {
        case "predicate": NSPredicate(format: "number > 3")
        case "attributedString": NSAttributedString(string: "styled")
        default: NSArray(object: NSAttributedString(string: "nested"))
        }
        let (pcv, _) = capture(value, store: ArchivingStore(.secureCoding))
        #expect(pcv.valueCaptureFailed, "\(type(of: value)) would decode to nil on a peer")
        #expect(pcv.value == nil)
    }

    @Test("Default: a value of the declared value class is still captured")
    func defaultAcceptsDeclaredValueClass() throws {
        let store = ArchivingStore(.secureCoding)
        let value = NSAttributedString(string: "declared")
        let (pcv, attribute) = capture(value, store: store, declaringValueClass: NSAttributedString.self)
        #expect(!pcv.valueCaptureFailed)
        let decoded = try reload(pcv).attributeValue(for: attribute, eventStore: store) as? NSAttributedString
        #expect(decoded == value)
    }

    @Test("Default: a nil store reference behaves as secure coding")
    func defaultWithoutStoreIsSecure() {
        let (pcv, _) = capture(PlainCodingValue(number: 7), store: nil)
        #expect(pcv.valueCaptureFailed)
    }

    @Test("Default: secure value bytes are unchanged and round-trip")
    func defaultSecureValueUnchanged() throws {
        let array: NSArray = ["a", NSNumber(value: 1)]
        let (pcv, attribute) = capture(array, store: ArchivingStore(.secureCoding))
        #expect(!pcv.valueCaptureFailed)
        let expected = ValueTransformer(forName: .secureUnarchiveFromDataTransformerName)!.reverseTransformedValue(array) as? Data
        #expect(pcv.value as? Data == expected, "default archive bytes must match the secure transformer's")
        let decoded = try reload(pcv).attributeValue(for: attribute, eventStore: ArchivingStore(.secureCoding)) as? NSArray
        #expect(decoded == array)
    }

    @Test("Default: a nil value is captured as nil, not as a failure")
    func defaultNilValue() {
        let (pcv, _) = capture(nil, store: ArchivingStore(.secureCoding))
        #expect(!pcv.valueCaptureFailed)
        #expect(pcv.value == nil)
    }

    @Test("Default: an Ensembles 2 archive of an NSCoding-only class still decodes to nil")
    func defaultStillRefusesNSCodingOnlyArchive() throws {
        let ctx = makeInMemoryContext()
        let attribute = ctx.persistentStoreCoordinator!.managedObjectModel.entitiesByName["TransformableContainer"]!.attributesByName[unnamedAttributeName]!
        let archived = try NSKeyedArchiver.archivedData(withRootObject: PlainCodingValue(number: 3), requiringSecureCoding: false)
        let stored = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: unnamedAttributeName,
                                          value: StoredValue.from(JSONEventImport.coreDataValue(fromJSONValue: e2Wire(archived))))
        #expect(stored.attributeValue(for: attribute, eventStore: ArchivingStore(.secureCoding)) == nil)
        #expect(stored.attributeValue(for: attribute, eventStore: nil) == nil)
    }

    // MARK: Opt-in (.keyedArchiver)

    @Test("Keyed archiver: an NSCoding-only value is captured and round-trips")
    func keyedArchiverRoundTrip() throws {
        let store = ArchivingStore(.keyedArchiver)
        let value = PlainCodingValue(number: 42)
        let (pcv, attribute) = capture(value, store: store)
        #expect(!pcv.valueCaptureFailed)
        let expected = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false)
        #expect(pcv.value as? Data == expected, "bytes must match Core Data's non-secure keyed archive")
        let decoded = try reload(pcv).attributeValue(for: attribute, eventStore: store) as? PlainCodingValue
        #expect(decoded?.number == 42)
        // The capture-side PropertyChangeValue decodes the same way.
        #expect((pcv.attributeValue(for: attribute) as? PlainCodingValue)?.number == 42)
    }

    @Test("Keyed archiver: an NSPredicate is captured and round-trips")
    func keyedArchiverPredicateRoundTrip() throws {
        let store = ArchivingStore(.keyedArchiver)
        let (pcv, attribute) = capture(NSPredicate(format: "number > 3"), store: store)
        #expect(!pcv.valueCaptureFailed)
        let decoded = try reload(pcv).attributeValue(for: attribute, eventStore: store) as? NSPredicate
        #expect(decoded?.predicateFormat == "number > 3")
    }

    @Test("Keyed archiver: plist values give the same bytes as the default")
    func keyedArchiverPlistBytesMatchDefault() {
        let array: NSArray = ["x", NSNumber(value: 2)]
        let (secure, _) = capture(array, store: ArchivingStore(.secureCoding))
        let (keyed, _) = capture(array, store: ArchivingStore(.keyedArchiver))
        #expect(secure.value as? Data != nil)
        #expect(secure.value as? Data == keyed.value as? Data)
    }

    @Test("Keyed archiver: corrupt or unknown-class archives decode to nil, never crash")
    func keyedArchiverCorruptDegradesToNil() throws {
        let ctx = makeInMemoryContext()
        let attribute = ctx.persistentStoreCoordinator!.managedObjectModel.entitiesByName["TransformableContainer"]!.attributesByName[unnamedAttributeName]!
        let store = ArchivingStore(.keyedArchiver)

        let garbage = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: unnamedAttributeName,
                                           value: StoredValue.from(Data([1, 2, 3, 4])))
        #expect(garbage.attributeValue(for: attribute, eventStore: store) == nil)

        var archived = try NSKeyedArchiver.archivedData(withRootObject: PlainCodingValue(number: 1), requiringSecureCoding: false)
        let name = Data("CDEPlainCodingValue".utf8)
        let range = try #require(archived.range(of: name))
        archived.replaceSubrange(range, with: Data("CDENoSuchClassXXXXX".utf8))
        let unknown = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: unnamedAttributeName,
                                           value: StoredValue.from(archived))
        #expect(unknown.attributeValue(for: attribute, eventStore: store) == nil)
    }

    /// An Ensembles 2 device (Studies 1.8) writes the non-secure keyed archive inline in the
    /// event JSON as `["data", base64]`. Import the event file through the real
    /// `JSONEventImport` into a real event store, read the persisted change back, and decode
    /// it the way `UpdateStage` does during a merge.
    @Test("Keyed archiver: an Ensembles 2 event's NSCoding-only value and NSPredicate decode")
    func keyedArchiverDecodesEnsembles2Event() throws {
        let setup = try TestEventStoreSetup(loadTestModel: true)
        let eventStore = setup.eventStore
        eventStore.unnamedTransformableArchiving = .keyedArchiver

        let entityName = "TransformableContainer"
        _ = try eventStore.insertGlobalIdentifier(globalIdentifier: "e2-1", nameOfEntity: entityName)
        _ = try eventStore.insertGlobalIdentifier(globalIdentifier: "e2-2", nameOfEntity: entityName)
        let plain = try NSKeyedArchiver.archivedData(withRootObject: PlainCodingValue(number: 9), requiringSecureCoding: false)
        let predicate = try NSKeyedArchiver.archivedData(withRootObject: NSPredicate(format: "number > 3"), requiringSecureCoding: false)

        func insert(_ globalId: String, _ data: Data) -> [String: Any] {
            ["type": NSNumber(value: ObjectChangeType.insert.rawValue),
             "globalIdentifier": globalId,
             "properties": [["propertyName": unnamedAttributeName,
                             "type": NSNumber(value: PropertyChangeType.attribute.rawValue),
                             "value": e2Wire(data)]]]
        }
        let eventDict: [String: Any] = [
            "uniqueIdentifier": "evt-e2-keyed",
            "type": NSNumber(value: StoreModificationEventType.save.rawValue),
            "timestamp": "0",
            "globalCount": NSNumber(value: 0),
            "storeIdentifier": "peerE2",
            "revisionsByStoreIdentifier": ["peerE2": NSNumber(value: 1)],
            "changesByEntity": [entityName: [insert("e2-1", plain), insert("e2-2", predicate)]],
        ]
        let url = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent("e2keyed_\(ProcessInfo.processInfo.globallyUniqueString).json"))
        try JSONSerialization.data(withJSONObject: eventDict).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = JSONEventImport(eventStore: eventStore, importURLs: [url])
        importer.prepareToImport()
        let eventId = try #require(try importer.importFirstFile(at: url)?.id)

        let model = TestModelCache.model(for: Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!)!
        let attribute = model.entitiesByName[entityName]!.attributesByName[unnamedAttributeName]!
        let values = try eventStore.fetchObjectChanges(eventId: eventId).compactMap {
            $0.propertyChangeValues?.first { $0.propertyName == unnamedAttributeName }?.attributeValue(for: attribute, eventStore: eventStore)
        }
        #expect(values.count == 2)
        #expect(values.compactMap { ($0 as? PlainCodingValue)?.number } == [9])
        #expect(values.compactMap { ($0 as? NSPredicate)?.predicateFormat } == ["number > 3"])
    }
}

// MARK: - Through attach, sync and merge

extension SyncTests {
@Suite("Unnamed transformable sync", .serialized)
@MainActor
struct UnnamedTransformableSyncTests {

    let stack: SyncTestStack

    init() {
        stack = SyncTestStack()
    }

    private func insertContainer(named name: String, value: Any?, in ctx: NSManagedObjectContext) {
        nonisolated(unsafe) let value = value
        ctx.performAndWait {
            let obj = NSEntityDescription.insertNewObject(forEntityName: "TransformableContainer", into: ctx)
            obj.setValue(name, forKey: "name")
            obj.setValue(value, forKey: unnamedAttributeName)
            try! ctx.save()
        }
    }

    private func container(named name: String, in ctx: NSManagedObjectContext) -> NSManagedObject? {
        ctx.performAndWait {
            ctx.refreshAllObjects()
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "TransformableContainer")
            fetch.predicate = NSPredicate(format: "name == %@", name)
            return try? ctx.fetch(fetch).first
        }
    }

    /// The Studies shape: the store already holds an NSCoding-only value when the device
    /// first attaches, so the attach import captures it. Then a later save captures an update.
    @Test("Keyed archiver: attach import and save capture sync an NSCoding-only value")
    func keyedArchiverSyncsThroughAttachAndSave() async throws {
        stack.ensemble1.unnamedTransformableArchiving = .keyedArchiver
        stack.ensemble2.unnamedTransformableArchiving = .keyedArchiver

        insertContainer(named: "scheduled", value: PlainCodingValue(number: 5), in: stack.context1)
        try await stack.attachStores()
        try await stack.syncChanges()

        let merged = try #require(container(named: "scheduled", in: stack.context2))
        #expect((merged.value(forKey: unnamedAttributeName) as? PlainCodingValue)?.number == 5)

        stack.context1.performAndWait {
            let obj = try! stack.context1.fetch(NSFetchRequest<NSManagedObject>(entityName: "TransformableContainer")).first!
            obj.setValue(PlainCodingValue(number: 6), forKey: unnamedAttributeName)
            try! stack.context1.save()
        }
        try await stack.syncChanges()

        let updated = try #require(container(named: "scheduled", in: stack.context2))
        #expect((updated.value(forKey: unnamedAttributeName) as? PlainCodingValue)?.number == 6)
    }

    /// The failure shape: a refused change is LEFT OUT of the event, never stored as nil. A
    /// peer that has its own value keeps it, while the object's other changes still arrive.
    @Test("Default: a refused update leaves the peer's own value alone")
    func defaultRefusedUpdateKeepsPeerValue() async throws {
        insertContainer(named: "shared", value: nil, in: stack.context1)
        try await stack.attachStores()
        try await stack.syncChanges()

        let peerValue: NSArray = ["mine"]
        stack.context2.performAndWait {
            let obj = try! stack.context2.fetch(NSFetchRequest<NSManagedObject>(entityName: "TransformableContainer")).first!
            obj.setValue(peerValue, forKey: unnamedAttributeName)
            try! stack.context2.save()
        }
        try await stack.syncChanges()

        stack.context1.performAndWait {
            let obj = try! stack.context1.fetch(NSFetchRequest<NSManagedObject>(entityName: "TransformableContainer")).first!
            obj.setValue(PlainCodingValue(number: 8), forKey: unnamedAttributeName)
            obj.setValue(["changed"], forKey: "secureArrayOfStrings")
            try! stack.context1.save()
        }
        try await stack.syncChanges()

        let peer = try #require(container(named: "shared", in: stack.context2))
        #expect(peer.value(forKey: "secureArrayOfStrings") as? [String] == ["changed"], "the object's other change must sync")
        #expect(peer.value(forKey: unnamedAttributeName) as? NSArray == peerValue, "the refused change must not blank the peer's value")
    }

    /// A save whose only change is refused records no update row at all, rather than an
    /// update with an empty property list.
    @Test("Default: a save whose only change is refused stores no empty update row")
    func defaultRefusedOnlyChangeStoresNoUpdateRow() async throws {
        insertContainer(named: "lonely", value: nil, in: stack.context1)
        try await stack.attachStores()
        let eventStore = stack.ensemble1.eventStore
        let eventsBefore = Set(try eventStore.fetchCompleteEvents().map(\.id))

        stack.context1.performAndWait {
            let obj = try! stack.context1.fetch(NSFetchRequest<NSManagedObject>(entityName: "TransformableContainer")).first!
            obj.setValue(PlainCodingValue(number: 1), forKey: unnamedAttributeName)
            try! stack.context1.save()
        }

        let newEvents = try eventStore.fetchCompleteEvents().filter { !eventsBefore.contains($0.id) }
        #expect(newEvents.count == 1, "the save must still be recorded as an event")
        let changes = try newEvents.flatMap { try eventStore.fetchObjectChanges(eventId: $0.id) }
        #expect(changes.filter { $0.type == .update }.isEmpty, "no update row for a change that was left out")
    }

    /// Without the opt-in, attach no longer aborts: the refused attribute is left out and the
    /// rest of the object syncs.
    @Test("Default: attach with an NSCoding-only value succeeds and the rest of the object syncs")
    func defaultAttachDoesNotAbort() async throws {
        insertContainer(named: "scheduled", value: PlainCodingValue(number: 5), in: stack.context1)
        try await stack.attachStores()
        try await stack.syncChanges()

        let merged = try #require(container(named: "scheduled", in: stack.context2), "object must still sync")
        #expect(merged.value(forKey: unnamedAttributeName) == nil)
        // The source keeps its own value.
        let source = try #require(container(named: "scheduled", in: stack.context1))
        #expect((source.value(forKey: unnamedAttributeName) as? PlainCodingValue)?.number == 5)
    }
}
}
