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

    @Test("A second suspend while already paused does not strand the sync")
    func doubleSuspendThenResumeUnblocks() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("erin", forKey: "name")
        stack.save(stack.context1)
        try await stack.syncEnsemble(stack.ensemble1)

        // Suspend, let the sync reach a checkpoint and pause there.
        stack.ensemble2.suspendSync()
        let finished = AtomicFlag(false)
        let syncTask = Task {
            try await stack.syncEnsemble(stack.ensemble2)
            finished.value = true
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!finished.value, "sync should be paused here")

        // A second expiration handler fires before the app ever resumed.
        stack.ensemble2.suspendSync()
        try await Task.sleep(for: .milliseconds(100))

        // One resume must release the paused sync.
        stack.ensemble2.resumeSync()

        let deadline = ContinuousClock.now + .seconds(5)
        while !finished.value && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(finished.value, "sync stayed paused after resumeSync()")
        if finished.value {
            let result = await syncTask.result
            #expect(throws: Never.self) { try result.get() }
        }

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
    }

    @Test("Repeated instant suspend/resume pairs leave the ensemble usable")
    func immediateResumeAfterSuspend() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("frank", forKey: "name")
        stack.save(stack.context1)
        try await stack.syncEnsemble(stack.ensemble1)

        // Background expiry then an instant foreground, repeated.
        for _ in 0..<20 {
            stack.ensemble2.suspendSync()
            stack.ensemble2.resumeSync()
        }
        #expect(!stack.ensemble2.isSyncSuspended)

        // A later real pause/resume cycle must still work.
        stack.ensemble2.suspendSync()
        let finished = AtomicFlag(false)
        let syncTask = Task {
            try await stack.syncEnsemble(stack.ensemble2)
            finished.value = true
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!finished.value, "sync should be paused here")
        stack.ensemble2.resumeSync()

        let deadline = ContinuousClock.now + .seconds(5)
        while !finished.value && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(finished.value, "sync stayed paused after resumeSync()")
        if finished.value {
            let result = await syncTask.result
            #expect(throws: Never.self) { try result.get() }
        }

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
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

/// Direct tests of the suspender, with no sync stack and no timing guesses.
@Suite("SyncSuspender unit")
struct SyncSuspenderUnitTests {

    /// Spin until `count` checkpoints are parked.
    private func waitForWaiters(_ count: Int, on suspender: SyncSuspender) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while suspender.waiterCount < count && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(suspender.waiterCount == count)
    }

    @Test("Checkpoint passes straight through when not suspended")
    func passThrough() async throws {
        let suspender = SyncSuspender()
        try await suspender.checkpointIfSuspended()
        #expect(suspender.waiterCount == 0)
    }

    @Test("Checkpoint parks while suspended and is released by resume")
    func parksAndReleases() async throws {
        let suspender = SyncSuspender()
        suspender.suspend()
        let task = Task { try await suspender.checkpointIfSuspended() }
        try await waitForWaiters(1, on: suspender)
        suspender.resume()
        try await task.value
        #expect(suspender.waiterCount == 0)
        #expect(!suspender.isSuspended)
    }

    @Test("A second suspend while a checkpoint is parked does not orphan it")
    func doubleSuspend() async throws {
        let suspender = SyncSuspender()
        suspender.suspend()
        let task = Task { try await suspender.checkpointIfSuspended() }
        try await waitForWaiters(1, on: suspender)
        suspender.suspend()
        #expect(suspender.waiterCount == 1)
        suspender.resume()
        try await task.value
    }

    @Test("Resume before any checkpoint arrives leaves nothing suspended")
    func resumeBeforeCheckpoint() async throws {
        let suspender = SyncSuspender()
        suspender.suspend()
        suspender.resume()
        #expect(!suspender.isSuspended)
        try await suspender.checkpointIfSuspended()
        #expect(suspender.waiterCount == 0)
    }

    @Test("One resume releases every parked checkpoint")
    func releasesAllWaiters() async throws {
        let suspender = SyncSuspender()
        suspender.suspend()
        let tasks = (0..<3).map { _ in Task { try await suspender.checkpointIfSuspended() } }
        try await waitForWaiters(3, on: suspender)
        suspender.resume()
        for task in tasks { try await task.value }
        #expect(suspender.waiterCount == 0)
    }

    @Test("A cancelled task does not park at a checkpoint")
    func cancelledTaskDoesNotPark() async throws {
        let suspender = SyncSuspender()
        suspender.suspend()
        let task = Task {
            try await Task.sleep(for: .seconds(10))
            try await suspender.checkpointIfSuspended()
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(suspender.waiterCount == 0)
    }
}
