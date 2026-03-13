import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("ManagedObjectModel Extensions")
struct ManagedObjectModelTests {

    @Test("Entity hashes property list round-trip")
    func entityHashesPropertyListRoundTrip() throws {
        let entity = NSEntityDescription()
        entity.name = "TestEntity"
        let attribute = NSAttributeDescription()
        attribute.name = "name"
        attribute.attributeType = .stringAttributeType
        entity.properties = [attribute]
        let model = NSManagedObjectModel()
        model.entities = [entity]

        let propertyList = model.entityHashesPropertyList
        #expect(propertyList != nil)

        let dictionary = NSManagedObjectModel.entityHashesByName(fromPropertyList: propertyList)
        #expect(dictionary != nil)
        #expect(dictionary?["TestEntity"] != nil)
    }

    @Test("Entity hashes from nil property list returns nil")
    func entityHashesFromNil() {
        let dictionary = NSManagedObjectModel.entityHashesByName(fromPropertyList: nil)
        #expect(dictionary == nil)
    }

    @Test("Compressed model hash starts with md5")
    func compressedModelHash() {
        let entity = NSEntityDescription()
        entity.name = "TestEntity"
        let attribute = NSAttributeDescription()
        attribute.name = "name"
        attribute.attributeType = .stringAttributeType
        entity.properties = [attribute]
        let model = NSManagedObjectModel()
        model.entities = [entity]

        let hash = model.compressedModelHash
        #expect(hash.hasPrefix("md5"))
    }

    @Test("Entities ordered by migration priority")
    func entitiesOrderedByMigrationPriority() {
        let entity1 = NSEntityDescription()
        entity1.name = "A"
        let entity2 = NSEntityDescription()
        entity2.name = "B"
        let model = NSManagedObjectModel()
        model.entities = [entity2, entity1]

        let ordered = model.entitiesOrderedByMigrationPriority
        #expect(ordered.count == 2)
        #expect(ordered[0].name == "A")
        #expect(ordered[1].name == "B")
    }

    @Test("Migration batch size defaults to zero")
    func migrationBatchSizeDefault() {
        let entity = NSEntityDescription()
        entity.name = "TestEntity"
        #expect(entity.migrationBatchSize == 0)
    }

    @Test("Descendant entities")
    func descendantEntities() {
        let parent = NSEntityDescription()
        parent.name = "Parent"
        let child = NSEntityDescription()
        child.name = "Child"
        parent.subentities = [child]
        let grandchild = NSEntityDescription()
        grandchild.name = "Grandchild"
        child.subentities = [grandchild]

        let descendants = parent.descendantEntities
        #expect(descendants.count == 2)
        #expect(descendants.contains(where: { $0.name == "Child" }))
        #expect(descendants.contains(where: { $0.name == "Grandchild" }))
    }

    @Test("Ancestor entities")
    func ancestorEntities() {
        let grandparent = NSEntityDescription()
        grandparent.name = "Grandparent"
        let parent = NSEntityDescription()
        parent.name = "Parent"
        grandparent.subentities = [parent]
        let child = NSEntityDescription()
        child.name = "Child"
        parent.subentities = [child]

        let ancestors = child.ancestorEntities
        #expect(ancestors.count == 2)
        #expect(ancestors[0].name == "Parent")
        #expect(ancestors[1].name == "Grandparent")
    }
}
