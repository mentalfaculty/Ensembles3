import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("Revision")
struct RevisionTests {

    @Test("Compare equal revisions")
    func compareEqualRevisions() {
        let rev1 = Revision(persistentStoreIdentifier: "1234", revisionNumber: 1)
        let rev2 = Revision(persistentStoreIdentifier: "1234", revisionNumber: 1)
        #expect(rev1 == rev2)
    }

    @Test("Compare unequal revisions with same store")
    func compareUnequalRevisions() {
        let rev1 = Revision(persistentStoreIdentifier: "1234", revisionNumber: 1)
        let rev2 = Revision(persistentStoreIdentifier: "1234", revisionNumber: 2)
        #expect(rev1 < rev2)
        #expect(rev2 > rev1)
    }

    @Test("Equality for equal revisions")
    func equalRevisions() {
        let rev1 = Revision(persistentStoreIdentifier: "1234", revisionNumber: 1)
        let rev2 = Revision(persistentStoreIdentifier: "1234", revisionNumber: 1)
        #expect(rev1 == rev2)
    }

    @Test("Inequality for different revision numbers")
    func unequalRevisionNumbers() {
        let rev1 = Revision(persistentStoreIdentifier: "1234", revisionNumber: 3)
        let rev2 = Revision(persistentStoreIdentifier: "1234", revisionNumber: 2)
        #expect(rev1 != rev2)
    }

    @Test("Default initialization values")
    func defaultInit() {
        let rev = Revision()
        #expect(rev.persistentStoreIdentifier == nil)
        #expect(rev.revisionNumber == -1)
        #expect(rev.globalCount == -1)
    }

    @Test("Unique identifier format")
    func uniqueIdentifier() {
        let rev = Revision(persistentStoreIdentifier: "store1", revisionNumber: 5, globalCount: 10)
        #expect(rev.uniqueIdentifier == "10_5_store1")
    }

    @Test("Hashable conformance uses unique identifier")
    func hashable() {
        let rev1 = Revision(persistentStoreIdentifier: "1234", revisionNumber: 1, globalCount: 5)
        let rev2 = Revision(persistentStoreIdentifier: "1234", revisionNumber: 1, globalCount: 5)
        #expect(rev1.hashValue == rev2.hashValue)
        let set: Set<Revision> = [rev1, rev2]
        #expect(set.count == 1)
    }
}
