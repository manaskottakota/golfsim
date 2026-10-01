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

@Test func swingResultRoundTrips() throws {
    let original = SimulatorMessage.swingResult(SwingResultPayload(
        resultID: "result",
        recordingID: "recording",
        club: "7_iron",
        swingDuration: 2.1,
        backswingDuration: 1.2,
        downswingDuration: 0.4,
        tempoRatio: 3,
        peakRotationalVelocity: 8.5,
        peakAcceleration: 2.2,
        maximumRelativeOrientationChangeDegrees: 142,
        phaseOffsets: ["takeaway": 0, "transition": 1.2, "impact_region": 1.6],
        confidence: 0.82,
        diagnostics: []
    ))
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(SimulatorMessage.self, from: data) == original)
}
