import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("PropertyChangeValue")
struct PropertyChangeValueTests {

    @Test("Basic init with type and property name")
    func basicInit() {
        let value = PropertyChangeValue(type: .attribute, propertyName: "name")
        #expect(value.type == .attribute)
        #expect(value.propertyName == "name")
        #expect(value.value == nil)
    }

    @Test("Merging to-many relationships")
    func mergingToManyRelationship() {
        let value1 = PropertyChangeValue(type: .toManyRelationship, propertyName: "property")
        value1.addedIdentifiers = Set(["11" as AnyHashable, "12" as AnyHashable])
        value1.removedIdentifiers = Set()

        let value2 = PropertyChangeValue(type: .toManyRelationship, propertyName: "property")
        value2.addedIdentifiers = Set(["11" as AnyHashable])
        value2.removedIdentifiers = Set(["12" as AnyHashable])

        value2.mergeToManyRelationship(from: value1, treatValueAsSubordinate: true)

        let expectedAdded: Set<AnyHashable> = Set(["11" as AnyHashable])
        #expect(value2.addedIdentifiers == expectedAdded)
        #expect(value2.removedIdentifiers == Set())
    }

    @Test("Merging ordered to-many relationships")
    func mergingOrderedToManyRelationship() {
        let value1 = PropertyChangeValue(type: .orderedToManyRelationship, propertyName: "property")
        value1.addedIdentifiers = Set(["11" as AnyHashable, "12" as AnyHashable, "13" as AnyHashable])
        value1.removedIdentifiers = Set()
        value1.movedIdentifiersByIndex = [
            0: "12",
            1: "13",
            2: "11"
        ]

        let value2 = PropertyChangeValue(type: .orderedToManyRelationship, propertyName: "property")
        value2.addedIdentifiers = Set(["11" as AnyHashable])
        value2.removedIdentifiers = Set(["12" as AnyHashable])
        value2.movedIdentifiersByIndex = [0: "11"]

        value2.mergeToManyRelationship(from: value1, treatValueAsSubordinate: true)

        let expectedAdded: Set<AnyHashable> = Set(["11" as AnyHashable, "13" as AnyHashable])
        #expect(value2.addedIdentifiers == expectedAdded)
        #expect(value2.removedIdentifiers == Set())

        let actualMoved = value2.movedIdentifiersByIndex
        #expect(actualMoved != nil)
        #expect(actualMoved?.count == 2)
        #expect(actualMoved?[0] as? String == "11")
        #expect(actualMoved?[1] as? String == "13")
    }

    @Test("NSCoding round-trip")
    func codingRoundTrip() throws {
        let value = PropertyChangeValue(type: .toManyRelationship, propertyName: "children")
        value.addedIdentifiers = Set(["id1" as AnyHashable, "id2" as AnyHashable])
        value.removedIdentifiers = Set(["id3" as AnyHashable])

        let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
        let allowedClasses: [AnyClass] = [
            PropertyChangeValue.self, NSString.self, NSNumber.self, NSSet.self, NSDictionary.self, NSArray.self
        ]
        let restored = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data) as? PropertyChangeValue
        #expect(restored != nil)
        #expect(restored?.type == .toManyRelationship)
        #expect(restored?.propertyName == "children")
        #expect(restored?.addedIdentifiers?.count == 2)
        #expect(restored?.removedIdentifiers?.count == 1)
    }

    @Test("NSCopying produces independent copy")
    func copying() {
        let original = PropertyChangeValue(type: .attribute, propertyName: "name")
        original.value = "hello" as NSString
        let copy = original.copy() as? PropertyChangeValue
        #expect(copy != nil)
        #expect(copy?.type == .attribute)
        #expect(copy?.propertyName == "name")
        #expect(copy?.value as? String == "hello")
    }

    @Test("Property change type raw values")
    func propertyChangeTypeRawValues() {
        #expect(PropertyChangeType.attribute.rawValue == 0)
        #expect(PropertyChangeType.toOneRelationship.rawValue == 1)
        #expect(PropertyChangeType.toManyRelationship.rawValue == 2)
        #expect(PropertyChangeType.orderedToManyRelationship.rawValue == 3)
    }
}
