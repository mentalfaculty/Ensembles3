import Testing
import Foundation
@_spi(Testing) import EnsemblesSupabase
@_spi(Testing) import Ensembles

@Suite("SupabaseCloudFileSystemTests")
struct SupabaseCloudFileSystemTests {

    // MARK: - Token Response Parsing

    @Test("Decode GoTrue token response into StoredCredential")
    func decodeTokenResponse() throws {
        let json = """
        {
            "access_token": "header.payload.sig",
            "expires_in": 3600,
            "refresh_token": "rt-xyz",
            "user": { "id": "11111111-2222-3333-4444-555555555555", "email": "user@example.com" }
        }
        """.data(using: .utf8)!

        let now = Date(timeIntervalSince1970: 1_000_000)
        let cred = try SupabaseAuthenticator.decodeTokenResponse(json, at: now)

        #expect(cred.accessToken == "header.payload.sig")
        #expect(cred.refreshToken == "rt-xyz")
        #expect(cred.userID == "11111111-2222-3333-4444-555555555555")
        #expect(cred.email == "user@example.com")
        // expires_in 3600 minus 60s safety margin
        #expect(cred.expiresAt == now.addingTimeInterval(3600 - 60))
    }

    // MARK: - Auth error mapping

    @Test("400 maps to authenticationFailure")
    func authHTTPError400() {
        #expect(SupabaseAuthenticator.mapAuthHTTPError(statusCode: 400) == .authenticationFailure)
    }

    @Test("401 maps to authenticationFailure")
    func authHTTPError401() {
        #expect(SupabaseAuthenticator.mapAuthHTTPError(statusCode: 401) == .authenticationFailure)
    }

    @Test("422 maps to authenticationFailure")
    func authHTTPError422() {
        #expect(SupabaseAuthenticator.mapAuthHTTPError(statusCode: 422) == .authenticationFailure)
    }

    @Test("500 maps to serverError")
    func authHTTPError500() {
        #expect(SupabaseAuthenticator.mapAuthHTTPError(statusCode: 500) == .serverError)
    }

    // MARK: - Refresh decision logic

    /// Mirrors `SupabaseAuthenticator.validAccessToken`'s decision branch.
    private enum RefreshDecision { case useCached, refresh, throwUnauthorized }

    private func refreshDecision(
        credential: SupabaseAuthenticator.StoredCredential?,
        now: Date
    ) -> RefreshDecision {
        guard let c = credential else { return .throwUnauthorized }
        if c.expiresAt > now.addingTimeInterval(30) { return .useCached }
        return .refresh
    }

    @Test("No credential → throwUnauthorized")
    func refreshDecisionNoCredential() {
        #expect(refreshDecision(credential: nil, now: Date()) == .throwUnauthorized)
    }

    @Test("Token comfortably in the future → useCached")
    func refreshDecisionFresh() {
        let now = Date()
        let cred = SupabaseAuthenticator.StoredCredential(
            accessToken: "a", refreshToken: "r",
            expiresAt: now.addingTimeInterval(600),
            userID: "u", email: nil
        )
        #expect(refreshDecision(credential: cred, now: now) == .useCached)
    }

    @Test("Token within 30s of expiry → refresh")
    func refreshDecisionAtBoundary() {
        let now = Date()
        let cred = SupabaseAuthenticator.StoredCredential(
            accessToken: "a", refreshToken: "r",
            expiresAt: now.addingTimeInterval(20),
            userID: "u", email: nil
        )
        #expect(refreshDecision(credential: cred, now: now) == .refresh)
    }

    @Test("Already-expired token → refresh")
    func refreshDecisionExpired() {
        let now = Date()
        let cred = SupabaseAuthenticator.StoredCredential(
            accessToken: "a", refreshToken: "r",
            expiresAt: now.addingTimeInterval(-100),
            userID: "u", email: nil
        )
        #expect(refreshDecision(credential: cred, now: now) == .refresh)
    }

    // MARK: - Path prefixing

    @Test("cloudKey strips leading slash in static-JWT mode")
    func cloudKeyStaticStripsSlash() async throws {
        let fs = SupabaseCloudFileSystem(
            configuration: .init(
                projectURL: URL(string: "https://example.supabase.co")!,
                anonKey: "key",
                bucket: "ensembles"
            ),
            accessToken: "jwt"
        )
        let key = try await fs._cloudKey(for: "/events/a.json")
        #expect(key == "events/a.json")
    }

    @Test("cloudKey leaves path unchanged in static-JWT mode if no leading slash")
    func cloudKeyStaticNoSlash() async throws {
        let fs = SupabaseCloudFileSystem(
            configuration: .init(
                projectURL: URL(string: "https://example.supabase.co")!,
                anonKey: "key",
                bucket: "ensembles"
            ),
            accessToken: "jwt"
        )
        let key = try await fs._cloudKey(for: "events/a.json")
        #expect(key == "events/a.json")
    }

    @Test("cloudKey prepends userID in authenticator mode")
    func cloudKeyAuthenticatorPrefixes() async throws {
        let auth = SupabaseAuthenticator(configuration: .init(
            projectURL: URL(string: "https://example.supabase.co")!,
            anonKey: "key"
        ))
        try await auth.acceptTokenResponse(data: """
        {
            "access_token": "at", "refresh_token": "rt", "expires_in": 3600,
            "user": { "id": "11111111-2222-3333-4444-555555555555", "email": "u@e.com" }
        }
        """.data(using: .utf8)!)

        let fs = SupabaseCloudFileSystem(
            configuration: .init(
                projectURL: URL(string: "https://example.supabase.co")!,
                anonKey: "key",
                bucket: "ensembles"
            ),
            authenticator: auth
        )
        let key = try await fs._cloudKey(for: "/events/a.json")
        #expect(key == "11111111-2222-3333-4444-555555555555/events/a.json")
        await auth.signOut()
    }

    @Test("cloudKey throws when authenticator has no userID")
    func cloudKeyAuthenticatorNoUserThrows() async throws {
        let auth = SupabaseAuthenticator(configuration: .init(
            projectURL: URL(string: "https://nouser.example.supabase.co")!,
            anonKey: "key"
        ))
        let fs = SupabaseCloudFileSystem(
            configuration: .init(
                projectURL: URL(string: "https://nouser.example.supabase.co")!,
                anonKey: "key",
                bucket: "ensembles"
            ),
            authenticator: auth
        )
        await #expect(throws: EnsembleError.self) {
            _ = try await fs._cloudKey(for: "events/a.json")
        }
    }

    // MARK: - Storage HTTP error mapping

    @Test("Storage 401 maps to authenticationFailure")
    func storageHTTPError401() {
        #expect(SupabaseCloudFileSystem.mapHTTPError(statusCode: 401) == .authenticationFailure)
    }

    @Test("Storage 403 maps to authenticationFailure")
    func storageHTTPError403() {
        #expect(SupabaseCloudFileSystem.mapHTTPError(statusCode: 403) == .authenticationFailure)
    }

    @Test("Storage 404 maps to fileAccessFailed")
    func storageHTTPError404() {
        #expect(SupabaseCloudFileSystem.mapHTTPError(statusCode: 404) == .fileAccessFailed)
    }

    @Test("Storage 409 maps to fileAccessFailed")
    func storageHTTPError409() {
        #expect(SupabaseCloudFileSystem.mapHTTPError(statusCode: 409) == .fileAccessFailed)
    }

    @Test("Storage 413 maps to fileAccessFailed")
    func storageHTTPError413() {
        #expect(SupabaseCloudFileSystem.mapHTTPError(statusCode: 413) == .fileAccessFailed)
    }

    @Test("Storage 429 maps to serverError")
    func storageHTTPError429() {
        #expect(SupabaseCloudFileSystem.mapHTTPError(statusCode: 429) == .serverError)
    }

    @Test("Storage 500 maps to serverError")
    func storageHTTPError500() {
        #expect(SupabaseCloudFileSystem.mapHTTPError(statusCode: 500) == .serverError)
    }

    // MARK: - List response parsing

    @Test("Parse list response with mixed files and prefixes")
    func parseListResponseMixed() {
        let entries: [[String: Any]] = [
            ["name": "snapshot.json", "metadata": ["size": 1024] as [String: Any]],
            ["name": "baseline.json", "metadata": ["size": 512] as [String: Any]],
            // Folder entries from Supabase have a null id and no metadata size.
            ["name": "events", "id": NSNull()],
        ]
        let items = SupabaseCloudFileSystem.parseList(
            entries: entries,
            requestPrefix: "11111111/MyStore"
        )
        let names = items.map(\.name).sorted()
        #expect(names == ["baseline.json", "events", "snapshot.json"])

        let events = items.first { $0.name == "events" }
        #expect(events is CloudDirectory)
        let snapshot = items.first { $0.name == "snapshot.json" } as? CloudFile
        #expect(snapshot?.size == 1024)
        #expect(snapshot?.path == "11111111/MyStore/snapshot.json")
    }

    @Test("Parse empty list response")
    func parseListResponseEmpty() {
        let items = SupabaseCloudFileSystem.parseList(entries: [], requestPrefix: "anything")
        #expect(items.isEmpty)
    }

    // MARK: - Concurrency smoke

    @Test("Concurrent validAccessToken calls don't crash or deadlock on expired credential")
    func concurrentValidAccessTokenOnExpiredCredential() async throws {
        let auth = SupabaseAuthenticator(configuration: .init(
            projectURL: URL(string: "https://concurrent.example.supabase.co")!,
            anonKey: "key"
        ))
        // Seed an *already-expired* credential. validAccessToken will try to refresh,
        // which will fail at the network layer (no server), but the single-flight
        // path must serialise correctly — all 10 callers must observe the same
        // outcome (a thrown error) without deadlock.
        let expired = """
        {
            "access_token": "old", "refresh_token": "rt", "expires_in": -3600,
            "user": { "id": "deadbeef", "email": "u@e.com" }
        }
        """.data(using: .utf8)!
        try await auth.acceptTokenResponse(data: expired)

        await withTaskGroup(of: Error?.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    do {
                        _ = try await auth.validAccessToken()
                        return nil
                    } catch {
                        return error
                    }
                }
            }
            var errorCount = 0
            for await result in group {
                if result != nil { errorCount += 1 }
            }
            // All ten must throw (no network) — and the test must not hang.
            #expect(errorCount == 10)
        }

        // Clean up any persisted Keychain artefact this auth instance may have written.
        await auth.signOut()
    }
}
