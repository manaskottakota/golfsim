//
//  MotionSample.swift
//  golfsim
//

import CoreMotion
import Foundation

/// One device-motion sample aligned for swing analysis (attitude, rates, acceleration).
struct MotionSample: Identifiable, Codable, Sendable {
    var id: UUID
    /// Core Motion timestamp (seconds since system boot).
    var motionTimestamp: TimeInterval
    /// Wall-clock time when the sample was received in the app.
    var receivedAt: Date

    var quaternionW: Double
    var quaternionX: Double
    var quaternionY: Double
    var quaternionZ: Double

    var rotationRateX: Double
    var rotationRateY: Double
    var rotationRateZ: Double

    var userAccelerationX: Double
    var userAccelerationY: Double
    var userAccelerationZ: Double

    var gravityX: Double
    var gravityY: Double
    var gravityZ: Double

    init(from motion: CMDeviceMotion, receivedAt: Date = Date()) {
        id = UUID()
        motionTimestamp = motion.timestamp
        self.receivedAt = receivedAt

        let q = motion.attitude.quaternion
        quaternionW = q.w
        quaternionX = q.x
        quaternionY = q.y
        quaternionZ = q.z

        rotationRateX = motion.rotationRate.x
        rotationRateY = motion.rotationRate.y
        rotationRateZ = motion.rotationRate.z

        userAccelerationX = motion.userAcceleration.x
        userAccelerationY = motion.userAcceleration.y
        userAccelerationZ = motion.userAcceleration.z

        gravityX = motion.gravity.x
        gravityY = motion.gravity.y
        gravityZ = motion.gravity.z
    }

    var userAccelerationMagnitude: Double {
        hypot3(userAccelerationX, userAccelerationY, userAccelerationZ)
    }

    var rotationRateMagnitude: Double {
        hypot3(rotationRateX, rotationRateY, rotationRateZ)
    }

    var gravityMagnitude: Double {
        hypot3(gravityX, gravityY, gravityZ)
    }

    private func hypot3(_ a: Double, _ b: Double, _ c: Double) -> Double {
        (a * a + b * b + c * c).squareRoot()
    }
}
