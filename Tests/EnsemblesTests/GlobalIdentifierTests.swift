import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("GlobalIdentifier")
struct GlobalIdentifierTests {

    @Test("Fetch for non-existent identifier returns nil")
    func fetchNonExistent() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            _ = stack.addGlobalIdentifier("aaa", entity: "EntityA")
            let ids = try! GlobalIdentifier.fetchGlobalIdentifiers(
                forIdentifierStrings: ["ccc"],
                withEntityNames: ["EntityA"],
                in: stack.context
            )
            #expect(ids.count == 1)
            #expect(ids[0] == nil)
        }
    }

    @Test("Fetch matching global ID but wrong entity returns nil")
    func fetchWrongEntity() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            _ = stack.addGlobalIdentifier("aaa", entity: "EntityA")
            let ids = try! GlobalIdentifier.fetchGlobalIdentifiers(
                forIdentifierStrings: ["aaa"],
                withEntityNames: ["EntityB"],
                in: stack.context
            )
            #expect(ids.count == 1)
            #expect(ids[0] == nil)
        }
    }

    @Test("Fetch matching global ID and entity returns object")
    func fetchMatching() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let gid = stack.addGlobalIdentifier("aaa", entity: "EntityA")
            let ids = try! GlobalIdentifier.fetchGlobalIdentifiers(
                forIdentifierStrings: ["aaa"],
                withEntityNames: ["EntityA"],
                in: stack.context
            )
            #expect(ids.count == 1)
            #expect(ids[0] === gid)
        }
    }

    @Test("Fetch multiple global IDs")
    func fetchMultiple() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let gid1 = stack.addGlobalIdentifier("aaa", entity: "EntityA")
            let gid2 = stack.addGlobalIdentifier("bbb", entity: "EntityB")
            _ = stack.addGlobalIdentifier("bbb", entity: "EntityC")
            let ids = try! GlobalIdentifier.fetchGlobalIdentifiers(
                forIdentifierStrings: ["bbb", "aaa", "aaa"],
                withEntityNames: ["EntityB", "EntityA", "EntityC"],
                in: stack.context
            )
            #expect(ids.count == 3)
            #expect(ids[0] === gid2)
            #expect(ids[1] === gid1)
            #expect(ids[2] == nil) // aaa with EntityC does not exist
        }
    }

    @Test("Fetch multiple objects with same ID but different entities")
    func fetchSameIdDifferentEntities() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let gid2 = stack.addGlobalIdentifier("bbb", entity: "EntityB")
            let gid3 = stack.addGlobalIdentifier("bbb", entity: "EntityC")
            let ids = try! GlobalIdentifier.fetchGlobalIdentifiers(
                forIdentifierStrings: ["bbb", "bbb"],
                withEntityNames: ["EntityB", "EntityC"],
                in: stack.context
            )
            #expect(ids[0] === gid2)
            #expect(ids[1] === gid3)
        }
    }
}
