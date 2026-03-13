import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

extension SyncTests {
@Suite("BaseliningSync", .serialized)
@MainActor
struct BaseliningSyncTests {

    let stack: SyncTestStack

    init() {
        stack = SyncTestStack()
    }

    @Test("Cloud baseline uniqueness with no initial data")
    func cloudBaselineUniquenessWithNoInitialData() async throws {
        try await stack.attachStores()
        try await stack.syncChanges()

        let baselineFiles = stack.contentsOfDirectory(atPath: stack.cloudBaselinesDir())
        #expect(baselineFiles.count == 1)

        let eventFiles = stack.contentsOfDirectory(atPath: stack.cloudEventsDir())
        #expect(eventFiles.count > 0)
    }

    @Test("Baseline consolidation")
    func baselineConsolidation() async throws {
        let parentOnDevice1 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parentOnDevice1.setValue("bob", forKey: "name")
        stack.save(stack.context1)

        let parentOnDevice2 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context2)
        parentOnDevice2.setValue("john", forKey: "name")
        stack.save(stack.context2)

        try await stack.attachStores()

        var baselineFiles = stack.contentsOfDirectory(atPath: stack.cloudBaselinesDir())
        #expect(baselineFiles.count == 0)

        try await stack.syncEnsemble(stack.ensemble1)
        baselineFiles = stack.contentsOfDirectory(atPath: stack.cloudBaselinesDir())
        #expect(baselineFiles.count == 1)

        try await stack.syncEnsemble(stack.ensemble2)
        baselineFiles = stack.contentsOfDirectory(atPath: stack.cloudBaselinesDir())
        #expect(baselineFiles.count == 1)

        try await stack.syncEnsemble(stack.ensemble1)

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents1 = try stack.context1.fetch(fetch)
        #expect(parents1.count == 2)
        let parents2 = try stack.context2.fetch(fetch)
        #expect(parents2.count == 2)
    }

    @Test("Rebasing is triggered")
    func rebasingIsTriggered() async throws {
        try await stack.attachStores()
        try await stack.syncEnsemble(stack.ensemble1)

        for _ in 0..<100 {
            let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
            parent.setValue("bob", forKey: "name")
        }
        stack.save(stack.context1)

        // Generate enough updates to trigger a rebase
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents = try stack.context1.fetch(fetch)
        var count = 0
        for _ in 0..<11 {
            for parent in parents {
                parent.setValue("tom\(count)", forKey: "name")
                count += 1
            }
            stack.save(stack.context1)
        }

        try await stack.syncEnsemble(stack.ensemble1)
        try await stack.syncEnsemble(stack.ensemble2)

        let parentsIn2 = try stack.context2.fetch(fetch)
        #expect(parentsIn2.count == 100)
    }

    @Test("Rebasing with local store left behind")
    func rebasingWithLocalStoreLeftBehind() async throws {
        try await stack.attachStores()
        try await stack.syncChanges()

        NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context2)
        stack.save(stack.context2)
        try await stack.syncEnsemble(stack.ensemble2)

        try await stack.rebaseEnsemble(stack.ensemble1)

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents1 = try stack.context1.fetch(fetch)
        let parents2 = try stack.context2.fetch(fetch)
        #expect(parents1.count == parents2.count)
    }

    @Test("Consolidating baselines after rebasing causes full integration if store left behind")
    func consolidatingBaselinesAfterRebasing() async throws {
        try await stack.attachStores()
        try await stack.syncChanges()

        NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context2)
        stack.save(stack.context2)
        try await stack.syncEnsemble(stack.ensemble2)

        NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        stack.save(stack.context1)

        try await stack.rebaseEnsemble(stack.ensemble1)
        try await stack.syncEnsemble(stack.ensemble2)

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents1 = try stack.context1.fetch(fetch)
        let parents2 = try stack.context2.fetch(fetch)
        #expect(parents1.count == parents2.count)
    }

    @Test("Concurrent rebasing")
    func concurrentRebasing() async throws {
        try await stack.attachStores()
        try await stack.syncChanges()

        for _ in 0..<50 { NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context2) }
        stack.save(stack.context2)

        for _ in 0..<20 { NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1) }
        stack.save(stack.context1)
        for _ in 0..<20 { NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1) }
        stack.save(stack.context1)

        // Concurrent rebase — one or both may fail due to cloud contention,
        // which is expected. A follow-up sync should recover consistency.
        async let sync1: () = stack.ensemble1.sync(options: .forceRebase)
        async let sync2: () = stack.ensemble2.sync(options: .forceRebase)
        let _ = try? await (sync1, sync2)

        try await stack.syncChanges()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents1 = try stack.context1.fetch(fetch)
        let parents2 = try stack.context2.fetch(fetch)
        #expect(parents1.count == 90)
        #expect(parents1.count == parents2.count)
    }

    @Test("Random rebasing")
    func randomRebasing() async throws {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        try await stack.attachStores()
        try await stack.syncChanges()

        srand48(55557)

        for _ in 0..<20 {
            if Int.random(in: 0...1) == 0 {
                NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context2)
                stack.save(stack.context2)
            }
            if Int.random(in: 0...1) == 0 {
                NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
                stack.save(stack.context1)
            }
            if Int.random(in: 0...1) == 0 { try await stack.rebaseEnsemble(stack.ensemble1) }
            if Int.random(in: 0...1) == 0 {
                NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context2)
                stack.save(stack.context2)
            }
            if Int.random(in: 0...1) == 0 {
                NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
                stack.save(stack.context1)
            }
            if Int.random(in: 0...1) == 0 { try await stack.rebaseEnsemble(stack.ensemble2) }
            if Int.random(in: 0...1) == 0 {
                if let parent = (try? stack.context1.fetch(fetch))?.last {
                    stack.context1.delete(parent)
                    stack.save(stack.context1)
                }
            }
            if Int.random(in: 0...1) == 0 {
                if let parent = (try? stack.context2.fetch(fetch))?.last {
                    stack.context2.delete(parent)
                    stack.save(stack.context2)
                }
            }
        }

        try await stack.syncChanges()

        let parents1 = try stack.context1.fetch(fetch)
        let parents2 = try stack.context2.fetch(fetch)
        #expect(parents1.count == parents2.count)
    }

    @Test("Abandoned store returns")
    func abandonedStoreReturns() async throws {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        try await stack.attachStores()
        try await stack.syncChanges()

        for _ in 0..<100 {
            NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
            stack.save(stack.context1)
        }
        try await stack.rebaseEnsemble(stack.ensemble1)

        for _ in 0..<100 {
            NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
            stack.save(stack.context1)
        }
        try await stack.rebaseEnsemble(stack.ensemble1)

        try await stack.syncChanges()

        let parents1 = try stack.context1.fetch(fetch)
        let parents2 = try stack.context2.fetch(fetch)
        #expect(parents1.count == parents2.count)
        #expect(parents1.count == 200)
    }
}
}
