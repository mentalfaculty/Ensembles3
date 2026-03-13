import Testing
@_spi(Testing) import Ensembles

@Suite("Logging")
struct LoggingTests {

    @Test("Set and get logging level")
    func setAndGetLoggingLevel() {
        let original = currentLoggingLevel()
        setLoggingLevel(.verbose)
        #expect(currentLoggingLevel() == .verbose)
        setLoggingLevel(.none)
        #expect(currentLoggingLevel() == .none)
        setLoggingLevel(original) // restore
    }

    @Test("Logging level raw values are ordered")
    func loggingLevelOrder() {
        #expect(LoggingLevel.none.rawValue < LoggingLevel.error.rawValue)
        #expect(LoggingLevel.error.rawValue < LoggingLevel.warning.rawValue)
        #expect(LoggingLevel.warning.rawValue < LoggingLevel.trace.rawValue)
        #expect(LoggingLevel.trace.rawValue < LoggingLevel.verbose.rawValue)
    }
}
