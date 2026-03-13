import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("EventFileSet")
struct EventFileSetTests {

    @Test("Initializing with invalid filename returns nil")
    func invalidFilename() {
        let set = EventFileSet(filename: "Wrong", isBaseline: false)
        #expect(set == nil)
    }

    @Test("Initializing with legacy baseline")
    func legacyBaseline() throws {
        let set = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK.cdeevent", isBaseline: true))
        #expect(set.isBaseline == true)
        #expect(set.uniqueIdentifier == "JHK-HKJH-LHK")
        #expect(set.globalCount == 345)
        #expect(set.persistentStoreIdentifier == nil)
        #expect(set.totalNumberOfParts == 1)
    }

    @Test("Initializing with new baseline")
    func newBaseline() throws {
        let set = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ.cdeevent", isBaseline: true))
        #expect(set.isBaseline == true)
        #expect(set.globalCount == 345)
        #expect(set.uniqueIdentifier == "JHK-HKJH-LHK")
        #expect(set.persistentStoreIdentifier == nil)
        #expect(set.persistentStorePrefix == "JFHDJHBJ")
        #expect(set.totalNumberOfParts == 1)
    }

    @Test("Initializing with standard event")
    func standardEvent() throws {
        let set = try #require(EventFileSet(filename: "345_JHKTKJKJ-HKJH-LHK_67.cdeevent", isBaseline: false))
        #expect(set.isBaseline == false)
        #expect(set.globalCount == 345)
        #expect(set.revisionNumber == 67)
        #expect(set.persistentStoreIdentifier == "JHKTKJKJ-HKJH-LHK")
        #expect(set.persistentStorePrefix == "JHKTKJKJ")
        #expect(set.totalNumberOfParts == 1)
    }

    @Test("Multipart baseline")
    func multipartBaseline() throws {
        let set = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_3of23.cdeevent", isBaseline: true))
        #expect(set.isBaseline == true)
        #expect(set.globalCount == 345)
        #expect(set.uniqueIdentifier == "JHK-HKJH-LHK")
        #expect(set.persistentStoreIdentifier == nil)
        #expect(set.persistentStorePrefix == "JFHDJHBJ")
        #expect(set.totalNumberOfParts == 23)
        #expect(set.partIndexSet.count == 1)
    }

    @Test("Multipart standard event")
    func multipartStandardEvent() throws {
        let set = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK-JFHDJHBJ_7_3of23.cdeevent", isBaseline: false))
        #expect(set.isBaseline == false)
        #expect(set.globalCount == 345)
        #expect(set.revisionNumber == 7)
        #expect(set.persistentStoreIdentifier == "JHK-HKJH-LHK-JFHDJHBJ")
        #expect(set.persistentStorePrefix == "JHK-HKJH")
        #expect(set.totalNumberOfParts == 23)
        #expect(set.partIndexSet.count == 1)
    }

    @Test("Adding a part to baseline")
    func addPartToBaseline() throws {
        let set = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_3of23.cdeevent", isBaseline: true))
        set.addPartIndex(forFile: "345_JHK-HKJH-LHK_JFHDJHBJ_4of23.cdeevent")
        #expect(set.partIndexSet.count == 2)
    }

    @Test("Adding a part to standard event")
    func addPartToStandardEvent() throws {
        let set = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK-JFHDJHBJ_7_3of23.cdeevent", isBaseline: false))
        set.addPartIndex(forFile: "345_JHK-HKJH-LHK-JFHDJHBJ_7_4of23.cdeevent")
        #expect(set.partIndexSet.count == 2)
    }

    @Test("Adding a part twice")
    func addPartTwice() throws {
        let set = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_3of23.cdeevent", isBaseline: true))
        set.addPartIndex(forFile: "345_JHK-HKJH-LHK_JFHDJHBJ_4of23.cdeevent")
        set.addPartIndex(forFile: "345_JHK-HKJH-LHK_JFHDJHBJ_4of23.cdeevent")
        #expect(set.partIndexSet.count == 2)
    }

    @Test("Same event file represents same event")
    func sameEventRepresentsSameEvent() throws {
        let set1 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_3of23.cdeevent", isBaseline: true))
        let set2 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_3of23.cdeevent", isBaseline: true))
        #expect(set1.representsSameEvent(as: set2))
    }

    @Test("Different parts represent same event")
    func differentPartsRepresentSameEvent() throws {
        let set1 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_3of23.cdeevent", isBaseline: true))
        let set2 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_20of23.cdeevent", isBaseline: true))
        #expect(set1.representsSameEvent(as: set2))
    }

    @Test("Different baseline settings do not represent same event")
    func differentBaselineNotSameEvent() throws {
        let set1 = try #require(EventFileSet(filename: "345_JFHDJHBJ_3of23.cdeevent", isBaseline: false))
        let set2 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_20of23.cdeevent", isBaseline: true))
        #expect(!set1.representsSameEvent(as: set2))
    }

    @Test("Legacy baseline matches multipart baseline")
    func legacyMatchesMultipart() throws {
        let set1 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK.cdeevent", isBaseline: true))
        let set2 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_20of23.cdeevent", isBaseline: true))
        #expect(set1.representsSameEvent(as: set2))
    }

    @Test("Single part matches multipart file set")
    func singlePartMatchesMultipart() throws {
        let set1 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_1.cdeevent", isBaseline: false))
        let set2 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_1_1of2.cdeevent", isBaseline: false))
        #expect(set1.representsSameEvent(as: set2))
    }

    @Test("Different revision numbers do not represent same file set")
    func differentRevisionNotSame() throws {
        let set1 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_2_2of2.cdeevent", isBaseline: false))
        let set2 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_1_1of2.cdeevent", isBaseline: false))
        #expect(!set1.representsSameEvent(as: set2))
    }

    @Test("Different global counts in baselines do not represent same file set")
    func differentGlobalCountsNotSame() throws {
        let set1 = try #require(EventFileSet(filename: "346_JHK-HKJH-LHK_JFHDJHBJ_3of23.cdeevent", isBaseline: true))
        let set2 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_20of23.cdeevent", isBaseline: true))
        #expect(!set1.representsSameEvent(as: set2))
    }

    @Test("Different store prefixes in baselines do not represent same file set")
    func differentStorePrefixesNotSame() throws {
        let set1 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJKKK_3of23.cdeevent", isBaseline: true))
        let set2 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_20of23.cdeevent", isBaseline: true))
        #expect(!set1.representsSameEvent(as: set2))
    }

    @Test("Different unique IDs in baselines do not represent same file set")
    func differentUniqueIdsNotSame() throws {
        let set1 = try #require(EventFileSet(filename: "345_JHK-HKJH-LLL_JFHDJHBJ_3of23.cdeevent", isBaseline: true))
        let set2 = try #require(EventFileSet(filename: "345_JHK-HKJH-LHK_JFHDJHBJ_20of23.cdeevent", isBaseline: true))
        #expect(!set1.representsSameEvent(as: set2))
    }

    @Test("Creating event file sets for many files")
    func createEventFileSetsForManyFiles() {
        let filenames: Set<String> = [
            "345_JHK-HKJH-LHK_JFHDJHBJ_3of23.cdeevent",
            "345_JHK-HKJH-LHK_JFHDJHBJ_1of23.cdeevent",
            "345_AHK-HKJH-LHK_JFHDJHBJ_3of23.cdeevent",
            "345_AHK-HKJH-LHK_JFHDJHBJ_1of23.cdeevent",
        ]
        let sets = EventFileSet.eventFileSets(forFilenames: filenames, containingBaselines: true)
        #expect(sets.count == 2)
    }
}
