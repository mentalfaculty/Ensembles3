import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("JSONValueConversion")
struct JSONValueConversionTests {

    // MARK: - Export (Core Data → JSON)

    @Test("NSDecimalNumber exports as tagged string")
    func decimalExport() {
        let decimal = NSDecimalNumber(string: "3.14159265358979323846")
        let result = JSONEventExport.jsonValue(fromCoreDataValue: decimal)
        let array = result as? [Any]
        #expect(array?.count == 2)
        #expect(array?[0] as? String == "decimal")
        #expect(array?[1] as? String == "3.14159265358979323846")
    }

    @Test("Date exports as tagged milliseconds")
    func dateExport() {
        let date = Date(timeIntervalSince1970: 1000.5)
        let result = JSONEventExport.jsonValue(fromCoreDataValue: date)
        let array = result as? [Any]
        #expect(array?.count == 2)
        #expect(array?[0] as? String == "date")
        #expect(array?[1] as? Double == 1000500.0)
    }

    @Test("Data exports as tagged base64")
    func dataExport() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let result = JSONEventExport.jsonValue(fromCoreDataValue: data)
        let array = result as? [Any]
        #expect(array?.count == 2)
        #expect(array?[0] as? String == "data")
        #expect(array?[1] as? String == data.base64EncodedString())
    }

    @Test("UUID exports as tagged string")
    func uuidExport() {
        let uuid = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let result = JSONEventExport.jsonValue(fromCoreDataValue: uuid)
        let array = result as? [Any]
        #expect(array?.count == 2)
        #expect(array?[0] as? String == "uuid")
        #expect(array?[1] as? String == "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
    }

    @Test("URL exports as tagged string")
    func urlExport() {
        let url = URL(string: "https://example.com/path?q=1")!
        let result = JSONEventExport.jsonValue(fromCoreDataValue: url)
        let array = result as? [Any]
        #expect(array?.count == 2)
        #expect(array?[0] as? String == "url")
        #expect(array?[1] as? String == "https://example.com/path?q=1")
    }

    @Test("NaN exports as tagged string")
    func nanExport() {
        let result = JSONEventExport.jsonValue(fromCoreDataValue: kCFNumberNaN as NSNumber)
        let array = result as? [Any]
        #expect(array?[0] as? String == "number")
        #expect(array?[1] as? String == "nan")
    }

    @Test("Positive infinity exports as tagged string")
    func positiveInfinityExport() {
        let result = JSONEventExport.jsonValue(fromCoreDataValue: kCFNumberPositiveInfinity as NSNumber)
        let array = result as? [Any]
        #expect(array?[0] as? String == "number")
        #expect(array?[1] as? String == "+inf")
    }

    @Test("Negative infinity exports as tagged string")
    func negativeInfinityExport() {
        let result = JSONEventExport.jsonValue(fromCoreDataValue: kCFNumberNegativeInfinity as NSNumber)
        let array = result as? [Any]
        #expect(array?[0] as? String == "number")
        #expect(array?[1] as? String == "-inf")
    }

    @Test("Regular integer passes through unchanged")
    func integerExport() {
        let result = JSONEventExport.jsonValue(fromCoreDataValue: NSNumber(value: 42))
        #expect(result as? NSNumber == NSNumber(value: 42))
    }

    @Test("Regular double passes through unchanged")
    func doubleExport() {
        let result = JSONEventExport.jsonValue(fromCoreDataValue: NSNumber(value: 3.14))
        #expect(result as? NSNumber == NSNumber(value: 3.14))
    }

    @Test("String passes through unchanged")
    func stringExport() {
        let result = JSONEventExport.jsonValue(fromCoreDataValue: "hello")
        #expect(result as? String == "hello")
    }

    // MARK: - Import (JSON → Core Data)

    @Test("Tagged decimal imports as NSDecimalNumber")
    func decimalImport() {
        let json: [Any] = ["decimal", "3.14159265358979323846"]
        let result = JSONEventImport.coreDataValue(fromJSONValue: json)
        let decimal = result as? NSDecimalNumber
        #expect(decimal != nil)
        #expect(decimal?.stringValue == "3.14159265358979323846")
    }

    @Test("Tagged date imports as Date")
    func dateImport() {
        let json: [Any] = ["date", NSNumber(value: 1000500.0)]
        let result = JSONEventImport.coreDataValue(fromJSONValue: json)
        let date = result as? Date
        #expect(date != nil)
        #expect(date?.timeIntervalSince1970 == 1000.5)
    }

    @Test("Tagged data imports as Data")
    func dataImport() {
        let original = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let json: [Any] = ["data", original.base64EncodedString()]
        let result = JSONEventImport.coreDataValue(fromJSONValue: json)
        #expect(result as? Data == original)
    }

    @Test("Tagged UUID imports as UUID")
    func uuidImport() {
        let json: [Any] = ["uuid", "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"]
        let result = JSONEventImport.coreDataValue(fromJSONValue: json)
        #expect(result as? UUID == UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
    }

    @Test("Tagged URL imports as URL")
    func urlImport() {
        let json: [Any] = ["url", "https://example.com/path?q=1"]
        let result = JSONEventImport.coreDataValue(fromJSONValue: json)
        #expect(result as? URL == URL(string: "https://example.com/path?q=1"))
    }

    @Test("Tagged NaN imports as NaN")
    func nanImport() {
        let json: [Any] = ["number", "nan"]
        let result = JSONEventImport.coreDataValue(fromJSONValue: json)
        #expect(result as? NSNumber == kCFNumberNaN as NSNumber)
    }

    @Test("Tagged positive infinity imports correctly")
    func positiveInfinityImport() {
        let json: [Any] = ["number", "+inf"]
        let result = JSONEventImport.coreDataValue(fromJSONValue: json)
        #expect(result as? NSNumber == kCFNumberPositiveInfinity as NSNumber)
    }

    @Test("Tagged negative infinity imports correctly")
    func negativeInfinityImport() {
        let json: [Any] = ["number", "-inf"]
        let result = JSONEventImport.coreDataValue(fromJSONValue: json)
        #expect(result as? NSNumber == kCFNumberNegativeInfinity as NSNumber)
    }

    @Test("Stray NSDecimalNumber from JSONSerialization is coerced to NSNumber")
    func strayDecimalCoercion() {
        // JSONSerialization sometimes returns NSDecimalNumber for large numbers.
        // The import should coerce it to a regular NSNumber to avoid isEqual: bugs.
        let stray = NSDecimalNumber(string: "999999999999999")
        let result = JSONEventImport.coreDataValue(fromJSONValue: stray)
        #expect(result is NSNumber)
        #expect(!(result is NSDecimalNumber))
        #expect((result as? NSNumber)?.doubleValue == 999999999999999.0)
    }

    @Test("Untagged integer passes through")
    func integerImport() {
        let result = JSONEventImport.coreDataValue(fromJSONValue: NSNumber(value: 42))
        #expect(result as? NSNumber == NSNumber(value: 42))
    }

    @Test("Untagged string passes through")
    func stringImport() {
        let result = JSONEventImport.coreDataValue(fromJSONValue: "hello")
        #expect(result as? String == "hello")
    }

    // MARK: - Full Round-Trip Through JSONSerialization

    @Test("NSDecimalNumber survives JSON round-trip with full precision")
    func decimalRoundTrip() throws {
        let original = NSDecimalNumber(string: "3.14159265358979323846")
        let exported = JSONEventExport.jsonValue(fromCoreDataValue: original)

        // Serialize to JSON and back, simulating actual file I/O
        let jsonData = try JSONSerialization.data(withJSONObject: ["v": exported])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        let imported = JSONEventImport.coreDataValue(fromJSONValue: parsed["v"]!)
        let decimal = imported as? NSDecimalNumber
        #expect(decimal?.stringValue == "3.14159265358979323846")
    }

    @Test("Large NSDecimalNumber preserves precision through round-trip")
    func largeDecimalRoundTrip() throws {
        let original = NSDecimalNumber(string: "12345678901234567890.123456789")
        let exported = JSONEventExport.jsonValue(fromCoreDataValue: original)

        let jsonData = try JSONSerialization.data(withJSONObject: ["v": exported])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        let imported = JSONEventImport.coreDataValue(fromJSONValue: parsed["v"]!)
        let decimal = imported as? NSDecimalNumber
        #expect(decimal == original)
    }

    @Test("Date survives JSON round-trip")
    func dateRoundTrip() throws {
        let original = Date(timeIntervalSince1970: 1709312461.123)
        let exported = JSONEventExport.jsonValue(fromCoreDataValue: original)

        let jsonData = try JSONSerialization.data(withJSONObject: ["v": exported])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        let imported = JSONEventImport.coreDataValue(fromJSONValue: parsed["v"]!)
        let date = imported as? Date
        #expect(date != nil)
        #expect(abs(date!.timeIntervalSince1970 - original.timeIntervalSince1970) < 0.001)
    }

    @Test("Data survives JSON round-trip")
    func dataRoundTrip() throws {
        let original = Data((0..<256).map { UInt8($0) })
        let exported = JSONEventExport.jsonValue(fromCoreDataValue: original)

        let jsonData = try JSONSerialization.data(withJSONObject: ["v": exported])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        let imported = JSONEventImport.coreDataValue(fromJSONValue: parsed["v"]!)
        #expect(imported as? Data == original)
    }

    @Test("UUID survives JSON round-trip")
    func uuidRoundTrip() throws {
        let original = UUID()
        let exported = JSONEventExport.jsonValue(fromCoreDataValue: original)

        let jsonData = try JSONSerialization.data(withJSONObject: ["v": exported])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        let imported = JSONEventImport.coreDataValue(fromJSONValue: parsed["v"]!)
        #expect(imported as? UUID == original)
    }

    @Test("URL survives JSON round-trip")
    func urlRoundTrip() throws {
        let original = URL(string: "https://example.com/path?q=hello%20world&flag=true")!
        let exported = JSONEventExport.jsonValue(fromCoreDataValue: original)

        let jsonData = try JSONSerialization.data(withJSONObject: ["v": exported])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        let imported = JSONEventImport.coreDataValue(fromJSONValue: parsed["v"]!)
        #expect(imported as? URL == original)
    }

    @Test("NaN survives JSON round-trip")
    func nanRoundTrip() throws {
        let exported = JSONEventExport.jsonValue(fromCoreDataValue: kCFNumberNaN as NSNumber)

        let jsonData = try JSONSerialization.data(withJSONObject: ["v": exported])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        let imported = JSONEventImport.coreDataValue(fromJSONValue: parsed["v"]!)
        #expect(imported as? NSNumber == kCFNumberNaN as NSNumber)
    }

    @Test("Regular double survives JSON round-trip")
    func doubleRoundTrip() throws {
        let original = NSNumber(value: 3.14)
        let exported = JSONEventExport.jsonValue(fromCoreDataValue: original)

        let jsonData = try JSONSerialization.data(withJSONObject: ["v": exported])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        // After JSON round-trip, JSONSerialization may return NSDecimalNumber
        // The import coerces it back to NSNumber
        let imported = JSONEventImport.coreDataValue(fromJSONValue: parsed["v"]!)
        #expect((imported as? NSNumber)?.doubleValue == 3.14)
    }

    @Test("Regular integer survives JSON round-trip")
    func integerRoundTrip() throws {
        let original = NSNumber(value: 42)
        let exported = JSONEventExport.jsonValue(fromCoreDataValue: original)

        let jsonData = try JSONSerialization.data(withJSONObject: ["v": exported])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        let imported = JSONEventImport.coreDataValue(fromJSONValue: parsed["v"]!)
        #expect((imported as? NSNumber)?.intValue == 42)
    }

    @Test("Boolean survives JSON round-trip")
    func boolRoundTrip() throws {
        let original = NSNumber(value: true)
        let exported = JSONEventExport.jsonValue(fromCoreDataValue: original)

        let jsonData = try JSONSerialization.data(withJSONObject: ["v": exported])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        let imported = JSONEventImport.coreDataValue(fromJSONValue: parsed["v"]!)
        #expect((imported as? NSNumber)?.boolValue == true)
    }

    @Test("String survives JSON round-trip")
    func stringRoundTrip() throws {
        let original = "Hello 世界 🌍"
        let exported = JSONEventExport.jsonValue(fromCoreDataValue: original)

        let jsonData = try JSONSerialization.data(withJSONObject: ["v": exported])
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        let imported = JSONEventImport.coreDataValue(fromJSONValue: parsed["v"]!)
        #expect(imported as? String == original)
    }
}
