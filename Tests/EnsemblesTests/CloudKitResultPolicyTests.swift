import Testing
import Foundation
import CloudKit
@_spi(Testing) import EnsemblesCloudKit
@_spi(Testing) import Ensembles

// The newer CloudKit operations report results on several channels: one overall
// result, and one result per record (or per zone). Ensembles 2 used the older
// operations, whose single completion block carried every failure, so none could be
// missed. The Swift port read only the overall channel. A save the server refused,
// reported per record, therefore looked like success, and the backend then wrote its
// own local copy of the record into the listing cache: a file the cloud never held,
// recorded as present for good. A customer's source device "published" a 9 MB
// baseline in half a second that way, and its followers stayed empty.
//
// These tests pin the decisions. They need no CloudKit account.
@Suite("CloudKitResultPolicy")
struct CloudKitResultPolicyTests {

    private let zone = CKRecordZone.ID(zoneName: "zone", ownerName: CKCurrentUserDefaultName)
    private func id(_ name: String) -> CKRecord.ID { CKRecord.ID(recordName: name, zoneID: zone) }

    private func partialFailure(_ errors: [CKRecord.ID: Error]) -> CKError {
        CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: errors as NSDictionary])
    }

    // MARK: Saves

    @Test("A save every channel confirms is confirmed")
    func allSavesConfirmed() throws {
        let a = id("a"), b = id("b")
        let confirmed = try CloudKitResultPolicy.confirmedSaves(
            requested: [a, b], overall: .success(()), perRecord: [a: .success(()), b: .success(())])
        #expect(confirmed == [a, b])
    }

    /// The customer's case. The overall channel says success; the per-record channel
    /// says the server refused the record. It must throw, and confirm nothing.
    @Test("A per-record save failure fails the upload even when the overall result is success")
    func perRecordSaveFailureIsNotSwallowed() {
        let a = id("part1"), b = id("part2")
        #expect(throws: (any Error).self) {
            try CloudKitResultPolicy.confirmedSaves(
                requested: [a, b], overall: .success(()),
                perRecord: [a: .failure(CKError(.zoneBusy)), b: .failure(CKError(.batchRequestFailed))])
        }
    }

    @Test("The same failure arriving as a partial failure on the overall channel also fails the upload")
    func partialFailureOnOverallChannelFails() {
        let a = id("a"), b = id("b")
        let overall = partialFailure([a: CKError(.quotaExceeded), b: CKError(.batchRequestFailed)])
        #expect(throws: (any Error).self) {
            try CloudKitResultPolicy.confirmedSaves(requested: [a, b], overall: .failure(overall), perRecord: [:])
        }
    }

    /// "Already exists" means the server holds a record of that name. That is the one
    /// save failure that still confirms existence, on either channel.
    @Test("serverRecordChanged is tolerated and counts as present, on either channel")
    func serverRecordChangedIsTolerated() throws {
        let a = id("a"), b = id("b")
        let viaPerRecord = try CloudKitResultPolicy.confirmedSaves(
            requested: [a, b], overall: .success(()),
            perRecord: [a: .success(()), b: .failure(CKError(.serverRecordChanged))])
        #expect(viaPerRecord == [a, b])

        let overall = partialFailure([a: CKError(.serverRecordChanged), b: CKError(.serverRecordChanged)])
        let viaOverall = try CloudKitResultPolicy.confirmedSaves(requested: [a, b], overall: .failure(overall), perRecord: [:])
        #expect(viaOverall == [a, b])
    }

    /// No word at all about a record is not confirmation. It must not be recorded as
    /// present, but silence alone is not treated as an error either: if the server did
    /// keep it, the next zone fetch reports it.
    @Test("A record no channel mentions is not confirmed")
    func unmentionedRecordIsNotConfirmed() throws {
        let a = id("a"), b = id("b")
        let confirmed = try CloudKitResultPolicy.confirmedSaves(
            requested: [a, b], overall: .success(()), perRecord: [a: .success(())])
        #expect(confirmed == [a])
    }

    @Test("An operation-level failure is rethrown as it is")
    func operationLevelFailureIsRethrown() {
        #expect(throws: CKError.self) {
            try CloudKitResultPolicy.confirmedSaves(
                requested: [id("a")], overall: .failure(CKError(.networkUnavailable)), perRecord: [:])
        }
    }

    // MARK: Deletes

    @Test("A delete of a record that is already gone counts as deleted; a refused delete fails")
    func deletes() throws {
        let a = id("a"), b = id("b")
        let gone = try CloudKitResultPolicy.confirmedDeletes(
            requested: [a, b], overall: .success(()),
            perRecord: [a: .success(()), b: .failure(CKError(.unknownItem))])
        #expect(gone == [a, b])

        #expect(throws: (any Error).self) {
            try CloudKitResultPolicy.confirmedDeletes(
                requested: [a], overall: .success(()), perRecord: [a: .failure(CKError(.zoneBusy))])
        }

        // Let through without failing the sync, as it always was, but NOT known gone.
        let unsure = try CloudKitResultPolicy.confirmedDeletes(
            requested: [a, b], overall: .success(()),
            perRecord: [a: .success(()), b: .failure(CKError(.serverRecordChanged))])
        #expect(unsure == [a])
    }

    // MARK: Fetches

    /// A failure that can pass fails the whole fetch, so the caller retries rather than
    /// being handed part of what it asked for.
    @Test("A transient per-record fetch failure fails the whole fetch")
    func transientFetchFailureFailsTheFetch() {
        let a = id("a"), b = id("b")
        #expect(throws: (any Error).self) {
            try CloudKitResultPolicy.fetchOutcome(requested: [a, b], fetched: [a], perRecordFailures: [b: CKError(.networkFailure)], overall: .success(()))
        }
        let overall = partialFailure([b: CKError(.zoneBusy)])
        #expect(throws: (any Error).self) {
            try CloudKitResultPolicy.fetchOutcome(requested: [a, b], fetched: [a], perRecordFailures: [:], overall: .failure(overall))
        }
    }

    /// A record that is not there, or that can never be read, must not fail the fetch:
    /// it would fail every sync at the same record for good. It is reported instead.
    @Test("An absent or permanently failing record is reported, and does not fail the fetch")
    func absentAndPermanentFailuresAreReportedNotThrown() throws {
        let a = id("a"), gone = id("gone"), silent = id("silent"), broken = id("broken")
        let outcome = try CloudKitResultPolicy.fetchOutcome(
            requested: [a, gone, silent, broken], fetched: [a],
            perRecordFailures: [gone: CKError(.unknownItem), broken: CKError(.assetFileNotFound)],
            overall: .success(()))
        #expect(outcome.absent == [gone, silent])
        #expect(Set(outcome.permanentFailures.keys) == [broken])
    }

    @Test("A fetch that delivers every requested record reports nothing missing")
    func fetchAllPresent() throws {
        let a = id("a"), b = id("b")
        let outcome = try CloudKitResultPolicy.fetchOutcome(requested: [a, b], fetched: [a, b], perRecordFailures: [:], overall: .success(()))
        #expect(outcome.absent.isEmpty)
        #expect(outcome.permanentFailures.isEmpty)
    }

    @Test("An operation-level fetch failure is rethrown")
    func operationLevelFetchFailure() {
        #expect(throws: CKError.self) {
            try CloudKitResultPolicy.fetchOutcome(requested: [id("a")], fetched: [], perRecordFailures: [:], overall: .failure(CKError(.networkUnavailable)))
        }
    }

    // MARK: Zone changes

    /// The per-zone channel is where CloudKit says a change token is dead. It must win
    /// over an overall success.
    @Test("A per-zone failure is surfaced even when the overall result is success")
    func perZoneFailureIsSurfaced() {
        let error = CloudKitResultPolicy.zoneChangesFailure(
            overall: .success(()), perZone: CKError(.changeTokenExpired), recordFailures: [])
        #expect((error as? CKError)?.code == .changeTokenExpired)
    }

    @Test("A changed record that failed transiently fails the zone fetch, so the token stays put")
    func transientRecordFailureFailsTheZoneFetch() {
        let error = CloudKitResultPolicy.zoneChangesFailure(
            overall: .success(()), perZone: nil, recordFailures: [CKError(.serverRejectedRequest), CKError(.serverResponseLost)])
        #expect((error as? CKError)?.code == .serverResponseLost)
    }

    /// Otherwise the token never advances, and every sync fails at that record for good.
    @Test("A changed record that fails permanently does not fail the zone fetch")
    func permanentRecordFailureDoesNotWedgeTheZoneFetch() {
        #expect(CloudKitResultPolicy.zoneChangesFailure(overall: .success(()), perZone: nil, recordFailures: [CKError(.serverRejectedRequest)]) == nil)
        #expect(CloudKitResultPolicy.zoneChangesFailure(overall: .success(()), perZone: nil, recordFailures: []) == nil)
    }

    @Test("Transient and permanent failures are told apart")
    func transientVersusPermanent() {
        for code in [CKError.Code.networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy, .serverResponseLost] {
            #expect(CloudKitResultPolicy.isPlausiblyTransient(CKError(code)), "\(code.rawValue) should be transient")
        }
        for code in [CKError.Code.unknownItem, .serverRejectedRequest, .assetFileNotFound, .invalidArguments, .permissionFailure] {
            #expect(!CloudKitResultPolicy.isPlausiblyTransient(CKError(code)), "\(code.rawValue) should be permanent")
        }
        // Not a CKError at all: unexpected, so fail loudly rather than skip.
        #expect(CloudKitResultPolicy.isPlausiblyTransient(EnsembleError.networkError))
    }

    // MARK: Files made of more than one record

    /// First-schema files are a node record plus a data record. A node whose data was
    /// not confirmed is a file with no content.
    @Test("A file counts as uploaded only when every one of its records is confirmed")
    func twoRecordFileNeedsBothConfirmed() {
        let nodeA = id("a"), dataA = id("DataFile_a"), nodeB = id("b"), dataB = id("DataFile_b"), nodeC = id("c")
        let files = [nodeA: [nodeA, dataA], nodeB: [nodeB, dataB], nodeC: [nodeC]]
        let confirmed = CloudKitResultPolicy.confirmedFiles(recordIDsByFile: files, confirmed: [nodeA, dataA, nodeB, nodeC])
        #expect(confirmed == [nodeA, nodeC])
    }

    // MARK: Dead cursor detection

    @Test("A dead change token is recognised inside a partial failure")
    func deadCursorInsidePartialFailure() {
        let wrapped = partialFailure([id("zone"): CKError(.changeTokenExpired)])
        #expect(CloudKitListingCache.errorRequiresCacheDiscard(wrapped))
        let zoneKeyed = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [zone: CKError(.zoneNotFound)] as NSDictionary])
        #expect(CloudKitListingCache.errorRequiresCacheDiscard(zoneKeyed))

        let harmless = partialFailure([id("a"): CKError(.serverRecordChanged)])
        #expect(!CloudKitListingCache.errorRequiresCacheDiscard(harmless))
    }
}
