import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

/// Thread-safe boolean flag for use across task boundaries in tests.
private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool
    init(_ value: Bool) { _value = value }
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

extension SyncTests {
@Suite("SyncSuspender", .serialized)
@MainActor
struct SyncSuspenderTests {

    let stack: SyncTestStack

    init() {
        stack = SyncTestStack()
    }

    @Test("Sync completes normally without suspend")
    func syncCompletesNormally() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("alice", forKey: "name")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
        #expect(parents.first?.value(forKey: "name") as? String == "alice")
    }

    @Test("Suspended sync does not complete until resumed")
    func suspendedSyncBlocksUntilResumed() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("bob", forKey: "name")
        stack.save(stack.context1)

        // Export from device 1
        try await stack.syncEnsemble(stack.ensemble1)

        // Suspend device 2 before syncing
        stack.ensemble2.suspendSync()
        #expect(stack.ensemble2.isSyncSuspended)

        // Start sync on device 2 in a task — it should block
        let syncFinished = AtomicFlag(false)

        let syncTask = Task {
            try await stack.syncEnsemble(stack.ensemble2)
            syncFinished.value = true
        }

        // Give the sync time to reach a checkpoint and block
        try await Task.sleep(for: .milliseconds(500))

        // Sync should not have finished
        #expect(!syncFinished.value)

        // Resume and wait for completion
        stack.ensemble2.resumeSync()
        try await syncTask.value

        #expect(syncFinished.value)
        #expect(!stack.ensemble2.isSyncSuspended)

        // Verify data arrived
        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
        #expect(parents.first?.value(forKey: "name") as? String == "bob")
    }

    @Test("isSyncSuspended reflects state")
    func isSyncSuspendedReflectsState() async throws {
        let ensemble = stack.ensemble1
        #expect(!ensemble.isSyncSuspended)

        ensemble.suspendSync()
        #expect(ensemble.isSyncSuspended)

        ensemble.resumeSync()
        #expect(!ensemble.isSyncSuspended)
    }

    @Test("Resume without suspend is a no-op")
    func resumeWithoutSuspendIsNoop() async throws {
        try await stack.attachStores()

        // Resume when not suspended — should not crash
        stack.ensemble1.resumeSync()

        // Sync should still work normally
        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("charlie", forKey: "name")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
    }

    @Test("Dismantle while suspended unblocks sync")
    func dismantleWhileSuspendedUnblocks() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("dave", forKey: "name")
        stack.save(stack.context1)

        try await stack.syncEnsemble(stack.ensemble1)

        // Suspend and start sync
        stack.ensemble2.suspendSync()

        let syncTask = Task {
            try? await stack.syncEnsemble(stack.ensemble2)
        }

        // Give sync time to reach a checkpoint
        try await Task.sleep(for: .milliseconds(500))

        // Dismantle should unblock the suspended sync
        stack.ensemble2.dismantle()

        // The sync task should complete (not hang forever)
        await syncTask.value
    }

    @Test("Suspend and resume multiple times across syncs")
    func multipleSuspendResumeCycles() async throws {
        try await stack.attachStores()

        // First cycle
        let p1 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        p1.setValue("first", forKey: "name")
        stack.save(stack.context1)

        stack.ensemble1.suspendSync()
        let task1 = Task { try await stack.syncEnsemble(stack.ensemble1) }
        try await Task.sleep(for: .milliseconds(300))
        stack.ensemble1.resumeSync()
        try await task1.value

        // Second cycle — sync should still work
        let p2 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        p2.setValue("second", forKey: "name")
        stack.save(stack.context1)

        stack.ensemble1.suspendSync()
        let task2 = Task { try await stack.syncEnsemble(stack.ensemble1) }
        try await Task.sleep(for: .milliseconds(300))
        stack.ensemble1.resumeSync()
        try await task2.value

        // Verify both synced
        try await stack.syncEnsemble(stack.ensemble2)
        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 2)
    }
}
}
