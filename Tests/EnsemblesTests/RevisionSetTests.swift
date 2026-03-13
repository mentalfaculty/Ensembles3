import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("RevisionSet")
struct RevisionSetTests {

    let revision1 = Revision(persistentStoreIdentifier: "1234", revisionNumber: 0)
    let revision2 = Revision(persistentStoreIdentifier: "1", revisionNumber: 2)

    @Test("Creating empty set")
    func createEmptySet() {
        let set = RevisionSet()
        #expect(set.numberOfRevisions == 0)
    }

    @Test("Adding a revision")
    func addRevision() {
        var set = RevisionSet()
        set.addRevision(revision1)
        #expect(set.numberOfRevisions == 1)
    }

    @Test("Adding same store twice overwrites")
    func addSameStoreTwice() {
        var set = RevisionSet()
        set.addRevision(revision1)
        set.addRevision(Revision(persistentStoreIdentifier: "1234", revisionNumber: 5))
        #expect(set.numberOfRevisions == 1)
        #expect(set.revision(forPersistentStoreIdentifier: "1234")?.revisionNumber == 5)
    }

    @Test("Removing existing revision")
    func removeExistingRevision() {
        var set = RevisionSet()
        set.addRevision(revision1)
        #expect(set.numberOfRevisions == 1)
        set.removeRevision(revision1)
        #expect(set.numberOfRevisions == 0)
    }

    @Test("Remove by persistent store identifier")
    func removeByIdentifier() {
        var set = RevisionSet()
        set.addRevision(revision1)
        set.removeRevision(forPersistentStoreIdentifier: "1234")
        #expect(set.numberOfRevisions == 0)
    }

    @Test("Membership for non-existent store")
    func membershipNonExistent() {
        let set = RevisionSet()
        #expect(!set.hasRevision(forPersistentStoreIdentifier: "12"))
    }

    @Test("Membership for existing store")
    func membershipExisting() {
        var set = RevisionSet()
        set.addRevision(revision1)
        #expect(set.hasRevision(forPersistentStoreIdentifier: "1234"))
    }

    @Test("Incrementing existing store")
    func incrementExistingStore() {
        var set = RevisionSet()
        set.addRevision(revision1)
        set.addRevision(revision2)
        set.incrementRevision(forStoreWithIdentifier: "1234")
        let rev = set.revision(forPersistentStoreIdentifier: "1234")
        #expect(rev?.revisionNumber == 1)
    }

    @Test("Accessing revisions")
    func accessingRevisions() {
        var set = RevisionSet()
        set.addRevision(revision1)
        set.addRevision(revision2)
        #expect(set.revisions.count == 2)
    }

    @Test("Persistent store identifiers")
    func persistentStoreIdentifiers() {
        var set = RevisionSet()
        set.addRevision(revision1)
        set.addRevision(revision2)
        #expect(set.persistentStoreIdentifiers == Set(["1234", "1"]))
    }

    @Test("Store-wise minimum with empty set")
    func storeWiseMinimumWithEmptySet() {
        var set = RevisionSet()
        set.addRevision(revision2)
        let other = RevisionSet()
        let result = set.storeWiseMinimum(with: other)
        #expect(result.numberOfRevisions == 1)
        let rev = result.revision(forPersistentStoreIdentifier: "1")
        #expect(rev?.revisionNumber == 2)
    }

    @Test("Store-wise minimum with different stores")
    func storeWiseMinimumDifferentStores() {
        var set = RevisionSet()
        set.addRevision(revision2)
        var other = RevisionSet()
        other.addRevision(revision1)
        let result = other.storeWiseMinimum(with: set)
        #expect(result.numberOfRevisions == 2)
        let rev = result.revision(forPersistentStoreIdentifier: "1")
        #expect(rev?.revisionNumber == 2)
    }

    @Test("Store-wise minimum with same store")
    func storeWiseMinimumSameStore() {
        var set = RevisionSet()
        set.addRevision(revision2)
        var other = RevisionSet()
        other.addRevision(Revision(persistentStoreIdentifier: "1", revisionNumber: 1))
        let result = other.storeWiseMinimum(with: set)
        #expect(result.numberOfRevisions == 1)
        let rev = result.revision(forPersistentStoreIdentifier: "1")
        #expect(rev?.revisionNumber == 1)
    }

    @Test("Store-wise maximum with empty set")
    func storeWiseMaximumWithEmptySet() {
        var set = RevisionSet()
        set.addRevision(revision2)
        let other = RevisionSet()
        let result = other.storeWiseMaximum(with: set)
        #expect(result.numberOfRevisions == 1)
        let rev = result.revision(forPersistentStoreIdentifier: "1")
        #expect(rev?.revisionNumber == 2)
    }

    @Test("Store-wise maximum with same store")
    func storeWiseMaximumSameStore() {
        var set = RevisionSet()
        set.addRevision(revision2)
        var other = RevisionSet()
        other.addRevision(Revision(persistentStoreIdentifier: "1", revisionNumber: 1))
        let result = other.storeWiseMaximum(with: set)
        #expect(result.numberOfRevisions == 1)
        let rev = result.revision(forPersistentStoreIdentifier: "1")
        #expect(rev?.revisionNumber == 2)
    }

    @Test("Static store-wise minimum of array")
    func staticStoreWiseMinimum() {
        var set1 = RevisionSet()
        set1.addRevision(Revision(persistentStoreIdentifier: "A", revisionNumber: 5))
        var set2 = RevisionSet()
        set2.addRevision(Revision(persistentStoreIdentifier: "A", revisionNumber: 3))
        let result = RevisionSet.storeWiseMinimum(of: [set1, set2])
        #expect(result.revision(forPersistentStoreIdentifier: "A")?.revisionNumber == 3)
    }

    @Test("Static store-wise maximum of array")
    func staticStoreWiseMaximum() {
        var set1 = RevisionSet()
        set1.addRevision(Revision(persistentStoreIdentifier: "A", revisionNumber: 5))
        var set2 = RevisionSet()
        set2.addRevision(Revision(persistentStoreIdentifier: "A", revisionNumber: 3))
        let result = RevisionSet.storeWiseMaximum(of: [set1, set2])
        #expect(result.revision(forPersistentStoreIdentifier: "A")?.revisionNumber == 5)
    }

    @Test("Comparison of equal revision sets")
    func compareEqualSets() {
        var set = RevisionSet()
        set.addRevision(revision2)
        set.addRevision(revision1)
        var other = RevisionSet()
        other.addRevision(revision2)
        other.addRevision(revision1)
        #expect(set.compare(other) == .orderedSame)
    }

    @Test("Comparison with subset revision set")
    func compareSubset() {
        var set = RevisionSet()
        set.addRevision(revision2)
        set.addRevision(revision1)
        var other = RevisionSet()
        other.addRevision(revision2)
        #expect(set.compare(other) == .orderedDescending)
        #expect(other.compare(set) == .orderedAscending)
    }

    @Test("Comparison with concurrent revision sets returns orderedSame")
    func compareConcurrent() {
        var set = RevisionSet()
        set.addRevision(revision2)
        set.addRevision(revision1)

        var other = RevisionSet()
        other.addRevision(Revision(persistentStoreIdentifier: "1234", revisionNumber: 1))
        other.addRevision(Revision(persistentStoreIdentifier: "1", revisionNumber: 1))
        #expect(set.compare(other) == .orderedSame)
    }

    @Test("Comparison with one superset")
    func compareOneSuperset() {
        var set = RevisionSet()
        set.addRevision(revision2)
        set.addRevision(revision1)

        var other = RevisionSet()
        other.addRevision(Revision(persistentStoreIdentifier: "1234", revisionNumber: 0))
        other.addRevision(Revision(persistentStoreIdentifier: "1", revisionNumber: 3))
        #expect(set.compare(other) == .orderedAscending)
        #expect(other.compare(set) == .orderedDescending)
    }

    @Test("Archive and unarchive round-trip")
    func archiveRoundTrip() throws {
        var set = RevisionSet()
        set.addRevision(Revision(persistentStoreIdentifier: "store1", revisionNumber: 5, globalCount: 10))
        set.addRevision(Revision(persistentStoreIdentifier: "store2", revisionNumber: 3, globalCount: 7))

        let data = try set.archivedData()
        let restored = try RevisionSet(archivedData: data)

        #expect(restored.numberOfRevisions == 2)
        #expect(restored.revision(forPersistentStoreIdentifier: "store1")?.revisionNumber == 5)
        #expect(restored.revision(forPersistentStoreIdentifier: "store1")?.globalCount == 10)
        #expect(restored.revision(forPersistentStoreIdentifier: "store2")?.revisionNumber == 3)
        #expect(restored.revision(forPersistentStoreIdentifier: "store2")?.globalCount == 7)
    }

    @Test("isEqual method")
    func isEqualMethod() {
        var set1 = RevisionSet()
        set1.addRevision(Revision(persistentStoreIdentifier: "A", revisionNumber: 1))
        var set2 = RevisionSet()
        set2.addRevision(Revision(persistentStoreIdentifier: "A", revisionNumber: 1))
        #expect(set1.isEqual(to: set2))
        #expect(set1 == set2)
    }

    @Test("isEqual returns false for different revision numbers")
    func isNotEqualDifferentNumbers() {
        var set1 = RevisionSet()
        set1.addRevision(Revision(persistentStoreIdentifier: "A", revisionNumber: 1))
        var set2 = RevisionSet()
        set2.addRevision(Revision(persistentStoreIdentifier: "A", revisionNumber: 2))
        #expect(!set1.isEqual(to: set2))
        #expect(set1 != set2)
    }

    @Test("isEqual returns false for different stores")
    func isNotEqualDifferentStores() {
        var set1 = RevisionSet()
        set1.addRevision(Revision(persistentStoreIdentifier: "A", revisionNumber: 1))
        var set2 = RevisionSet()
        set2.addRevision(Revision(persistentStoreIdentifier: "B", revisionNumber: 1))
        #expect(!set1.isEqual(to: set2))
    }
}
