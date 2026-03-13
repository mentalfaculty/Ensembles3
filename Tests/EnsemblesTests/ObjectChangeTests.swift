import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("ObjectChange")
struct ObjectChangeTests {

    @Test("Object change type round-trip")
    func objectChangeType() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let gid = stack.addGlobalIdentifier("id1", entity: "EntityA")
            let event = stack.addModEvent(store: "store1", revision: 0)
            let change = stack.addObjectChange(type: .insert, globalIdentifier: gid, event: event)
            #expect(change.objectChangeType == .insert)
            change.objectChangeType = .update
            #expect(change.objectChangeType == .update)
            #expect(change.type == ObjectChangeType.update.rawValue)
        }
    }

    @Test("Object change type raw values")
    func objectChangeTypeRawValues() {
        #expect(ObjectChangeType.insert.rawValue == 100)
        #expect(ObjectChangeType.update.rawValue == 200)
        #expect(ObjectChangeType.delete.rawValue == 300)
    }

    @Test("Count of object changes in events")
    func countObjectChanges() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let gid1 = stack.addGlobalIdentifier("id1", entity: "EntityA")
            let gid2 = stack.addGlobalIdentifier("id2", entity: "EntityA")
            let event = stack.addModEvent(store: "store1", revision: 0)
            _ = stack.addObjectChange(type: .insert, globalIdentifier: gid1, event: event)
            _ = stack.addObjectChange(type: .insert, globalIdentifier: gid2, event: event)
            try! stack.context.save()

            let count = ObjectChange.countOfObjectChanges(in: [event])
            #expect(count == 2)
        }
    }

    @Test("Merge values from another change")
    func mergeValues() throws {
        PropertyChangeValue.registerTransformer()
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let gid = stack.addGlobalIdentifier("id1", entity: "EntityA")
            let event1 = stack.addModEvent(store: "store1", revision: 0)
            let change1 = stack.addObjectChange(type: .update, globalIdentifier: gid, event: event1)

            let attrValue1 = PropertyChangeValue(type: .attribute, propertyName: "name")
            attrValue1.value = "Alice" as NSString
            change1.propertyChangeValues = [attrValue1] as NSArray

            let event2 = stack.addModEvent(store: "store2", revision: 0)
            let change2 = stack.addObjectChange(type: .update, globalIdentifier: gid, event: event2)

            let attrValue2 = PropertyChangeValue(type: .attribute, propertyName: "name")
            attrValue2.value = "Bob" as NSString
            let attrValue3 = PropertyChangeValue(type: .attribute, propertyName: "age")
            attrValue3.value = NSNumber(value: 30)
            change2.propertyChangeValues = [attrValue2, attrValue3] as NSArray

            // Merge change2 into change1, treating change2 as subordinate
            change1.mergeValues(from: change2, treatChangeAsSubordinate: true)

            let merged = change1.propertyChangeValues as? [PropertyChangeValue] ?? []
            let nameValue = merged.first(where: { $0.propertyName == "name" })
            let ageValue = merged.first(where: { $0.propertyName == "age" })

            #expect(merged.count == 2)
            // When subordinate=true, existing value wins for attributes
            #expect(nameValue?.value as? String == "Alice")
            #expect(ageValue?.value as? NSNumber == NSNumber(value: 30))
        }
    }

    @Test("Merge values with subordinate false overrides")
    func mergeValuesSubordinateFalse() throws {
        PropertyChangeValue.registerTransformer()
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let change1 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: stack.context) as! ObjectChange
            let value1 = PropertyChangeValue(type: .attribute, propertyName: "a")
            value1.value = "A" as NSString
            change1.propertyChangeValues = [value1] as NSArray

            let change2 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: stack.context) as! ObjectChange
            let value2 = PropertyChangeValue(type: .attribute, propertyName: "a")
            value2.value = "AA" as NSString
            change2.propertyChangeValues = [value2] as NSArray

            // subordinate=true: existing value wins
            change1.mergeValues(from: change2, treatChangeAsSubordinate: true)
            var result = (change1.propertyChangeValues as? [PropertyChangeValue])?.last
            #expect(result?.value as? String == "A")

            // subordinate=false: incoming value wins
            change1.mergeValues(from: change2, treatChangeAsSubordinate: false)
            result = (change1.propertyChangeValues as? [PropertyChangeValue])?.last
            #expect(result?.value as? String == "AA")
        }
    }

    @Test("Merge values with differing property names")
    func mergeValuesWithDifferingPropertyNames() throws {
        PropertyChangeValue.registerTransformer()
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let change1 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: stack.context) as! ObjectChange
            let value1 = PropertyChangeValue(type: .attribute, propertyName: "a")
            value1.value = "A" as NSString
            change1.propertyChangeValues = [value1] as NSArray

            let change2 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: stack.context) as! ObjectChange
            change2.propertyChangeValues = [] as NSArray

            // Merge empty into non-empty: value persists
            change1.mergeValues(from: change2, treatChangeAsSubordinate: true)
            var result = (change1.propertyChangeValues as? [PropertyChangeValue])?.last
            #expect(result?.value as? String == "A")

            change1.mergeValues(from: change2, treatChangeAsSubordinate: false)
            result = (change1.propertyChangeValues as? [PropertyChangeValue])?.last
            #expect(result?.value as? String == "A")

            // Merge non-empty into empty: value transferred
            change1.propertyChangeValues = [] as NSArray
            change2.propertyChangeValues = [value1] as NSArray

            change1.mergeValues(from: change2, treatChangeAsSubordinate: true)
            result = (change1.propertyChangeValues as? [PropertyChangeValue])?.last
            #expect(result?.value as? String == "A")

            change1.mergeValues(from: change2, treatChangeAsSubordinate: false)
            result = (change1.propertyChangeValues as? [PropertyChangeValue])?.last
            #expect(result?.value as? String == "A")
        }
    }

    @Test("Required properties: missing nameOfEntity prevents save")
    func requiredPropertiesNameOfEntity() throws {
        PropertyChangeValue.registerTransformer()
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let gid = stack.addGlobalIdentifier("123", entity: "CDEObjectChange")
            let event = stack.addModEvent(store: "1234", revision: 0, timestamp: 123)
            let change = stack.addObjectChange(type: .update, globalIdentifier: gid, event: event)
            change.propertyChangeValues = [PropertyChangeValue(type: .attribute, propertyName: "a")] as NSArray

            change.nameOfEntity = nil
            #expect((try? stack.context.save()) == nil)
        }
    }

    @Test("Required properties: all valid saves successfully")
    func requiredPropertiesAllValid() throws {
        PropertyChangeValue.registerTransformer()
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let gid = stack.addGlobalIdentifier("123", entity: "CDEObjectChange")
            let event = stack.addModEvent(store: "1234", revision: 0, timestamp: 123)
            let change = stack.addObjectChange(type: .update, globalIdentifier: gid, event: event)
            change.propertyChangeValues = [PropertyChangeValue(type: .attribute, propertyName: "c")] as NSArray

            #expect((try? stack.context.save()) != nil)
        }
    }

    @Test("Property values saved and restored")
    func propertyValuesSavedAndRestored() throws {
        PropertyChangeValue.registerTransformer()
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let gid = stack.addGlobalIdentifier("123", entity: "Entity")
            let event = stack.addModEvent(store: "store1", revision: 0, timestamp: 123)
            let change = stack.addObjectChange(type: .update, globalIdentifier: gid, event: event)
            change.propertyChangeValues = [PropertyChangeValue(type: .attribute, propertyName: "val")] as NSArray

            try! stack.context.save()
            stack.context.refresh(change, mergeChanges: false)

            let values = change.propertyChangeValues as? [PropertyChangeValue] ?? []
            #expect(values.count == 1)
            #expect(values.first?.propertyName == "val")
        }
    }
}
