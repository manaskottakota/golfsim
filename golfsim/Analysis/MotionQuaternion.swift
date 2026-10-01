import Foundation

struct MotionQuaternion: Codable, Equatable, Sendable {
    var w: Double
    var x: Double
    var y: Double
    var z: Double

    static let identity = MotionQuaternion(w: 1, x: 0, y: 0, z: 0)

    init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    init(sample: MotionSample) {
        self.init(w: sample.quaternionW, x: sample.quaternionX, y: sample.quaternionY, z: sample.quaternionZ)
    }

    var normalized: MotionQuaternion {
        let magnitude = (w * w + x * x + y * y + z * z).squareRoot()
        guard magnitude > .ulpOfOne else { return .identity }
        return MotionQuaternion(w: w / magnitude, x: x / magnitude, y: y / magnitude, z: z / magnitude)
    }

    var inverse: MotionQuaternion {
        let normSquared = w * w + x * x + y * y + z * z
        guard normSquared > .ulpOfOne else { return .identity }
        return MotionQuaternion(w: w / normSquared, x: -x / normSquared, y: -y / normSquared, z: -z / normSquared)
    }

    static func * (lhs: MotionQuaternion, rhs: MotionQuaternion) -> MotionQuaternion {
        MotionQuaternion(
            w: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z,
            x: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
            z: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w
        )
    }

    /// Core Motion attitudes are device-to-reference quaternions. Left multiplying the current
    /// attitude by the inverse address attitude expresses the current device in the address frame.
    func relative(to reference: MotionQuaternion) -> MotionQuaternion {
        (reference.normalized.inverse * normalized).normalized.canonicalized
    }

    var rotationAngleRadians: Double {
        let value = min(1, max(-1, abs(normalized.w)))
        return 2 * acos(value)
    }

    private var canonicalized: MotionQuaternion {
        w < 0 ? MotionQuaternion(w: -w, x: -x, y: -y, z: -z) : self
    }

    static func averaged(_ values: [MotionQuaternion]) -> MotionQuaternion? {
        guard let first = values.first else { return nil }
        let reference = first.normalized
        var total = MotionQuaternion(w: 0, x: 0, y: 0, z: 0)
        for value in values {
            var candidate = value.normalized
            let dot = reference.w * candidate.w + reference.x * candidate.x + reference.y * candidate.y + reference.z * candidate.z
            if dot < 0 {
                candidate = MotionQuaternion(w: -candidate.w, x: -candidate.x, y: -candidate.y, z: -candidate.z)
            }
            total.w += candidate.w
            total.x += candidate.x
            total.y += candidate.y
            total.z += candidate.z
        }
        return total.normalized
    }
}

struct RelativeMotionFrame: Codable, Equatable, Sendable {
    let motionTimestamp: TimeInterval
    let orientation: MotionQuaternion
    let rotationRateMagnitude: Double
    let userAccelerationMagnitude: Double

    init(sample: MotionSample, address: AddressCalibration) {
        motionTimestamp = sample.motionTimestamp
        orientation = MotionQuaternion(sample: sample).relative(to: address.referenceQuaternion)
        rotationRateMagnitude = sample.rotationRateMagnitude
        userAccelerationMagnitude = sample.userAccelerationMagnitude
    }
}
