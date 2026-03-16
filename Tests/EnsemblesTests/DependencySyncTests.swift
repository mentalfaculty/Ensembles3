import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

extension SyncTests {
@Suite("DependencySync", .serialized)
@MainActor
struct DependencySyncTests {

    let stack: SyncTestStack

    init() {
        stack = SyncTestStack()
    }

    @Test("Missing data file prevents event merge")
    func missingDataFilePreventsEventMerge() async throws {
        try await stack.attachStores()

        let data = Data(count: 10001)
        let parent = stack.insertParent(name: "bob", in: stack.context1)
        parent.setValue(data, forKey: "data")
        stack.save(stack.context1)

        try await stack.syncEnsemble(stack.ensemble1) // Exports data file

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        var parentsInContext2 = try stack.context2.fetch(fetch)
        #expect(parentsInContext2.count == 0)

        // Remove data file to fake it missing
        let dataRoot = (stack.cloudRootDir as NSString).appendingPathComponent("com.ensembles.synctest/data")
        try? FileManager.default.removeItem(atPath: dataRoot)
        try FileManager.default.createDirectory(atPath: dataRoot, withIntermediateDirectories: false)

        try await stack.syncEnsemble(stack.ensemble2)

        parentsInContext2 = try stack.context2.fetch(fetch)
        #expect(parentsInContext2.count == 0)

        try await stack.syncEnsemble(stack.ensemble1)
        try await stack.syncEnsemble(stack.ensemble2)

        parentsInContext2 = try stack.context2.fetch(fetch)
        #expect(parentsInContext2.count == 1)

        let parent1InContext2 = parentsInContext2.last!
        #expect(parent1InContext2.value(forKey: "data") != nil)
    }

    @Test("Missing event invalidates future events from device")
    func missingEventInvalidatesFutureEventsFromDevice() async throws {
        try await stack.attachStores()

        stack.insertParent(in: stack.context1)
        stack.save(stack.context1)
        try await stack.syncEnsemble(stack.ensemble1)

        let eventsRoot = (stack.cloudRootDir as NSString).appendingPathComponent("com.ensembles.synctest/events")
        let eventFiles = stack.contentsOfDirectory(atPath: eventsRoot)
        let firstEventFile = (eventsRoot as NSString).appendingPathComponent(eventFiles.last!)

        stack.insertParent(in: stack.context1)
        stack.save(stack.context1)
        try await stack.syncEnsemble(stack.ensemble1)

        // Remove first cloud event file
        try FileManager.default.removeItem(atPath: firstEventFile)

        try await stack.syncEnsemble(stack.ensemble2)

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        var parentsInContext2 = try stack.context2.fetch(fetch)
        #expect(parentsInContext2.count == 0)

        try await stack.syncChanges()

        parentsInContext2 = try stack.context2.fetch(fetch)
        #expect(parentsInContext2.count == 2)
    }

    @Test("Baseline with missing data files is ignored")
    func baselineWithMissingDataFilesIsIgnored() async throws {
        let data = Data(count: 10001)
        let parent1 = stack.insertParent(name: "bob", in: stack.context1)
        parent1.setValue(data, forKey: "data")
        stack.save(stack.context1)

        stack.insertChild(name: "peter", in: stack.context2)
        stack.save(stack.context2)

        try await stack.attachStores()

        // Add one save event
        stack.insertParent(name: "terry", in: stack.context1)
        stack.save(stack.context1)

        try await stack.syncEnsemble(stack.ensemble1) // Exports data file

        // Remove data file to fake it missing
        let dataRoot = (stack.cloudRootDir as NSString).appendingPathComponent("com.ensembles.synctest/data")
        try? FileManager.default.removeItem(atPath: dataRoot)
        try FileManager.default.createDirectory(atPath: dataRoot, withIntermediateDirectories: false)

        try await stack.syncEnsemble(stack.ensemble2) // Should ignore baseline due to missing data file

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        var parentsInContext2 = try stack.context2.fetch(fetch)
        #expect(parentsInContext2.count == 0)

        // Reupload
        try await stack.syncEnsemble(stack.ensemble1)

        let childFetch = NSFetchRequest<NSManagedObject>(entityName: "Child")
        let childrenInContext1 = try stack.context1.fetch(childFetch)
        #expect(childrenInContext1.count == 1)

        // Merge the full data now
        try await stack.syncEnsemble(stack.ensemble2)

        parentsInContext2 = try stack.context2.fetch(fetch)
        #expect(parentsInContext2.count == 2)
    }
}
}
