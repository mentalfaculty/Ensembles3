import Testing
import Foundation
import CoreData
import CoreLocation
@_spi(Testing) import Ensembles

/// Reproduces the Ensembles 2 -> Ensembles 3 path for transformable attributes, which the
/// existing `TransformableAttributeRoundTripTests` does not cover (that suite is E3<->E3).
///
/// An E2 device serializes a transformable attribute by running its value transformer and
/// base64-encoding the resulting `Data` into the cloud JSON as `["data", "<base64>"]`
/// (see `CDEJSONEventExport.m` `JSONValueFromCoreDataValue:`). These tests construct that
/// exact wire value, run it through E3's real import entry point
/// (`JSONEventImport.coreDataValue(fromJSONValue:)`), and then through E3's real attribute
/// decode (`StoredPropertyChange.attributeValue(for:eventStore:)`), to confirm what survives.
@Suite("E2 -> E3 transformable import", .serialized)
struct E2ToE3TransformableImportTests {

    // A named secure transformer that allowlists CLLocation, mirroring the customer pattern.
    @objc(CDEE2ImportCLLocationTransformer)
    final class NamedCLLocationTransformer: NSSecureUnarchiveFromDataTransformer {
        static let name = NSValueTransformerName("CDEE2ImportCLLocationTransformer")
        override class var allowedTopLevelClasses: [AnyClass] { [CLLocation.self] }
        static func register() {
            ValueTransformer.setValueTransformer(NamedCLLocationTransformer(), forName: name)
        }
    }

    /// Builds a transformable `NSAttributeDescription`, optionally with a named transformer.
    private func transformableAttribute(named transformerName: String?) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = "location"
        attr.attributeType = .transformableAttributeType
        attr.attributeValueClassName = NSStringFromClass(CLLocation.self)
        if let transformerName {
            attr.valueTransformerName = transformerName
        }
        return attr
    }

    /// Produces the exact JSON value an E2 device writes to the cloud for a transformable
    /// attribute: `["data", base64]`, where the data is the archived value.
    private func e2WireValue(forArchived data: Data) -> [Any] {
        ["data", data.base64EncodedString()]
    }

    /// The full E2 -> E3 decode: E2 wire JSON -> coreDataValue -> StoredPropertyChange -> attributeValue.
    private func decodeThroughE3(e2Wire: [Any], attribute: NSAttributeDescription) -> Any? {
        let coreDataValue = JSONEventImport.coreDataValue(fromJSONValue: e2Wire)
        let storedValue = StoredValue.from(coreDataValue)
        let stored = StoredPropertyChange(
            type: PropertyChangeType.attribute.rawValue,
            propertyName: attribute.name,
            value: storedValue
        )
        return stored.attributeValue(for: attribute, eventStore: nil)
    }

    /// The cross-framework contract for a NAMED transformer: an E2 device archives a
    /// CLLocation through its named secure transformer, and an E3 device decodes it back.
    /// This is the case the customer (named CLLocationValueTransformer) actually exercises.
    @Test("Named transformer: E2-archived CLLocation decodes intact on E3")
    func namedTransformer_e2ArchivedCLLocation_decodesIntact() throws {
        NamedCLLocationTransformer.register()

        let location = CLLocation(latitude: 59.3293, longitude: 18.0686)
        // E2 stores a named secure transformer's value via reverseTransformedValue (archive).
        let archived = NamedCLLocationTransformer().reverseTransformedValue(location) as! Data

        let attribute = transformableAttribute(named: NamedCLLocationTransformer.name.rawValue)
        let result = decodeThroughE3(e2Wire: e2WireValue(forArchived: archived), attribute: attribute) as? CLLocation

        #expect(result != nil, "Named-transformer CLLocation lost on E2 -> E3 import")
        #expect(result?.coordinate.latitude == 59.3293)
        #expect(result?.coordinate.longitude == 18.0686)
    }

    /// Same as above but the E2 blob was produced with `requiringSecureCoding: false`
    /// (the legacy/insecure keyed archiver). Confirms the archive *format* is the same
    /// and a named secure transformer reads either blob (empirically verified separately).
    @Test("Named transformer: E2 insecure-archived CLLocation still decodes on E3")
    func namedTransformer_e2InsecureArchivedCLLocation_decodesIntact() throws {
        NamedCLLocationTransformer.register()

        let location = CLLocation(latitude: 59.3293, longitude: 18.0686)
        let archivedInsecure = try NSKeyedArchiver.archivedData(withRootObject: location, requiringSecureCoding: false)

        let attribute = transformableAttribute(named: NamedCLLocationTransformer.name.rawValue)
        let result = decodeThroughE3(e2Wire: e2WireValue(forArchived: archivedInsecure), attribute: attribute) as? CLLocation

        #expect(result != nil, "Named-transformer CLLocation (insecure-archived) lost on E2 -> E3 import")
        #expect(result?.coordinate.latitude == 59.3293)
    }

    /// The blank / default-transformer case: a transformable attribute with NO named transformer,
    /// holding a custom class (CLLocation).
    ///
    /// E3 previously ran the built-in `secureUnarchiveFromDataTransformerName` over the blob,
    /// which throws an uncaught `NSInvalidUnarchiveOperationException` for any class outside its
    /// plist allowlist (CLLocation is not in it), crashing the process. E2 wrapped the
    /// equivalent call in `@try/@catch`. The fix routes the decode through a catchable
    /// unarchiver that allowlists the attribute's declared value class, so the value now
    /// decodes intact rather than crashing.
    @Test("Blank transformer: custom-class blob decodes via declared value class, never crashes")
    func blankTransformer_customClassBlob_decodesIntact() throws {
        let location = CLLocation(latitude: 59.3293, longitude: 18.0686)
        let archived = try NSKeyedArchiver.archivedData(withRootObject: location, requiringSecureCoding: true)

        let attribute = transformableAttribute(named: nil)
        let result = decodeThroughE3(e2Wire: e2WireValue(forArchived: archived), attribute: attribute) as? CLLocation

        #expect(result != nil, "Blank-transformer CLLocation lost on E2 -> E3 import")
        #expect(result?.coordinate.latitude == 59.3293)
        #expect(result?.coordinate.longitude == 18.0686)
    }

    /// A genuinely corrupt blob on the blank-transformer path must degrade to nil, never crash.
    @Test("Blank transformer: corrupt blob degrades to nil, never crashes")
    func blankTransformer_corruptBlob_degradesToNil() throws {
        let garbage = Data([0x01, 0x02, 0x03, 0x04])
        let attribute = transformableAttribute(named: nil)
        let result = decodeThroughE3(e2Wire: e2WireValue(forArchived: garbage), attribute: attribute)
        #expect(result == nil, "Expected graceful nil for a corrupt transformable blob")
    }

    /// A blank-transformer attribute with NO declared value class (Core Data returns nil for
    /// `attributeValueClassName`) holding a non-plist custom class decodes to nil rather than
    /// crashing. This pins the intentional security tradeoff: without a declared class or named
    /// transformer to widen the allowlist, a foreign class is not deserialized. E2's insecure
    /// fallback would have decoded it; E3 deliberately does not.
    @Test("Blank transformer, no declared value class: foreign class degrades to nil")
    func blankTransformer_noDeclaredClass_degradesToNil() throws {
        let location = CLLocation(latitude: 59.3293, longitude: 18.0686)
        let archived = try NSKeyedArchiver.archivedData(withRootObject: location, requiringSecureCoding: true)

        let attribute = NSAttributeDescription()
        attribute.name = "location"
        attribute.attributeType = .transformableAttributeType
        // No attributeValueClassName, no valueTransformerName: allowlist is plist primitives only.
        #expect(attribute.attributeValueClassName == nil)

        let result = decodeThroughE3(e2Wire: e2WireValue(forArchived: archived), attribute: attribute)
        #expect(result == nil, "Foreign class with no declared value class must not be deserialized")
    }

    /// Confirms a standard `NSSecureUnarchiveFromDataTransformer` subclass (allowlist-only, no
    /// custom `transformedValue` body) round-trips through the helper unchanged. This is the
    /// supported subclass shape; custom `transformedValue` overrides on a secure subclass are
    /// intentionally not invoked (see `TransformableDecoding` doc comment).
    @Test("Named secure transformer: allowlist-only subclass round-trips unchanged")
    func namedTransformer_allowlistOnlySubclass_roundTrips() throws {
        NamedCLLocationTransformer.register()
        let location = CLLocation(latitude: 1.5, longitude: 2.5)
        let archived = try NSKeyedArchiver.archivedData(withRootObject: location, requiringSecureCoding: true)

        let attribute = transformableAttribute(named: NamedCLLocationTransformer.name.rawValue)
        let result = decodeThroughE3(e2Wire: e2WireValue(forArchived: archived), attribute: attribute) as? CLLocation

        #expect(result?.coordinate.latitude == 1.5)
        #expect(result?.coordinate.longitude == 2.5)
    }

    /// FULL end-to-end import: writes an Ensembles-2-format event JSON file (exactly the shape
    /// `CDEJSONEventExport.m` produces — an `insert` object change whose `properties` array
    /// carries the transformable value inline as `["data", base64]`), imports it through the
    /// real `JSONEventImport` into a real SQLite `EventStore`, then reads the persisted
    /// `StoredPropertyChange` back out and decodes it. This exercises the import -> persist ->
    /// read-back chain that the property-level tests above skip, which is where Ola's E2->E3
    /// CLLocation could be lost between cloud bytes and the merge context.
    @Test("E2-format event file imports and the transformable value survives persistence")
    func e2EventFile_transformableValueSurvivesImport() throws {
        NamedCLLocationTransformer.register()

        let location = CLLocation(latitude: 59.3293, longitude: 18.0686)
        let archived = NamedCLLocationTransformer().reverseTransformedValue(location) as! Data

        // Event JSON exactly as CDEJSONEventExport.m writes it: top-level event fields plus a
        // `changes` -> wait, E3's JSONEventImport reads object changes from the event dict.
        let setup = try TestEventStoreSetup(loadTestModel: true)
        let eventStore = setup.eventStore

        let globalIdString = "loc-1"
        let entityName = "TransformableContainer"
        // Pre-register the global identifier so the import resolves it (mirrors a known peer object).
        _ = try eventStore.insertGlobalIdentifier(globalIdentifier: globalIdString, nameOfEntity: entityName)

        let eventDict: [String: Any] = [
            "uniqueIdentifier": "evt-1",
            "type": NSNumber(value: StoreModificationEventType.save.rawValue),
            "timestamp": "0",
            "globalCount": NSNumber(value: 0),
            "storeIdentifier": "peerE2",
            "revisionsByStoreIdentifier": ["peerE2": NSNumber(value: 1)],
            // E2 writes object changes under `changesByEntity`, a dict keyed by entity name,
            // each value a flat array of change dicts (see CDEJSONEventExport.m line 96).
            "changesByEntity": [
                entityName: [
                    [
                        "type": NSNumber(value: ObjectChangeType.insert.rawValue),
                        "globalIdentifier": globalIdString,
                        "properties": [
                            [
                                "propertyName": "secureCustomTransformerString",
                                "type": NSNumber(value: PropertyChangeType.attribute.rawValue),
                                "value": ["data", archived.base64EncodedString()],
                            ]
                        ],
                    ]
                ]
            ],
        ]

        let tmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("e2event_\(ProcessInfo.processInfo.globallyUniqueString).json")
        try JSONSerialization.data(withJSONObject: eventDict).write(to: URL(fileURLWithPath: tmp))
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let importer = JSONEventImport(eventStore: eventStore, importURLs: [URL(fileURLWithPath: tmp)])
        importer.prepareToImport()
        let event = try importer.importFirstFile(at: URL(fileURLWithPath: tmp))
        let eventId = try #require(event?.id)

        // Read the persisted property change back from SQLite and decode it.
        let changes = try eventStore.fetchObjectChanges(eventId: eventId)
        let change = try #require(changes.first, "no object change imported from E2 event")
        let pc = try #require(change.propertyChangeValues?.first { $0.propertyName == "secureCustomTransformerString" },
                              "transformable property change missing after import")

        // Build the attribute the way the model defines it (CLLocation via named transformer).
        let attribute = transformableAttribute(named: NamedCLLocationTransformer.name.rawValue)
        let decoded = pc.attributeValue(for: attribute, eventStore: eventStore) as? CLLocation

        #expect(decoded != nil, "transformable CLLocation lost on full E2-format event import")
        #expect(decoded?.coordinate.latitude == 59.3293)
        #expect(decoded?.coordinate.longitude == 18.0686)
    }
}
