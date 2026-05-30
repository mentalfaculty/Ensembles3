import Testing
import Foundation
import CoreData
import CoreLocation
@_spi(Testing) import Ensembles

/// Regression for the Ensembles 2 → Ensembles 3 transformable-value drop.
///
/// E2's Objective-C exporter base64-encodes `Data`/transformable blobs in 64-column lines
/// joined by CRLF. E3's JSON import decoded the `"data"` tag with strict
/// `Data(base64Encoded:)`, which rejects embedded CR/LF and returns nil — silently dropping the
/// value before any transformer runs. Symptom (Ola Nilsson, CLLocation): the location arrives
/// nil on the E3 device while plain-string siblings (header, uniqueIdentifier) arrive fine,
/// because only the transformable is encoded as `["data", base64]`.
///
/// The fix decodes with `.ignoreUnknownCharacters`, tolerating E2's line wrapping.
@Suite("E2 CRLF-wrapped base64 import", .serialized)
struct RealBlobDecodeTests {

    /// Wraps base64 in 64-column lines joined by CRLF, exactly as E2's CDENewBase64Encode does.
    private func e2Wrap(_ base64: String) -> String {
        var out = ""
        var i = base64.startIndex
        while i < base64.endIndex {
            let end = base64.index(i, offsetBy: 64, limitedBy: base64.endIndex) ?? base64.endIndex
            out += base64[i..<end]
            i = end
            if i < base64.endIndex { out += "\r\n" }
        }
        return out
    }

    @Test("CRLF-wrapped data tag imports to the original bytes (was nil)")
    func crlfWrappedData_importsCorrectly() throws {
        let original = try NSKeyedArchiver.archivedData(
            withRootObject: CLLocation(latitude: 43.7384, longitude: 7.4246),
            requiringSecureCoding: true)
        // A CLLocation archive is ~2KB, so its base64 is well over 64 chars → multiple CRLF lines.
        let wrapped = e2Wrap(original.base64EncodedString())
        #expect(wrapped.contains("\r\n"), "fixture must actually be line-wrapped")

        let json: [Any] = ["data", wrapped]
        let result = JSONEventImport.coreDataValue(fromJSONValue: json) as? Data

        #expect(result == original, "CRLF-wrapped E2 base64 must decode to the original bytes")
    }

    @Test("CRLF-wrapped CLLocation survives import + transformer decode end to end")
    func crlfWrappedCLLocation_endToEnd() throws {
        let monaco = CLLocation(latitude: 43.7384, longitude: 7.4246)
        let archived = try NSKeyedArchiver.archivedData(withRootObject: monaco, requiringSecureCoding: true)
        let wrapped = e2Wrap(archived.base64EncodedString())

        // Import the E2 wire value, then decode through the transformable attribute path.
        let imported = JSONEventImport.coreDataValue(fromJSONValue: ["data", wrapped])
        let storedValue = StoredValue.from(imported)
        let stored = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue,
                                          propertyName: "location", value: storedValue)

        let attr = NSAttributeDescription()
        attr.name = "location"
        attr.attributeType = .transformableAttributeType
        attr.attributeValueClassName = NSStringFromClass(CLLocation.self)
        // Blank transformer (declared-class fallback) so the test is independent of registration.
        let result = stored.attributeValue(for: attr, eventStore: nil) as? CLLocation

        #expect(result != nil, "CLLocation lost across CRLF-wrapped E2 import")
        #expect(result?.coordinate.latitude == 43.7384)
        #expect(result?.coordinate.longitude == 7.4246)
    }

    @Test("Unwrapped data tag still imports correctly (no regression)")
    func unwrappedData_stillWorks() {
        let original = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02])
        let json: [Any] = ["data", original.base64EncodedString()]
        let result = JSONEventImport.coreDataValue(fromJSONValue: json) as? Data
        #expect(result == original)
    }
}
