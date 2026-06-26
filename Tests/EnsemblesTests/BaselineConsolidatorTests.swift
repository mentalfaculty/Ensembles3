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
        // No non-empty *other* baseline was merged in (only an empty placeholder),
        // so the merged baseline keeps its identifier. Renaming here is the beta.12
        // wipe regression.
        #expect(event.uniqueIdentifier == nonEmptyUniqueID)
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
        // Only an empty placeholder baseline was merged in, so the surviving
        // baseline keeps its identifier (matches Ensembles 2).
        #expect(event.uniqueIdentifier == mergedBaselineID)
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

    /// When two baselines hold the same object and the object references an
    /// external data file (e.g. an image), consolidating them must keep the
    /// data_files reference on the surviving merged change so the file is not
    /// garbage-collected. Regression test for images disappearing after a
    /// baseline consolidation.
    @Test("Consolidating preserves external data file references")
    func consolidatingPreservesExternalDataFiles() async throws {
        PropertyChangeValue.registerTransformer()
        let baseline0 = try setup.addBaselineEvents(storeId: "123", globalCounts: [10], revisions: [10]).last!
        let baseline1 = try setup.addBaselineEvents(storeId: "234", globalCounts: [20], revisions: [10]).last!

        let globalId = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "123", nameOfEntity: "Parent")

        // Both baselines carry a shared attribute so the object change is merged
        // (the if-branch), and each baseline references a distinct external data
        // file under its own property name so both must survive the merge.
        let imageData0 = Data("IMAGE-BASELINE-0".utf8)
        let filename0 = try #require(setup.eventStore.storeData(inFile: imageData0))
        var imageChange0 = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "imageA")
        imageChange0.filename = filename0
        let shared0 = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "name", value: .string("zero"))
        try setup.eventStore.insertObjectChange(type: .insert, nameOfEntity: "Parent", eventId: baseline0.id, globalIdentifierId: globalId.id, propertyChanges: [shared0, imageChange0])

        let imageData1 = Data("IMAGE-BASELINE-1".utf8)
        let filename1 = try #require(setup.eventStore.storeData(inFile: imageData1))
        var imageChange1 = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "imageB")
        imageChange1.filename = filename1
        let shared1 = StoredPropertyChange(type: PropertyChangeType.attribute.rawValue, propertyName: "name", value: .string("one"))
        try setup.eventStore.insertObjectChange(type: .insert, nameOfEntity: "Parent", eventId: baseline1.id, globalIdentifierId: globalId.id, propertyChanges: [shared1, imageChange1])

        try await consolidator.consolidateBaseline()

        let event = try #require(try setup.fetchStoreModEvents().last)
        let changes = try setup.eventStore.fetchObjectChanges(eventId: event.id)
        #expect(changes.count == 1)
        let mergedChange = try #require(changes.first)

        // Both data files must be referenced by the merged change...
        let referenced = Set(try setup.eventStore.fetchDataFiles(objectChangeId: mergedChange.id).map(\.filename))
        #expect(referenced.contains(filename0))
        #expect(referenced.contains(filename1))

        // ...so the cleanup pass must leave both on-disk files intact.
        try setup.eventStore.removeUnreferencedDataFiles()
        #expect(setup.eventStore.data(forFile: filename0) != nil)
        #expect(setup.eventStore.data(forFile: filename1) != nil)
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

    // MARK: - Baseline Identifier Stability (beta.12 wipe regression)

    @Test("Merging a non-empty baseline with an empty placeholder keeps the non-empty identifier")
    func mergingNonEmptyWithEmptyKeepsIdentifier() async throws {
        // Regression for the beta.12 E2->E3 migration wipe. The merged baseline must
        // only be re-identified when a non-empty *other* baseline was actually merged
        // in. Renaming it whenever more than one baseline exists (including the common
        // real-baseline + empty-placeholder case) desyncs the local baseline id from
        // the cloud copy, causing the device to perpetually re-import its own baseline
        // as type .baselineMissingDependencies — which the consolidator then refuses to
        // promote — eventually stranding the store with no usable baseline and driving
        // a full-integration wipe.
        PropertyChangeValue.registerTransformer()
        let nonEmptyBaseline = try setup.addBaselineEvents(storeId: "123", globalCounts: [2], revisions: [2]).last!
        try setup.addBaselineEvents(storeId: "234", globalCounts: [0], revisions: [0])

        let globalId = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "123", nameOfEntity: "Parent")
        try setup.objectChange(globalId: globalId, valuesByKey: ["date": NSDate(timeIntervalSince1970: 10)], event: nonEmptyBaseline)

        let originalUniqueID = nonEmptyBaseline.uniqueIdentifier

        try await consolidator.consolidateBaseline()

        let events = try setup.fetchStoreModEvents()
        #expect(events.count == 1)
        #expect(events.last?.uniqueIdentifier == originalUniqueID)
    }

    @Test("A re-imported baseline produced by the local store is still promoted")
    func reimportedLocallyProducedBaselineIsPromoted() async throws {
        // Defense-in-depth for the stuck-sync regression. The consolidator skips
        // dependency-checking and promotion of baselines "created locally" (whose
        // event-revision store id matches this store's). But a baseline IMPORTED
        // from the cloud arrives as `.baselineMissingDependencies` (type 400) — and
        // if it was originally produced under this store's own id, the skip fires
        // and it is never promoted to `.baseline` (type 100). It then stays
        // invisible to `fetchBaselineEvent()`, so integration reports nothing
        // integrable and sync stalls forever. A type-400 baseline must always be
        // dependency-checked and promoted, regardless of which store produced it.
        let baseline = try setup.eventStore.insertEvent(
            uniqueIdentifier: ProcessInfo.processInfo.globallyUniqueString,
            type: .baselineMissingDependencies,
            timestamp: 10,
            globalCount: 0,
            modelVersion: "DEFAULT"
        )
        // Event-revision store id == this store's own id — the customer's situation,
        // where the device re-imports a baseline it produced on a prior run.
        try setup.eventStore.insertRevision(
            persistentStoreIdentifier: setup.persistentStoreIdentifier,
            revisionNumber: 0,
            eventId: baseline.id,
            isEventRevision: true
        )

        try await consolidator.consolidateBaseline()

        let promoted = try setup.eventStore.fetchEvent(id: baseline.id)
        #expect(promoted?.type == .baseline, "Re-imported locally-produced baseline was not promoted from type 400 to type 100")
        #expect(try setup.eventStore.fetchBaselineEvent() != nil, "Promoted baseline must be visible to fetchBaselineEvent()")
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
