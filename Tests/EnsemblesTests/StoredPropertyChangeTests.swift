import Testing
import Foundation
@testable import Ensembles

@Suite("StoredPropertyChange")
struct StoredPropertyChangeTests {

    @Test("Encode and decode round-trip")
    func encodeDecodeRoundTrip() throws {
        let changes = [
            StoredPropertyChange(
                type: PropertyChangeType.attribute.rawValue,
                propertyName: "name",
                value: .string("Alice")
            ),
            StoredPropertyChange(
                type: PropertyChangeType.toOneRelationship.rawValue,
                propertyName: "parent",
                relatedIdentifier: "global-id-123"
            ),
            StoredPropertyChange(
                type: PropertyChangeType.toManyRelationship.rawValue,
                propertyName: "children",
                addedIdentifiers: ["gid-1", "gid-2"],
                removedIdentifiers: ["gid-3"]
            ),
            StoredPropertyChange(
                type: PropertyChangeType.orderedToManyRelationship.rawValue,
                propertyName: "orderedItems",
                addedIdentifiers: ["gid-4"],
                movedIdentifiersByIndex: ["0": "gid-4", "1": "gid-5"]
            ),
        ]

        let data = try StoredPropertyChange.encode(changes)
        let decoded = try StoredPropertyChange.decode(from: data)

        #expect(decoded.count == 4)
        #expect(decoded[0].propertyName == "name")
        #expect(decoded[0].value == .string("Alice"))
        #expect(decoded[1].relatedIdentifier == "global-id-123")
        #expect(decoded[2].addedIdentifiers == ["gid-1", "gid-2"])
        #expect(decoded[2].removedIdentifiers == ["gid-3"])
        #expect(decoded[3].movedIdentifiersByIndex?["0"] == "gid-4")
    }

    @Test("Nil fields are preserved")
    func nilFields() throws {
        let change = StoredPropertyChange(
            type: PropertyChangeType.attribute.rawValue,
            propertyName: "age",
            value: .null
        )

        let data = try StoredPropertyChange.encode([change])
        let decoded = try StoredPropertyChange.decode(from: data)

        #expect(decoded[0].value == .null)
        #expect(decoded[0].filename == nil)
        #expect(decoded[0].relatedIdentifier == nil)
    }

    @Test("Filename field round-trips")
    func filenameRoundTrip() throws {
        let change = StoredPropertyChange(
            type: PropertyChangeType.attribute.rawValue,
            propertyName: "bigData",
            filename: "abc123"
        )

        let data = try StoredPropertyChange.encode([change])
        let decoded = try StoredPropertyChange.decode(from: data)

        #expect(decoded[0].filename == "abc123")
        #expect(decoded[0].value == nil)
    }

    @Test("Empty array encodes and decodes")
    func emptyArray() throws {
        let data = try StoredPropertyChange.encode([])
        let decoded = try StoredPropertyChange.decode(from: data)
        #expect(decoded.isEmpty)
    }
}

@Suite("StoredValue")
struct StoredValueTests {

    @Test("String round-trip")
    func stringRoundTrip() throws {
        let value = StoredValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Int round-trip")
    func intRoundTrip() throws {
        let value = StoredValue.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Double round-trip")
    func doubleRoundTrip() throws {
        let value = StoredValue.double(3.14159)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Bool round-trip")
    func boolRoundTrip() throws {
        for v in [true, false] {
            let value = StoredValue.bool(v)
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test("Data round-trip")
    func dataRoundTrip() throws {
        let value = StoredValue.data(Data([0x01, 0x02, 0xFF]))
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Date round-trip")
    func dateRoundTrip() throws {
        let value = StoredValue.date(Date().timeIntervalSinceReferenceDate)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Decimal round-trip")
    func decimalRoundTrip() throws {
        let value = StoredValue.decimal("123456789.987654321")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("UUID round-trip")
    func uuidRoundTrip() throws {
        let value = StoredValue.uuid(UUID().uuidString)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("URL round-trip")
    func urlRoundTrip() throws {
        let value = StoredValue.url("https://example.com/path")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Null round-trip")
    func nullRoundTrip() throws {
        let value = StoredValue.null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Special numbers round-trip")
    func specialNumberRoundTrip() throws {
        for v in ["nan", "+inf", "-inf"] {
            let value = StoredValue.specialNumber(v)
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test("From nil returns null")
    func fromNilReturnsNull() {
        #expect(StoredValue.from(nil) == .null)
    }

    @Test("From NSNull returns null")
    func fromNSNullReturnsNull() {
        #expect(StoredValue.from(NSNull()) == .null)
    }

    @Test("From String")
    func fromString() {
        #expect(StoredValue.from("hello") == .string("hello"))
    }

    @Test("From NSNumber integer")
    func fromNSNumberInt() {
        let value = StoredValue.from(NSNumber(value: 42))
        #expect(value == .int(42))
    }

    @Test("From NSNumber double")
    func fromNSNumberDouble() {
        let value = StoredValue.from(NSNumber(value: 3.14))
        #expect(value == .double(3.14))
    }

    @Test("From NSNumber bool")
    func fromNSNumberBool() {
        let value = StoredValue.from(NSNumber(value: true))
        #expect(value == .bool(true))
    }

    @Test("From Date")
    func fromDate() {
        let date = Date()
        let value = StoredValue.from(date)
        #expect(value == .date(date.timeIntervalSinceReferenceDate))
    }

    @Test("From Data")
    func fromData() {
        let data = Data([1, 2, 3])
        #expect(StoredValue.from(data) == .data(data))
    }

    @Test("From UUID")
    func fromUUID() {
        let uuid = UUID()
        #expect(StoredValue.from(uuid) == .uuid(uuid.uuidString))
    }

    @Test("From URL")
    func fromURL() {
        let url = URL(string: "https://example.com")!
        #expect(StoredValue.from(url) == .url("https://example.com"))
    }

    @Test("From NSDecimalNumber")
    func fromDecimal() {
        let decimal = NSDecimalNumber(string: "123.456")
        #expect(StoredValue.from(decimal) == .decimal("123.456"))
    }

    @Test("From special floats")
    func fromSpecialFloats() {
        #expect(StoredValue.from(kCFNumberNaN as NSNumber) == .specialNumber("nan"))
        #expect(StoredValue.from(kCFNumberPositiveInfinity as NSNumber) == .specialNumber("+inf"))
        #expect(StoredValue.from(kCFNumberNegativeInfinity as NSNumber) == .specialNumber("-inf"))
    }

    @Test("toFoundationValue round-trip for string")
    func toFoundationString() {
        let result = StoredValue.string("hello").toFoundationValue() as? String
        #expect(result == "hello")
    }

    @Test("toFoundationValue round-trip for int")
    func toFoundationInt() {
        let result = StoredValue.int(42).toFoundationValue() as? NSNumber
        #expect(result?.int64Value == 42)
    }

    @Test("toFoundationValue round-trip for date")
    func toFoundationDate() {
        let interval = Date().timeIntervalSinceReferenceDate
        let result = StoredValue.date(interval).toFoundationValue() as? Date
        #expect(result?.timeIntervalSinceReferenceDate == interval)
    }

    @Test("toFoundationValue null returns nil")
    func toFoundationNull() {
        #expect(StoredValue.null.toFoundationValue() == nil)
    }

    @Test("toFoundationValue special number nan")
    func toFoundationNaN() {
        let result = StoredValue.specialNumber("nan").toFoundationValue() as? NSNumber
        #expect(result == kCFNumberNaN as NSNumber)
    }

    @Test("toFoundationValue decimal")
    func toFoundationDecimal() {
        let result = StoredValue.decimal("123.456").toFoundationValue() as? NSDecimalNumber
        #expect(result == NSDecimalNumber(string: "123.456"))
    }

    @Test("toFoundationValue UUID")
    func toFoundationUUID() {
        let uuidString = UUID().uuidString
        let result = StoredValue.uuid(uuidString).toFoundationValue() as? UUID
        #expect(result?.uuidString == uuidString)
    }

    // MARK: - Precision Tests

    @Test("Date precision preserved through JSON round-trip")
    func datePrecisionPreserved() throws {
        // timeIntervalSinceReferenceDate values have high precision
        let preciseValues: [Double] = [
            793742399.123456789,      // typical timestamp
            0.000000001,              // very small
            99999999999.999999,       // very large
            12345.0,                  // exact integer
            -86400.5,                 // negative
            1000.1 + 1000.2,         // floating point arithmetic result
        ]

        for original in preciseValues {
            let value = StoredValue.date(original)
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(StoredValue.self, from: data)

            guard case .date(let decodedInterval) = decoded else {
                Issue.record("Expected .date, got \(decoded)")
                continue
            }
            #expect(decodedInterval == original, "Date precision lost for \(original): got \(decodedInterval)")
        }
    }

    @Test("Date encoded as string in JSON (not bare number)")
    func dateEncodedAsString() throws {
        let value = StoredValue.date(793742399.123456789)
        let data = try JSONEncoder().encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["type"] as? String == "date")
        // Value should be a string, not a number
        #expect(json?["value"] is String, "Date value should be encoded as String, got \(type(of: json?["value"] as Any))")
    }

    @Test("Date decodes from legacy numeric format")
    func dateDecodesFromLegacyNumeric() throws {
        // Older data may have encoded dates as bare doubles
        let json = #"{"type":"date","value":12345.5}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
        #expect(decoded == .date(12345.5))
    }

    @Test("Double precision edge cases")
    func doublePrecisionEdgeCases() throws {
        let edgeCases: [Double] = [
            .leastNormalMagnitude,
            .leastNonzeroMagnitude,
            .greatestFiniteMagnitude,
            .pi,
            .ulpOfOne,
            1.0 / 3.0,               // repeating decimal
            0.1 + 0.2,               // classic floating point
        ]

        for original in edgeCases {
            let value = StoredValue.double(original)
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
            #expect(decoded == .double(original), "Double precision lost for \(original)")
        }
    }

    @Test("Decimal preserves arbitrary precision")
    func decimalPreservesArbitraryPrecision() throws {
        let preciseDecimals = [
            "123456789012345678901234567890.123456789012345678901234567890",
            "0.000000000000000000000000000001",
            "-99999999999999999999.99999999999999999999",
            "3.14159265358979323846264338327950288",
        ]

        for original in preciseDecimals {
            let value = StoredValue.decimal(original)
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
            #expect(decoded == .decimal(original), "Decimal precision lost for \(original)")
        }
    }

    @Test("Decimal round-trip through Foundation preserves value")
    func decimalFoundationRoundTrip() {
        let original = "123456789.987654321"
        let stored = StoredValue.decimal(original)
        let foundation = stored.toFoundationValue() as! NSDecimalNumber
        let backToStored = StoredValue.from(foundation)
        #expect(backToStored == .decimal(original))
    }

    @Test("Special numbers round-trip through Foundation and back")
    func specialNumbersFoundationRoundTrip() throws {
        let cases: [(StoredValue, NSNumber)] = [
            (.specialNumber("nan"), kCFNumberNaN as NSNumber),
            (.specialNumber("+inf"), kCFNumberPositiveInfinity as NSNumber),
            (.specialNumber("-inf"), kCFNumberNegativeInfinity as NSNumber),
        ]

        for (stored, expectedNS) in cases {
            // StoredValue → Foundation
            let foundation = stored.toFoundationValue() as? NSNumber
            #expect(foundation == expectedNS)

            // Foundation → StoredValue
            let backToStored = StoredValue.from(foundation as Any)
            #expect(backToStored == stored)

            // JSON round-trip
            let data = try JSONEncoder().encode(stored)
            let decoded = try JSONDecoder().decode(StoredValue.self, from: data)
            #expect(decoded == stored)
        }
    }

    @Test("Large Data blob round-trip")
    func largeDataBlobRoundTrip() throws {
        // 10KB of random-ish data
        var bytes = [UInt8](repeating: 0, count: 10_000)
        for i in 0..<bytes.count { bytes[i] = UInt8(i % 256) }
        let original = Data(bytes)

        let value = StoredValue.data(original)
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(StoredValue.self, from: encoded)

        guard case .data(let decodedData) = decoded else {
            Issue.record("Expected .data")
            return
        }
        #expect(decodedData == original)
    }

    @Test("Full encode/decode cycle preserves all StoredValue types together")
    func fullCycleAllTypes() throws {
        let changes = [
            StoredPropertyChange(type: 0, propertyName: "str", value: .string("hello")),
            StoredPropertyChange(type: 0, propertyName: "num", value: .int(Int64.max)),
            StoredPropertyChange(type: 0, propertyName: "dbl", value: .double(Double.pi)),
            StoredPropertyChange(type: 0, propertyName: "flag", value: .bool(true)),
            StoredPropertyChange(type: 0, propertyName: "blob", value: .data(Data([0xDE, 0xAD]))),
            StoredPropertyChange(type: 0, propertyName: "when", value: .date(793742399.123456789)),
            StoredPropertyChange(type: 0, propertyName: "money", value: .decimal("99.99")),
            StoredPropertyChange(type: 0, propertyName: "uid", value: .uuid("550E8400-E29B-41D4-A716-446655440000")),
            StoredPropertyChange(type: 0, propertyName: "link", value: .url("https://example.com")),
            StoredPropertyChange(type: 0, propertyName: "empty", value: .null),
            StoredPropertyChange(type: 0, propertyName: "nan", value: .specialNumber("nan")),
            StoredPropertyChange(type: 0, propertyName: "pinf", value: .specialNumber("+inf")),
            StoredPropertyChange(type: 0, propertyName: "ninf", value: .specialNumber("-inf")),
        ]

        let data = try StoredPropertyChange.encode(changes)
        let decoded = try StoredPropertyChange.decode(from: data)

        #expect(decoded.count == changes.count)
        for (original, round) in zip(changes, decoded) {
            #expect(original == round, "Mismatch for \(original.propertyName)")
        }
    }
}
