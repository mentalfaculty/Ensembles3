import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

extension SyncTests {
@Suite("RandomSync", .serialized)
@MainActor
struct RandomSyncTests {

    let stack: SyncTestStack

    init() {
        stack = SyncTestStack()
    }

    @Test("Random sync history")
    func randomSyncHistory() async throws {
        try await stack.attachStores()

        let data = Data(count: 10001)
        for _ in 0..<50 {
            let r1 = Int.random(in: 0..<6)
            let randBool1 = Bool.random()
            let randBool2 = Bool.random()
            switch r1 {
            case 0:
                let parent = stack.insertParent(name: UUID().uuidString, in: stack.context1)
                if randBool2 { parent.setValue(data, forKey: "data") }
                if randBool1 { stack.save(stack.context1) }
            case 1:
                let parent = stack.insertParent(name: UUID().uuidString, in: stack.context2)
                if randBool2 { parent.setValue(data, forKey: "data") }
                if randBool1 { stack.save(stack.context2) }
            case 2:
                try? await stack.syncEnsemble(stack.ensemble1)
            case 3:
                try? await stack.syncEnsemble(stack.ensemble2)
            case 4:
                try? await stack.detachEnsemble(stack.ensemble1)
                try? await stack.attachEnsemble(stack.ensemble1)
            case 5:
                let dataRoot = (stack.cloudRootDir as NSString).appendingPathComponent("com.ensembles.synctest/data")
                try? FileManager.default.removeItem(atPath: dataRoot)
                try? FileManager.default.createDirectory(atPath: dataRoot, withIntermediateDirectories: false)
            default:
                break
            }
        }

        stack.save(stack.context1)
        stack.save(stack.context2)
        try await stack.syncChanges()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents1 = try stack.context1.fetch(fetch)
        let parents2 = try stack.context2.fetch(fetch)
        #expect(parents1.count == parents2.count)
    }
}
}
