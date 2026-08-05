import Testing
import Foundation
import CoreData
import CoreLocation
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

// MARK: - Test transformers (mirror what the test model references)

/// `NSSecureUnarchiveFromDataTransformer` subclass for `String`/`Array`/`Dictionary` values.
@objc(CDESecureTestTransformer)
final class CDESecureTestTransformer: NSSecureUnarchiveFromDataTransformer {
    static let name = NSValueTransformerName("CDESecureTestTransformer")
    override class var allowedTopLevelClasses: [AnyClass] {
        [NSString.self, NSArray.self, NSDictionary.self]
    }
    static func register() {
        ValueTransformer.setValueTransformer(CDESecureTestTransformer(), forName: name)
    }
}

/// Plain `ValueTransformer` subclass that encodes a `String` to UTF-8 `Data` and back.
@objc(CDEInsecureTestTransformer)
final class CDEInsecureTestTransformer: ValueTransformer {
    static let name = NSValueTransformerName("CDEInsecureTestTransformer")
    override class func transformedValueClass() -> AnyClass { NSData.self }
    override class func allowsReverseTransformation() -> Bool { true }
    override func transformedValue(_ value: Any?) -> Any? {
        guard let s = value as? String else { return nil }
        return s.data(using: .utf8)
    }
    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let d = value as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func register() {
        ValueTransformer.setValueTransformer(CDEInsecureTestTransformer(), forName: name)
    }
}

/// `NSSecureUnarchiveFromDataTransformer` subclass for `CLLocation`, mirroring the pattern
/// customers use for location-bearing attributes.
@objc(CDETestCLLocationTransformer)
final class CDETestCLLocationTransformer: NSSecureUnarchiveFromDataTransformer {
    static let name = NSValueTransformerName("CDETestCLLocationTransformer")
    override class var allowedTopLevelClasses: [AnyClass] { [CLLocation.self] }
    static func register() {
        ValueTransformer.setValueTransformer(CDETestCLLocationTransformer(), forName: name)
    }
}

// MARK: - Test helpers

private func makeContext() -> NSManagedObjectContext {
    let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
    let model = NSManagedObjectModel(contentsOf: modelURL)!
    let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
    try! psc.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
    let ctx = NSManagedObjectContext(.mainQueue)
    ctx.persistentStoreCoordinator = psc
    return ctx
}

private func insertTransformableContainer(in ctx: NSManagedObjectContext) -> NSManagedObject {
    let obj = NSEntityDescription.insertNewObject(forEntityName: "TransformableContainer", into: ctx)
    try! ctx.obtainPermanentIDs(for: [obj])
    return obj
}

// MARK: - Tests

@Suite("Transformable attribute round-trip", .serialized)
final class TransformableAttributeRoundTripTests {

    init() {
        CDESecureTestTransformer.register()
        CDEInsecureTestTransformer.register()
        CDETestCLLocationTransformer.register()
    }

    /// Mirrors a one-peer-write/one-peer-read flow at the property-change level:
    ///   1. Sender: build PropertyChangeValue (storeValues: true) and convert to StoredPropertyChange
    ///   2. JSON encode/decode (what the SQLite event store does internally)
    ///   3. Receiver: stored.attributeValue(for: attribute, eventStore:)
    private func roundTrip(propertyName: String, value: Any?, in ctx: NSManagedObjectContext) -> Any? {
        let obj = insertTransformableContainer(in: ctx)
        obj.setValue(value, forKey: propertyName)
        try! ctx.save()

        let desc = obj.entity.propertiesByName[propertyName]!
        let pcv = PropertyChangeValue(
            object: obj,
            propertyDescription: desc,
            eventStore: nil,
            isPreSave: false,
            storeValues: true
        )

        let stored = pcv.toStoredPropertyChange()
        let json = try! StoredPropertyChange.encode([stored])
        let restored = try! StoredPropertyChange.decode(from: json)[0]

        let attribute = obj.entity.attributesByName[propertyName]!
        return restored.attributeValue(for: attribute, eventStore: nil)
    }

    @Test("Round-trip with named NSSecureUnarchiveFromDataTransformer subclass preserves String value")
    func secureNamedTransformer_string() {
        let ctx = makeContext()
        let restored = roundTrip(propertyName: "secureCustomTransformerString", value: "hello world" as NSString, in: ctx)
        #expect(restored as? String == "hello world")
    }

    @Test("Round-trip with named NSSecureUnarchiveFromDataTransformer subclass preserves Array value")
    func secureNamedTransformer_array() {
        let ctx = makeContext()
        let value: NSArray = ["a", "b", "c"]
        let restored = roundTrip(propertyName: "secureCustomTransformerString", value: value, in: ctx)
        #expect((restored as? NSArray) == value)
    }

    @Test("Round-trip with plain ValueTransformer subclass preserves String value")
    func insecureNamedTransformer_string() {
        let ctx = makeContext()
        let restored = roundTrip(propertyName: "insecureCustomTransformerString", value: "the quick brown fox", in: ctx)
        #expect(restored as? String == "the quick brown fox")
    }

    @Test("Round-trip with built-in NSSecureUnarchiveFromDataTransformer preserves Array value")
    func builtinSecureTransformer_array() {
        let ctx = makeContext()
        let value: NSArray = ["one", "two", "three"]
        let restored = roundTrip(propertyName: "secureArrayOfStrings", value: value, in: ctx)
        #expect((restored as? NSArray) == value)
    }

    /// Property-change-level round-trip of a CLLocation through an
    /// NSSecureUnarchiveFromDataTransformer subclass, matching the pattern customers
    /// use for location-bearing attributes.
    @Test("Round-trip with CLLocation via NSSecureUnarchiveFromDataTransformer subclass preserves value")
    func clLocationRoundTrip() throws {
        // Build a model where `secureCustomTransformerString` is rewired to a CLLocation transformer.
        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        let model = NSManagedObjectModel(contentsOf: modelURL)!
        let attribute = model.entitiesByName["TransformableContainer"]!.attributesByName["secureCustomTransformerString"]!
        attribute.valueTransformerName = CDETestCLLocationTransformer.name.rawValue
        attribute.attributeValueClassName = NSStringFromClass(CLLocation.self)

        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        let ctx = NSManagedObjectContext(.mainQueue)
        ctx.persistentStoreCoordinator = psc

        let location = CLLocation(latitude: 59.3293, longitude: 18.0686)

        let obj = NSEntityDescription.insertNewObject(forEntityName: "TransformableContainer", into: ctx)
        try ctx.obtainPermanentIDs(for: [obj])
        obj.setValue(location, forKey: "secureCustomTransformerString")
        try ctx.save()

        let desc = obj.entity.propertiesByName["secureCustomTransformerString"]!
        let pcv = PropertyChangeValue(object: obj, propertyDescription: desc, eventStore: nil, isPreSave: false, storeValues: true)
        let stored = pcv.toStoredPropertyChange()
        let json = try StoredPropertyChange.encode([stored])
        let restored = try StoredPropertyChange.decode(from: json)[0]
        let result = restored.attributeValue(for: attribute, eventStore: nil) as? CLLocation

        #expect(result != nil)
        #expect(result?.coordinate.latitude == 59.3293)
        #expect(result?.coordinate.longitude == 18.0686)
    }

    /// End-to-end two-peer sync of a transformable CLLocation attribute over `LocalCloudFileSystem`.
    /// If this passes, the framework's transformable-attribute path is intact end-to-end.
    @MainActor
    @Test("End-to-end sync of CLLocation via custom transformer between two peers")
    func endToEndCLLocationSync() async throws {
        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        let model = NSManagedObjectModel(contentsOf: modelURL)!
        let attribute = model.entitiesByName["TransformableContainer"]!.attributesByName["secureCustomTransformerString"]!
        attribute.valueTransformerName = CDETestCLLocationTransformer.name.rawValue
        attribute.attributeValueClassName = NSStringFromClass(CLLocation.self)

        let rootDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("CLLocSync_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: rootDir) }

        let cloudDir = (rootDir as NSString).appendingPathComponent("cloudfiles")
        try FileManager.default.createDirectory(atPath: cloudDir, withIntermediateDirectories: true)

        // Peer 1
        let storeURL1 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store1.sql"))
        let psc1 = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc1.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL1, options: nil)
        let ctx1 = NSManagedObjectContext(.mainQueue)
        ctx1.persistentStoreCoordinator = psc1
        let cloudFS1 = LocalCloudFileSystem(rootDirectory: cloudDir)
        let ens1 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.cllocsync",
            persistentStoreURL: storeURL1,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: model,
            cloudFileSystem: cloudFS1,
            localDataRootDirectoryURL: URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("eventData1"))
        )!

        // Peer 2
        let storeURL2 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store2.sql"))
        let psc2 = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc2.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL2, options: nil)
        let ctx2 = NSManagedObjectContext(.mainQueue)
        ctx2.persistentStoreCoordinator = psc2
        let cloudFS2 = LocalCloudFileSystem(rootDirectory: cloudDir)
        let ens2 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.cllocsync",
            persistentStoreURL: storeURL2,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: model,
            cloudFileSystem: cloudFS2,
            localDataRootDirectoryURL: URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("eventData2"))
        )!

        final class MergeDelegate: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {
            let ctx1: NSManagedObjectContext
            let ctx2: NSManagedObjectContext
            unowned var ens1: CoreDataEnsemble!
            unowned var ens2: CoreDataEnsemble!
            init(ctx1: NSManagedObjectContext, ctx2: NSManagedObjectContext) {
                self.ctx1 = ctx1; self.ctx2 = ctx2
            }
            func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didSaveMergeChangesWith notification: Notification) {
                nonisolated(unsafe) let n = notification
                if ensemble === ens1 { ctx1.performAndWait { ctx1.mergeChanges(fromContextDidSave: n) } }
                else if ensemble === ens2 { ctx2.performAndWait { ctx2.mergeChanges(fromContextDidSave: n) } }
            }
            func coreDataEnsemble(_ ensemble: CoreDataEnsemble, globalIdentifiersForManagedObjects objects: [NSManagedObject]) -> [String] {
                objects.map { obj in
                    if let name = obj.value(forKey: "name") as? String, !name.isEmpty { return name }
                    // Test-only identifier: object URIs never match across devices and are not valid production global identifiers. See "Global Identifiers" in the Manual.
                    return obj.objectID.uriRepresentation().absoluteString
                }
            }
            func coreDataEnsemble(_ ensemble: CoreDataEnsemble, shouldSaveMergedChangesIn savingContext: NSManagedObjectContext, reparationContext: NSManagedObjectContext) -> Bool { true }
        }

        let delegate = MergeDelegate(ctx1: ctx1, ctx2: ctx2)
        delegate.ens1 = ens1
        delegate.ens2 = ens2
        ens1.delegate = delegate
        ens2.delegate = delegate

        defer {
            ens1.dismantle()
            ens2.dismantle()
            ctx1.performAndWait { ctx1.reset(); if let s = psc1.persistentStores.first { try? psc1.remove(s) } }
            ctx2.performAndWait { ctx2.reset(); if let s = psc2.persistentStores.first { try? psc2.remove(s) } }
        }

        try await ens1.attachPersistentStore()
        try await ens2.attachPersistentStore()

        let location = CLLocation(latitude: 59.3293, longitude: 18.0686)
        ctx1.performAndWait {
            let obj = NSEntityDescription.insertNewObject(forEntityName: "TransformableContainer", into: ctx1)
            obj.setValue("stockholm", forKey: "name")
            obj.setValue(location, forKey: "secureCustomTransformerString")
            try! ctx1.save()
        }

        try await ens1.sync()
        try await ens2.sync()
        try await ens1.sync()
        try await ens2.sync()

        let result: CLLocation? = ctx2.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "TransformableContainer")
            let objs = (try? ctx2.fetch(fetch)) ?? []
            return objs.first { ($0.value(forKey: "name") as? String) == "stockholm" }?
                .value(forKey: "secureCustomTransformerString") as? CLLocation
        }

        #expect(result != nil, "Peer 2 lost the CLLocation value")
        #expect(result?.coordinate.latitude == 59.3293)
        #expect(result?.coordinate.longitude == 18.0686)
    }
}
