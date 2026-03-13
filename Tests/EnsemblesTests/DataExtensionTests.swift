import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("Data Extensions")
struct DataExtensionTests {

    @Test("MD5 checksum produces hex string")
    func md5Checksum() {
        let data = Data("hello world".utf8)
        let checksum = data.md5Checksum
        #expect(checksum.count == 32)
        #expect(checksum == "5EB63BBBE01EEED093CB22BB8F5ACDC3")
    }

    @Test("SHA256 hash produces 32 bytes")
    func sha256Hash() {
        let data = Data("hello world".utf8)
        let hash = data.sha256Hash
        #expect(hash.count == 32)
    }

    @Test("Empty data MD5")
    func emptyDataMD5() {
        let data = Data()
        let checksum = data.md5Checksum
        #expect(checksum.count == 32)
        #expect(checksum == "D41D8CD98F00B204E9800998ECF8427E")
    }
}
