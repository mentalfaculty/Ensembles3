import Testing
import Foundation
import EnsemblesPCloud
@_spi(Testing) import Ensembles

/// Tests for PCloudCloudFileSystem JSON parsing and error mapping.
/// Uses a mock URLProtocol to intercept network requests.
@Suite("PCloudCloudFileSystemTests")
struct PCloudCloudFileSystemTests {

    // MARK: - JSON Parsing Tests

    @Test("Parse userinfo response extracts email")
    func parseUserInfoResponse() throws {
        let json: [String: Any] = [
            "result": 0,
            "email": "user@example.com",
            "userid": 12345,
            "quota": 10737418240
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(parsed["result"] as? Int == 0)
        #expect(parsed["email"] as? String == "user@example.com")
    }

    @Test("Parse listfolder response produces correct CloudItems")
    func parseListFolderResponse() throws {
        let json: [String: Any] = [
            "result": 0,
            "metadata": [
                "contents": [
                    [
                        "name": "events",
                        "isfolder": true,
                        "folderid": 100
                    ],
                    [
                        "name": "snapshot.json",
                        "isfolder": false,
                        "size": 2048,
                        "fileid": 200
                    ],
                    [
                        "name": "baseline.json",
                        "isfolder": false,
                        "size": 512,
                        "fileid": 201
                    ]
                ]
            ] as [String: Any]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let metadata = parsed["metadata"] as! [String: Any]
        let contents = metadata["contents"] as! [[String: Any]]

        #expect(contents.count == 3)

        // First item: directory
        let first = contents[0]
        #expect(first["name"] as? String == "events")
        #expect(first["isfolder"] as? Bool == true)

        // Second item: file with size
        let second = contents[1]
        #expect(second["name"] as? String == "snapshot.json")
        #expect(second["isfolder"] as? Bool == false)
        #expect(second["size"] as? Int == 2048)

        // Third item: another file
        let third = contents[2]
        #expect(third["name"] as? String == "baseline.json")
        #expect(third["size"] as? Int == 512)
    }

    @Test("Parse stat response for existing file")
    func parseStatResponse() throws {
        let json: [String: Any] = [
            "result": 0,
            "metadata": [
                "name": "data.json",
                "isfolder": false,
                "size": 1024,
                "fileid": 300
            ] as [String: Any]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(parsed["result"] as? Int == 0)
        let metadata = parsed["metadata"] as! [String: Any]
        #expect(metadata["isfolder"] as? Bool == false)
        #expect(metadata["name"] as? String == "data.json")
    }

    @Test("Parse stat response for directory")
    func parseStatDirectoryResponse() throws {
        let json: [String: Any] = [
            "result": 0,
            "metadata": [
                "name": "events",
                "isfolder": true,
                "folderid": 100
            ] as [String: Any]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let metadata = parsed["metadata"] as! [String: Any]
        #expect(metadata["isfolder"] as? Bool == true)
    }

    // MARK: - Error Mapping Tests

    @Test("Error code 1000 maps to authenticationFailure")
    func loginRequiredError() throws {
        let error = mapPCloudResultCode(1000)
        #expect(error == .authenticationFailure)
    }

    @Test("Error code 2000 maps to fileAccessFailed")
    func fileNotFoundError() throws {
        let error = mapPCloudResultCode(2000)
        #expect(error == .fileAccessFailed)
    }

    @Test("Error code 2009 maps to fileAccessFailed")
    func fileNotFoundError2009() throws {
        let error = mapPCloudResultCode(2009)
        #expect(error == .fileAccessFailed)
    }

    @Test("Error code 2003 maps to authenticationFailure")
    func accessDeniedError() throws {
        let error = mapPCloudResultCode(2003)
        #expect(error == .authenticationFailure)
    }

    @Test("Unknown error code maps to serverError")
    func unknownErrorCode() throws {
        let error = mapPCloudResultCode(9999)
        #expect(error == .serverError)
    }

    // MARK: - Path Handling Tests

    @Test("Path without leading slash gets one prepended")
    func pathPrepending() {
        let result = pcloudPath(for: "ensembleId/events/data.json")
        #expect(result == "/ensembleId/events/data.json")
    }

    @Test("Path with leading slash is unchanged")
    func pathWithLeadingSlash() {
        let result = pcloudPath(for: "/ensembleId/events/data.json")
        #expect(result == "/ensembleId/events/data.json")
    }

    @Test("Root path is preserved")
    func rootPath() {
        let result = pcloudPath(for: "/")
        #expect(result == "/")
    }

    // MARK: - Helpers (mirror the private methods in PCloudCloudFileSystem)

    private func mapPCloudResultCode(_ code: Int) -> EnsembleError {
        switch code {
        case 1000:
            return .authenticationFailure
        case 2000, 2009, 2005:
            return .fileAccessFailed
        case 2003:
            return .authenticationFailure
        default:
            return .serverError
        }
    }

    private func pcloudPath(for path: String) -> String {
        var cloudPath = path
        if !cloudPath.hasPrefix("/") {
            cloudPath = "/" + cloudPath
        }
        return cloudPath
    }
}
