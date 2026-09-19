import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

extension SyncTests {
@Suite("RebaseMetrics", .serialized)
@MainActor
struct RebaseMetricsTests {

    let stack: SyncTestStack

    init() {
        stack = SyncTestStack()
    }

    @Test("Metrics are refused while detached")
    func metricsRefusedWhileDetached() async throws {
        await #expect(throws: EnsembleError.disallowedStateChange) {
            _ = try await stack.ensemble1.rebaseMetrics()
        }
    }

    @Test("A freshly attached store does not recommend a rebase")
    func freshStoreDoesNotRecommendRebase() async throws {
        stack.insertParent(name: "bob", in: stack.context1)
        stack.save(stack.context1)
        try await stack.attachStores()

        let metrics = try await stack.ensemble1.rebaseMetrics()
        #expect(metrics.eventCount == 1, "only the baseline")
        #expect(metrics.objectChangeCount == 1)
        #expect(metrics.estimatedCompaction >= 0 && metrics.estimatedCompaction <= 1)
        #expect(!metrics.isRebaseRecommended)
    }

    /// The app-driven pattern: suppress rebasing in normal use, watch the metrics, and
    /// force a rebase when they call for one. An insert-only history scores no
    /// compaction at all, so the recommendation has to come from the event count.
    @Test("Insert-only history is recommended by event count, and a forced rebase clears it")
    func insertOnlyHistoryRecommendedByEventCount() async throws {
        try await stack.attachStores()

        for i in 0..<101 {
            stack.insertParent(name: "reading\(i)", in: stack.context1)
            stack.save(stack.context1)
        }
        try await stack.syncEnsembleAndSuppressRebase(stack.ensemble1)

        let before = try await stack.ensemble1.rebaseMetrics()
        #expect(before.eventCount > 100)
        #expect(before.estimatedCompaction < 0.5, "inserts alone recover nothing")
        #expect(before.isRebaseRecommended)

        // Reading the metrics starts nothing.
        let again = try await stack.ensemble1.rebaseMetrics()
        #expect(again == before)

        try await stack.rebaseEnsemble(stack.ensemble1)

        let after = try await stack.ensemble1.rebaseMetrics()
        #expect(after.eventCount < before.eventCount)
        #expect(!after.isRebaseRecommended)
        #expect(stack.fetchParents(in: stack.context1).count == 101)
    }
}
}
