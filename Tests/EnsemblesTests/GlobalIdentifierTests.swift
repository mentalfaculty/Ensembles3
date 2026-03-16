import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("GlobalIdentifier")
struct GlobalIdentifierTests {

    @Test("Fetch for non-existent identifier returns nil")
    func fetchNonExistent() throws {
        let setup = try TestEventStoreSetup()
        try setup.addGlobalIdentifier("aaa", entity: "EntityA")
        let ids = try setup.eventStore.fetchGlobalIdentifiers(
            forIdentifierStrings: ["ccc"],
            withEntityNames: ["EntityA"]
        )
        #expect(ids.count == 1)
        #expect(ids[0] == nil)
    }

    @Test("Fetch matching global ID but wrong entity returns nil")
    func fetchWrongEntity() throws {
        let setup = try TestEventStoreSetup()
        try setup.addGlobalIdentifier("aaa", entity: "EntityA")
        let ids = try setup.eventStore.fetchGlobalIdentifiers(
            forIdentifierStrings: ["aaa"],
            withEntityNames: ["EntityB"]
        )
        #expect(ids.count == 1)
        #expect(ids[0] == nil)
    }

    @Test("Fetch matching global ID and entity returns object")
    func fetchMatching() throws {
        let setup = try TestEventStoreSetup()
        let gid = try setup.addGlobalIdentifier("aaa", entity: "EntityA")
        let ids = try setup.eventStore.fetchGlobalIdentifiers(
            forIdentifierStrings: ["aaa"],
            withEntityNames: ["EntityA"]
        )
        #expect(ids.count == 1)
        #expect(ids[0]?.id == gid.id)
    }

    @Test("Fetch multiple global IDs")
    func fetchMultiple() throws {
        let setup = try TestEventStoreSetup()
        let gid1 = try setup.addGlobalIdentifier("aaa", entity: "EntityA")
        let gid2 = try setup.addGlobalIdentifier("bbb", entity: "EntityB")
        try setup.addGlobalIdentifier("bbb", entity: "EntityC")
        let ids = try setup.eventStore.fetchGlobalIdentifiers(
            forIdentifierStrings: ["bbb", "aaa", "aaa"],
            withEntityNames: ["EntityB", "EntityA", "EntityC"]
        )
        #expect(ids.count == 3)
        #expect(ids[0]?.id == gid2.id)
        #expect(ids[1]?.id == gid1.id)
        #expect(ids[2] == nil) // aaa with EntityC does not exist
    }

    @Test("Fetch multiple objects with same ID but different entities")
    func fetchSameIdDifferentEntities() throws {
        let setup = try TestEventStoreSetup()
        let gid2 = try setup.addGlobalIdentifier("bbb", entity: "EntityB")
        let gid3 = try setup.addGlobalIdentifier("bbb", entity: "EntityC")
        let ids = try setup.eventStore.fetchGlobalIdentifiers(
            forIdentifierStrings: ["bbb", "bbb"],
            withEntityNames: ["EntityB", "EntityC"]
        )
        #expect(ids[0]?.id == gid2.id)
        #expect(ids[1]?.id == gid3.id)
    }
}
