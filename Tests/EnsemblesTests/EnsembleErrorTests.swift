import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("EnsembleError")
struct EnsembleErrorTests {

    @Test("Error domain is CDEErrorDomain")
    func errorDomain() {
        #expect(EnsembleError.errorDomain == "CDEErrorDomain")
    }

    @Test("Error raw values match expected codes")
    func errorRawValues() {
        #expect(EnsembleError.unknown.rawValue == -1)
        #expect(EnsembleError.cancelled.rawValue == 101)
        #expect(EnsembleError.saveOccurredDuringMerge.rawValue == 207)
        #expect(EnsembleError.unknownModelVersion.rawValue == 204)
        #expect(EnsembleError.multipleObjectChanges.rawValue == 211)
    }

    @Test("Conforms to Error protocol")
    func conformsToError() {
        let error: Error = EnsembleError.unknown
        #expect(error is EnsembleError)
    }

    @Test("errorDescription names the case and code")
    func errorDescriptionNamesCaseAndCode() {
        let description = EnsembleError.missingGlobalIdentifierSource.errorDescription
        #expect(description?.contains("missingGlobalIdentifierSource") == true)
        #expect(description?.contains("220") == true)
        #expect(description?.contains("global identifiers") == true)
    }

    @Test("localizedDescription surfaces errorDescription through NSError bridging")
    func localizedDescriptionBridging() {
        let error: Error = EnsembleError.hardwareIdentityUnknown
        #expect(error.localizedDescription.contains("hardwareIdentityUnknown"))
        #expect(error.localizedDescription.contains("214"))
        #expect(!error.localizedDescription.contains("couldn’t be completed"))
    }

    @Test("Bridges to NSError with CDEErrorDomain and raw value code")
    func bridgesToNSErrorWithPublicDomain() {
        let nsError = EnsembleError.saveOccurredDuringMerge as NSError
        #expect(nsError.domain == "CDEErrorDomain")
        #expect(nsError.code == 207)
        #expect(nsError.localizedDescription.contains("saveOccurredDuringMerge"))
    }
}
