import Foundation
import Testing
@testable import GolfSimProtocol

@Test func parsesValidPairingPayload() throws {
    let value = "golfsim://pair?v=1&session=session_123&token=token-456&ws=ws%3A%2F%2F192.168.1.2%3A8080%2Fcontroller"
    let payload = try PairingPayload(scannedValue: value)

    #expect(payload.version == 1)
    #expect(payload.sessionID == "session_123")
    #expect(payload.webSocketURL.absoluteString.contains("session=session_123"))
    #expect(payload.webSocketURL.absoluteString.contains("token=token-456"))
}

@Test(arguments: [
    "https://example.com/not-golfsim",
    "golfsim://pair?v=2&session=a&token=b&ws=ws%3A%2F%2Fhost%3A8080%2Fcontroller",
    "golfsim://pair?v=1&token=b&ws=ws%3A%2F%2Fhost%3A8080%2Fcontroller",
    "golfsim://pair?v=1&session=a&token=b&ws=https%3A%2F%2Fhost%2Fcontroller",
    "golfsim://pair?v=1&v=1&session=a&token=b&ws=ws%3A%2F%2Fhost%2Fcontroller",
    "not a url"
])
func rejectsMalformedPairingPayload(value: String) {
    #expect(throws: PairingPayloadError.self) {
        try PairingPayload(scannedValue: value)
    }
}
