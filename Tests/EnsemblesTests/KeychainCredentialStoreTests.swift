import Testing
import Foundation
@_spi(Auth) import Ensembles

@Suite("KeychainCredentialStoreTests")
struct KeychainCredentialStoreTests {

    /// Builds a service name that is unique per-test-invocation so different
    /// tests can't collide on the shared system Keychain.
    private func uniqueService(_ tag: String = #function) -> String {
        "com.ensembles.tests.keychain.\(tag).\(UUID().uuidString)"
    }

    private struct TokenBlob: Codable, Equatable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    @Test("load returns nil when no entry exists")
    func loadReturnsNilWhenAbsent() {
        let store = KeychainCredentialStore<TokenBlob>(service: uniqueService())
        #expect(store.load() == nil)
    }

    @Test("save then load round-trips a credential")
    func saveLoadRoundTrip() {
        let store = KeychainCredentialStore<TokenBlob>(service: uniqueService())
        let cred = TokenBlob(
            accessToken: "at-abc",
            refreshToken: "rt-xyz",
            expiresAt: Date(timeIntervalSince1970: 1_234_567_890)
        )
        defer { store.delete() }

        store.save(cred)
        let loaded = store.load()
        #expect(loaded == cred)
    }

    @Test("save replaces existing entry under the same service")
    func saveReplacesExisting() {
        let store = KeychainCredentialStore<TokenBlob>(service: uniqueService())
        defer { store.delete() }

        let first = TokenBlob(accessToken: "first", refreshToken: "r1", expiresAt: .now)
        let second = TokenBlob(accessToken: "second", refreshToken: "r2", expiresAt: .now)

        store.save(first)
        store.save(second)
        #expect(store.load() == second)
    }

    @Test("delete removes the entry; subsequent load returns nil")
    func deleteRemovesEntry() {
        let store = KeychainCredentialStore<TokenBlob>(service: uniqueService())
        defer { store.delete() }

        let cred = TokenBlob(accessToken: "a", refreshToken: "r", expiresAt: .now)
        store.save(cred)
        #expect(store.load() != nil)

        store.delete()
        #expect(store.load() == nil)
    }

    @Test("Two stores with different services are isolated")
    func storesAreIsolatedByService() {
        let storeA = KeychainCredentialStore<TokenBlob>(service: uniqueService("A"))
        let storeB = KeychainCredentialStore<TokenBlob>(service: uniqueService("B"))
        defer { storeA.delete(); storeB.delete() }

        let credA = TokenBlob(accessToken: "A", refreshToken: "rA", expiresAt: .now)
        let credB = TokenBlob(accessToken: "B", refreshToken: "rB", expiresAt: .now)

        storeA.save(credA)
        storeB.save(credB)

        #expect(storeA.load()?.accessToken == "A")
        #expect(storeB.load()?.accessToken == "B")
    }
}
