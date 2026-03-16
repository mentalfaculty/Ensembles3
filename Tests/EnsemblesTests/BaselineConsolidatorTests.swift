import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("BaselineConsolidator", .serialized)
struct BaselineConsolidatorTests {

    let setup: TestEventStoreSetup
    let consolidator: BaselineConsolidator

    init() throws {
        let s = try TestEventStoreSetup()
        let c = BaselineConsolidator(eventStore: s.eventStore, ensemble: nil)
        setup = s
        consolidator = c
    }

    // MARK: - Consolidation Needed

    @Test("No consolidation needed for no baselines")
    func consolidationNotNeededForNoBaselines() {
        #expect(!consolidator.baselineNeedsConsolidation())
    }

    @Test("No consolidation needed for one baseline")
    func consolidationNotNeededForOneBaseline() throws {
        try setup.addBaselineEvents(storeId: "store1", globalCounts: [0], revisions: [0])
        #expect(!consolidator.baselineNeedsConsolidation())
    }

    @Test("Consolidation needed for two baselines")
    func consolidationNeededForTwoBaselines() throws {
        try setup.addBaselineEvents(storeId: "store1", globalCounts: [0], revisions: [0])
        try setup.addBaselineEvents(storeId: "store2", globalCounts: [0], revisions: [0])
        #expect(consolidator.baselineNeedsConsolidation())
    }

    // MARK: - Consolidation

    @Test("Consolidating multiple baselines keeps most recent")
    func consolidatingMultipleBaselinesKeepsMostRecent() async throws {
        try setup.addBaselineEvents(storeId: "123", globalCounts: [2, 0, 1], revisions: [2, 0, 1])

        try await consolidator.consolidateBaseline()

        let events = try setup.fetchStoreModEvents()
        #expect(events.count == 1)
        #expect(events.last?.globalCount == 2)
    }

    @Test("Consolidating with an empty baseline prioritizes non-empty")
    func consolidatingWithEmptyBaselinePrioritizesNonEmpty() async throws {
        PropertyChangeValue.registerTransformer()
        try setup.addBaselineEvents(storeId: "123", globalCounts: [0], revisions: [0])
        let nonEmptyBaselines = try setup.addBaselineEvents(storeId: "234", globalCounts: [2], revisions: [2])

        let nonEmptyBaseline = nonEmptyBaselines.last!
        let nonEmptyUniqueID = nonEmptyBaseline.uniqueIdentifier

        let globalId = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "123", nameOfEntity: "Parent")
        try setup.objectChange(globalId: globalId, valuesByKey: ["date": NSDate(timeIntervalSince1970: 10)], event: nonEmptyBaseline)

        try await consolidator.consolidateBaseline()

        let events = try setup.fetchStoreModEvents()
        #expect(events.count == 1)

        let event = events.last!
        #expect(event.globalCount == 2)
        let revSet = try setup.eventStore.revisionSet(forEventId: event.id)
        #expect(revSet.revision(forPersistentStoreIdentifier: "123")?.revisionNumber == 0)
        #expect(revSet.revision(forPersistentStoreIdentifier: "234")?.revisionNumber == 2)
        #expect(event.uniqueIdentifier != nonEmptyUniqueID)
    }

    @Test("Consolidating two empty baselines produces one empty baseline")
    func consolidatingTwoEmptyBaselines() async throws {
        try setup.addBaselineEvents(storeId: "123", globalCounts: [0], revisions: [0])
        try setup.addBaselineEvents(storeId: "234", globalCounts: [0], revisions: [0])

        try await consolidator.consolidateBaseline()

        let events = try setup.fetchStoreModEvents()
        #expect(events.count == 1)

        let event = events.last!
        #expect(event.globalCount == 0)
        let revSet = try setup.eventStore.revisionSet(forEventId: event.id)
        #expect(revSet.revision(forPersistentStoreIdentifier: "123") != nil)
        #expect(revSet.revision(forPersistentStoreIdentifier: "234") != nil)
        #expect(revSet.revision(forPersistentStoreIdentifier: "123")?.revisionNumber == 0)
        #expect(revSet.revision(forPersistentStoreIdentifier: "234")?.revisionNumber == 0)
    }

    @Test("Consolidating with multiple empty baselines")
    func consolidatingWithMultipleEmptyBaselines() async throws {
        let mergedBaselines = try setup.addBaselineEvents(storeId: "123", globalCounts: [2], revisions: [2])
        try setup.addBaselineEvents(storeId: "234", globalCounts: [0], revisions: [0])

        let mergedBaselineID = mergedBaselines.last!.uniqueIdentifier

        try await consolidator.consolidateBaseline()

        let events = try setup.fetchStoreModEvents()
        #expect(events.count == 1)

        let event = events.last!
        #expect(event.globalCount == 2)
        let revSet = try setup.eventStore.revisionSet(forEventId: event.id)
        #expect(revSet.revision(forPersistentStoreIdentifier: "123")?.revisionNumber == 2)
        #expect(revSet.revision(forPersistentStoreIdentifier: "234")?.revisionNumber == 0)
        #expect(event.uniqueIdentifier != mergedBaselineID)
    }

    @Test("Consolidating multiple baselines with multiple stores keeps most recent")
    func consolidatingMultipleBaselinesWithMultipleStores() async throws {
        try setup.addBaselineEvents(storeId: "123", globalCounts: [2, 0, 1], revisions: [2, 0, 1])
        let baselines = try setup.addBaselineEvents(storeId: "234", globalCounts: [3], revisions: [0])

        let mostRecentBaselineId = baselines.last!.id

        try await consolidator.consolidateBaseline()

        let events = try setup.fetchStoreModEvents()
        #expect(events.count == 1)

        let event = events.last!
        #expect(event.id == mostRecentBaselineId)
        #expect(event.globalCount == 3)
    }

    @Test("Consolidating baselines with different model triggers full integration")
    func consolidatingWithDifferentModel() async throws {
        let baselines = try setup.addBaselineEvents(storeId: "123", globalCounts: [2, 0, 1], revisions: [2, 0, 1])

        let secondBaseline = baselines[1]
        setup.eventStore.identifierOfBaselineUsedToConstructStore = secondBaseline.uniqueIdentifier
        try setup.eventStore.updateEventModelVersion(id: baselines.last!.id, modelVersion: "A DIFFERENT MODEL", modelVersionIdentifier: nil)

        try await consolidator.consolidateBaseline()

        #expect(setup.eventStore.needsFullIntegration)
    }

    @Test("Consolidating baselines with nil model triggers full integration")
    func consolidatingWithNilModel() async throws {
        let baselines = try setup.addBaselineEvents(storeId: "123", globalCounts: [2, 0, 1], revisions: [2, 0, 1])

        let secondBaseline = baselines[1]
        setup.eventStore.identifierOfBaselineUsedToConstructStore = secondBaseline.uniqueIdentifier
        try setup.eventStore.updateEventModelVersion(id: baselines.last!.id, modelVersion: nil, modelVersionIdentifier: nil)

        try await consolidator.consolidateBaseline()

        #expect(setup.eventStore.needsFullIntegration)
    }

    @Test("Consolidating where local baseline prevails triggers no full integration")
    func consolidatingWhereLocalBaselinePrevails() async throws {
        let baselines = try setup.addBaselineEvents(storeId: "123", globalCounts: [2, 0, 1], revisions: [2, 0, 1])

        setup.eventStore.identifierOfBaselineUsedToConstructStore = baselines[0].uniqueIdentifier

        try await consolidator.consolidateBaseline()

        // When there are concurrent baselines, needsFullIntegration is set to true
        // even if the local baseline prevails, because the concurrent baseline
        // might have different data
        // The ObjC test expected false because the redundant baselines were subset,
        // but in Swift the consolidator always sets needsFullIntegration when merging
        // multiple concurrent baselines. Since this is a single-store scenario with
        // the 3 baselines all being from "123", the redundant ones are eliminated
        // first, leaving only 1.
        #expect(!setup.eventStore.needsFullIntegration)
    }

    @Test("Consolidating baselines with same model triggers no full integration")
    func consolidatingWithSameModel() async throws {
        try setup.addBaselineEvents(storeId: "123", globalCounts: [2, 0, 1], revisions: [2, 0, 1])

        try await consolidator.consolidateBaseline()

        #expect(!setup.eventStore.needsFullIntegration)
    }

    @Test("Baseline revisions when merging concurrent baselines")
    func baselineRevisionsWhenMergingConcurrent() async throws {
        try setup.addBaselineEvents(storeId: "123", globalCounts: [10], revisions: [10])
        try setup.addBaselineEvents(storeId: setup.persistentStoreIdentifier, globalCounts: [20], revisions: [11])

        try await consolidator.consolidateBaseline()

        #expect(setup.eventStore.needsFullIntegration)

        let events = try setup.fetchStoreModEvents()
        let event = events.last!

        let eventRevision = try setup.eventStore.fetchEventRevision(eventId: event.id)
        #expect(eventRevision?.revisionNumber == 11)

        let otherRevisions = try setup.eventStore.fetchOtherStoreRevisions(eventId: event.id)
        let rev123 = otherRevisions.first { $0.persistentStoreIdentifier == "123" }
        #expect(rev123?.revisionNumber == 10)
    }

    @Test("Merging concurrent baselines keeps most recent object change")
    func mergingConcurrentBaselinesKeepsMostRecentChange() async throws {
        PropertyChangeValue.registerTransformer()
        let baseline0 = try setup.addBaselineEvents(storeId: "123", globalCounts: [10], revisions: [10]).last!
        let baseline1 = try setup.addBaselineEvents(storeId: "234", globalCounts: [20], revisions: [10]).last!

        let globalId = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "123", nameOfEntity: "Parent")

        try setup.objectChange(globalId: globalId, valuesByKey: ["date": NSDate(timeIntervalSince1970: 10)], event: baseline0)
        try setup.objectChange(globalId: globalId, valuesByKey: ["date": NSDate(timeIntervalSince1970: 20)], event: baseline1)

        try await consolidator.consolidateBaseline()

        let events = try setup.fetchStoreModEvents()
        let event = events.last!

        let changes = try setup.eventStore.fetchObjectChanges(eventId: event.id)
        #expect(changes.count == 1)

        let change = changes.first!
        #expect(change.type == .insert)

        let values = change.propertyChangeValues ?? []
        #expect(values.count == 1)

        let value = values.last!
        #expect(value.value == StoredValue.date(NSDate(timeIntervalSince1970: 20).timeIntervalSinceReferenceDate))
        #expect(value.type == PropertyChangeType.attribute.rawValue)
    }

    @Test("Merging concurrent baselines gives low priority to new local baseline")
    func mergingConcurrentBaselinesLowPriorityLocalBaseline() async throws {
        PropertyChangeValue.registerTransformer()
        let baseline0 = try setup.addBaselineEvents(storeId: "123", globalCounts: [0], revisions: [0]).last!
        let baseline1 = try setup.addBaselineEvents(storeId: "234", globalCounts: [0], revisions: [0]).last!

        setup.eventStore.identifierOfBaselineUsedToConstructStore = baseline1.uniqueIdentifier

        let globalId = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "123", nameOfEntity: "Parent")

        try setup.objectChange(globalId: globalId, valuesByKey: ["date": NSDate(timeIntervalSince1970: 10)], event: baseline0)
        try setup.objectChange(globalId: globalId, valuesByKey: ["date": NSDate(timeIntervalSince1970: 20)], event: baseline1)

        try await consolidator.consolidateBaseline()

        let events = try setup.fetchStoreModEvents()
        let event = events.last!

        let changes = try setup.eventStore.fetchObjectChanges(eventId: event.id)
        #expect(changes.count == 1)

        let change = changes.first!
        #expect(change.type == .insert)

        let values = change.propertyChangeValues ?? []
        #expect(values.count == 1)

        let value = values.last!
        #expect(value.value == StoredValue.date(NSDate(timeIntervalSince1970: 10).timeIntervalSinceReferenceDate))
        #expect(value.type == PropertyChangeType.attribute.rawValue)
    }

    @Test("Merging concurrent baselines with many object changes")
    func mergingConcurrentBaselinesWithManyChanges() async throws {
        PropertyChangeValue.registerTransformer()
        let baseline0 = try setup.addBaselineEvents(storeId: "123", globalCounts: [10], revisions: [10]).last!
        let baseline1 = try setup.addBaselineEvents(storeId: "234", globalCounts: [20], revisions: [10]).last!

        for _ in 0..<1000 {
            let globalIdString = ProcessInfo.processInfo.globallyUniqueString

            let globalId = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: globalIdString, nameOfEntity: "Parent")

            try setup.objectChange(globalId: globalId, valuesByKey: ["date": NSDate(timeIntervalSince1970: 10)], event: baseline0)
            try setup.objectChange(globalId: globalId, valuesByKey: ["date": NSDate(timeIntervalSince1970: 20)], event: baseline1)
        }

        try await consolidator.consolidateBaseline()

        let events = try setup.fetchStoreModEvents()
        let event = events.last!

        let changes = try setup.eventStore.fetchObjectChanges(eventId: event.id)
        #expect(changes.count == 1000)
    }

    @Test("Merging concurrent baselines merges property values")
    func mergingConcurrentBaselinesMergesPropertyValues() async throws {
        PropertyChangeValue.registerTransformer()
        let baseline0 = try setup.addBaselineEvents(storeId: "123", globalCounts: [10], revisions: [10]).last!
        let baseline1 = try setup.addBaselineEvents(storeId: "234", globalCounts: [20], revisions: [10]).last!

        let globalId = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "123", nameOfEntity: "Parent")

        try setup.objectChange(globalId: globalId, valuesByKey: ["date": NSDate(timeIntervalSince1970: 10), "strength": NSNumber(value: 5)], event: baseline0)
        try setup.objectChange(globalId: globalId, valuesByKey: ["date": NSDate(timeIntervalSince1970: 20)], event: baseline1)

        try await consolidator.consolidateBaseline()

        let events = try setup.fetchStoreModEvents()
        let event = events.last!

        let changes = try setup.eventStore.fetchObjectChanges(eventId: event.id)
        #expect(changes.count == 1)

        let change = changes.first!
        let values = change.propertyChangeValues ?? []
        #expect(values.count == 2)

        let strengthValue = values.first { $0.propertyName == "strength" }
        #expect(strengthValue?.value == StoredValue.int(5))
    }
}
