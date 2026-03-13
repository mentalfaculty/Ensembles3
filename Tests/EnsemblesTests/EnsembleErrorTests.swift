import Testing
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
}
