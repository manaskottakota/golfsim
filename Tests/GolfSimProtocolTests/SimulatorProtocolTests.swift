import Foundation
import Testing
@testable import GolfSimProtocol

@Test func livePoseRoundTrips() throws {
    let original = SimulatorMessage.livePose(LivePosePayload(
        sequenceNumber: 42,
        motionTimestamp: 123.45,
        sentAtUnixMilliseconds: 1_700_000_000_000,
        quaternion: ProtocolQuaternion(w: 1, x: 0.1, y: 0.2, z: 0.3),
        rotationRate: ProtocolVector3(x: 2, y: 3, z: 4),
        userAccelerationMagnitude: 0.75
    ))

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(SimulatorMessage.self, from: encoded)
    #expect(decoded == original)
}

@Test func rejectsUnsupportedProtocolVersion() {
    let json = #"{"protocolVersion":99,"type":"ping","payload":{"id":"a","sentAtUnixMilliseconds":1}}"#
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(SimulatorMessage.self, from: Data(json.utf8))
    }
}
