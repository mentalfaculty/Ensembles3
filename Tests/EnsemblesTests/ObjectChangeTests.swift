import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("ObjectChange")
struct ObjectChangeTests {

    @Test("Object change type is set correctly at insert")
    func objectChangeType() throws {
        let setup = try TestEventStoreSetup()
        let gid = try setup.addGlobalIdentifier("id1", entity: "EntityA")
        let event = try setup.addModEvent(store: "store1", revision: 0)

        let insertChange = try setup.addObjectChange(type: .insert, globalIdentifier: gid, event: event)
        #expect(insertChange.type == .insert)

        let gid2 = try setup.addGlobalIdentifier("id2", entity: "EntityA")
        let updateChange = try setup.addObjectChange(type: .update, globalIdentifier: gid2, event: event)
        #expect(updateChange.type == .update)

        let gid3 = try setup.addGlobalIdentifier("id3", entity: "EntityA")
        let deleteChange = try setup.addObjectChange(type: .delete, globalIdentifier: gid3, event: event)
        #expect(deleteChange.type == .delete)

        // Verify round-trip through database
        let fetched = try setup.eventStore.fetchObjectChange(id: updateChange.id)!
        #expect(fetched.type == .update)
    }

    @Test("Object change type raw values")
    func objectChangeTypeRawValues() {
        #expect(ObjectChangeType.insert.rawValue == 100)
        #expect(ObjectChangeType.update.rawValue == 200)
        #expect(ObjectChangeType.delete.rawValue == 300)
    }

    @Test("Count of object changes in events")
    func countObjectChanges() throws {
        let setup = try TestEventStoreSetup()
        let gid1 = try setup.addGlobalIdentifier("id1", entity: "EntityA")
        let gid2 = try setup.addGlobalIdentifier("id2", entity: "EntityA")
        let event = try setup.addModEvent(store: "store1", revision: 0)
        try setup.addObjectChange(type: .insert, globalIdentifier: gid1, event: event)
        try setup.addObjectChange(type: .insert, globalIdentifier: gid2, event: event)

        let count = try setup.eventStore.fetchObjectChangeCount(eventIds: [event.id])
        #expect(count == 2)
    }

    @Test("Merge values from another change")
    func mergeValues() throws {
        let setup = try TestEventStoreSetup()
        let gid = try setup.addGlobalIdentifier("id1", entity: "EntityA")
        let event1 = try setup.addModEvent(store: "store1", revision: 0)

        let storedValue1 = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "name", value: .string("Alice"))
        let change1 = try setup.addObjectChange(type: .update, globalIdentifier: gid, event: event1, propertyChanges: [storedValue1])

        let event2 = try setup.addModEvent(store: "store2", revision: 0)
        let storedValue2 = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "name", value: .string("Bob"))
        let storedValue3 = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "age", value: .int(30))
        let change2 = try setup.addObjectChange(type: .update, globalIdentifier: gid, event: event2, propertyChanges: [storedValue2, storedValue3])

        // Merge change2 into change1, treating change2 as subordinate
        let merged = change1.mergingValues(from: change2, treatOtherAsSubordinate: true)

        let mergedValues = merged.propertyChangeValues ?? []
        let nameValue = mergedValues.first(where: { $0.propertyName == "name" })
        let ageValue = mergedValues.first(where: { $0.propertyName == "age" })

        #expect(mergedValues.count == 2)
        // When subordinate=true, existing value wins for attributes
        #expect(nameValue?.value == .string("Alice"))
        #expect(ageValue?.value == .int(30))
    }

    @Test("Merge values with subordinate false overrides")
    func mergeValuesSubordinateFalse() throws {
        let setup = try TestEventStoreSetup()
        let gid = try setup.addGlobalIdentifier("id1", entity: "EntityA")
        let event = try setup.addModEvent(store: "store1", revision: 0)

        let value1 = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "a", value: .string("A"))
        let change1 = try setup.addObjectChange(type: .update, globalIdentifier: gid, event: event, propertyChanges: [value1])

        let value2 = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "a", value: .string("AA"))
        let event2 = try setup.addModEvent(store: "store2", revision: 0)
        let change2 = try setup.addObjectChange(type: .update, globalIdentifier: gid, event: event2, propertyChanges: [value2])

        // subordinate=true: existing value wins
        let merged1 = change1.mergingValues(from: change2, treatOtherAsSubordinate: true)
        let result1 = merged1.propertyChangeValues?.first(where: { $0.propertyName == "a" })
        #expect(result1?.value == .string("A"))

        // subordinate=false: incoming value wins
        let merged2 = change1.mergingValues(from: change2, treatOtherAsSubordinate: false)
        let result2 = merged2.propertyChangeValues?.first(where: { $0.propertyName == "a" })
        #expect(result2?.value == .string("AA"))
    }

    @Test("Merge values with differing property names")
    func mergeValuesWithDifferingPropertyNames() throws {
        let value1 = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "a", value: .string("A"))

        let change1 = ObjectChange(id: 1, type: .update, nameOfEntity: "E", eventId: 1, globalIdentifierId: 1, propertyChangeValues: [value1])
        let change2 = ObjectChange(id: 2, type: .update, nameOfEntity: "E", eventId: 1, globalIdentifierId: 1, propertyChangeValues: [])

        // Merge empty into non-empty: value persists
        var merged = change1.mergingValues(from: change2, treatOtherAsSubordinate: true)
        var result = merged.propertyChangeValues?.first(where: { $0.propertyName == "a" })
        #expect(result?.value == .string("A"))

        merged = change1.mergingValues(from: change2, treatOtherAsSubordinate: false)
        result = merged.propertyChangeValues?.first(where: { $0.propertyName == "a" })
        #expect(result?.value == .string("A"))

        // Merge non-empty into empty: value transferred
        let change1Empty = ObjectChange(id: 1, type: .update, nameOfEntity: "E", eventId: 1, globalIdentifierId: 1, propertyChangeValues: [])
        let change2WithValue = ObjectChange(id: 2, type: .update, nameOfEntity: "E", eventId: 1, globalIdentifierId: 1, propertyChangeValues: [value1])

        merged = change1Empty.mergingValues(from: change2WithValue, treatOtherAsSubordinate: true)
        result = merged.propertyChangeValues?.first(where: { $0.propertyName == "a" })
        #expect(result?.value == .string("A"))

        merged = change1Empty.mergingValues(from: change2WithValue, treatOtherAsSubordinate: false)
        result = merged.propertyChangeValues?.first(where: { $0.propertyName == "a" })
        #expect(result?.value == .string("A"))
    }

    @Test("Required properties: nameOfEntity is non-optional")
    func requiredPropertiesNameOfEntity() throws {
        // In the struct model, nameOfEntity is a non-optional String,
        // so this constraint is enforced at compile time. Verify it's present after insert.
        let setup = try TestEventStoreSetup()
        let gid = try setup.addGlobalIdentifier("123", entity: "CDEObjectChange")
        let event = try setup.addModEvent(store: "1234", revision: 0, timestamp: 123)
        let change = try setup.addObjectChange(type: .update, globalIdentifier: gid, event: event)
        #expect(!change.nameOfEntity.isEmpty)
    }

    @Test("Required properties: all valid inserts successfully")
    func requiredPropertiesAllValid() throws {
        let setup = try TestEventStoreSetup()
        let gid = try setup.addGlobalIdentifier("123", entity: "CDEObjectChange")
        let event = try setup.addModEvent(store: "1234", revision: 0, timestamp: 123)
        let storedChange = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "c")
        let change = try setup.addObjectChange(type: .update, globalIdentifier: gid, event: event, propertyChanges: [storedChange])
        #expect(change.id > 0)
    }

    @Test("Property values saved and restored")
    func propertyValuesSavedAndRestored() throws {
        let setup = try TestEventStoreSetup()
        let gid = try setup.addGlobalIdentifier("123", entity: "Entity")
        let event = try setup.addModEvent(store: "store1", revision: 0, timestamp: 123)
        let storedChange = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "val")
        try setup.addObjectChange(type: .update, globalIdentifier: gid, event: event, propertyChanges: [storedChange])

        let changes = try setup.eventStore.fetchObjectChanges(eventId: event.id)
        #expect(changes.count == 1)
        let values = changes.first?.propertyChangeValues ?? []
        #expect(values.count == 1)
        #expect(values.first?.propertyName == "val")
    }
}
