import Foundation
import Testing
@testable import GolfSimProtocol

@Test func addressMapsToRelativeIdentity() {
    let address = axisAngle(z: 1, radians: .pi / 3)
    let relative = address.relative(to: address)
    #expect(abs(relative.w - 1) < 0.000_001)
    #expect(abs(relative.x) < 0.000_001)
    #expect(abs(relative.y) < 0.000_001)
    #expect(abs(relative.z) < 0.000_001)
}

@Test func relativeRotationAndReturnAreStable() {
    let address = axisAngle(y: 1, radians: .pi / 4)
    let movement = axisAngle(x: 1, radians: .pi / 2)
    let current = address * movement
    let relative = current.relative(to: address)
    #expect(abs(relative.rotationAngleRadians - .pi / 2) < 0.000_001)
    #expect(abs(address.relative(to: address).rotationAngleRadians) < 0.000_001)
}

private func axisAngle(x: Double = 0, y: Double = 0, z: Double = 0, radians: Double) -> MotionQuaternion {
    let length = max(0.000_001, (x * x + y * y + z * z).squareRoot())
    let sine = sin(radians / 2)
    return MotionQuaternion(w: cos(radians / 2), x: x / length * sine, y: y / length * sine, z: z / length * sine)
}
