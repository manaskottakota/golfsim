import Foundation
import Testing
@testable import GolfSimProtocol

@Test func calibrationAveragesStableUprightWindow() throws {
    let samples = (0..<76).map { index in
        MotionSample(
            motionTimestamp: Double(index) * 0.01,
            quaternionW: 1, quaternionX: 0, quaternionY: 0, quaternionZ: Double(index % 2) * 0.0001,
            rotationRateX: 0.03, rotationRateY: 0.01, rotationRateZ: 0,
            userAccelerationX: 0, userAccelerationY: 0, userAccelerationZ: 0,
            gravityX: 0, gravityY: -1, gravityZ: 0.02
        )
    }
    let result = try AddressCalibrationBuilder.evaluate(samples: samples).get()
    #expect(result.sampleCount == 76)
    #expect(result.referenceQuaternion.relative(to: result.referenceQuaternion).rotationAngleRadians < 0.000_001)
}

@Test func calibrationRejectsMovement() {
    let samples = (0..<76).map { index in
        MotionSample(
            motionTimestamp: Double(index) * 0.01,
            quaternionW: 1, quaternionX: 0, quaternionY: 0, quaternionZ: 0,
            rotationRateX: 1, rotationRateY: 0, rotationRateZ: 0,
            userAccelerationX: 0, userAccelerationY: 0, userAccelerationZ: 0,
            gravityX: 0, gravityY: -1, gravityZ: 0
        )
    }
    #expect(AddressCalibrationBuilder.evaluate(samples: samples) == .failure(.phoneMoving))
}
