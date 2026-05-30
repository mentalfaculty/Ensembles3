import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

/// Pins the public contract that `awakeFromInsert` side-effect guards rely on:
/// the context Ensembles uses to integrate remote events reports
/// `isEnsemblesIntegrationContext == true`, and ordinary app contexts report `false`.
///
/// Background: Core Data calls `awakeFromInsert()` on objects Ensembles inserts during
/// integration, just as it does for objects the app inserts. A customer's `awakeFromInsert`
/// that stamps default content (a fresh location, timestamp, etc.) will overwrite synced
/// values unless it skips the integration context. This API is how that guard is written.
@Suite("Integration context flag", .serialized)
@MainActor
struct IntegrationContextFlagTests {

    @Test("A plain app context is not the Ensembles integration context")
    func plainContext_isNotIntegrationContext() {
        let ctx = NSManagedObjectContext(.mainQueue)
        #expect(ctx.isEnsemblesIntegrationContext == false)
    }

    @Test("Setting the key flips the flag (public accessor reads the documented key)")
    func keyControlsFlag() {
        let ctx = NSManagedObjectContext(.mainQueue)
        ctx.userInfo[NSManagedObjectContext.ensemblesIntegrationContextKey] = true
        #expect(ctx.isEnsemblesIntegrationContext == true)
    }

    @Test("The integrator's own context is flagged after a merge")
    func integratorContext_isFlagged() async throws {
        let stack = try IntegratorTestStack()
        stack.integrator.performIntegrabilityChecks = false

        // A minimal remote insert, built the same way the other integrator tests do.
        let modEvent = try stack.setup.addModEvent(store: "store2", revision: 0, timestamp: 123)
        let globalId = try stack.setup.addGlobalIdentifier("parentFlag", entity: "Parent")
        let nameChange = stack.setup.attributeChange(name: "name", value: "parentFlag" as NSString)
        try stack.setup.addObjectChange(type: .insert, globalIdentifier: globalId, event: modEvent,
                                        propertyChanges: [nameChange.toStoredPropertyChange()])

        try await stack.mergeEvents()

        let ctx = try #require(stack.integrator.managedObjectContext,
                               "integrator did not create a context")
        #expect(ctx.isEnsemblesIntegrationContext == true,
                "Ensembles integration context must be identifiable so awakeFromInsert guards work")
    }
}
