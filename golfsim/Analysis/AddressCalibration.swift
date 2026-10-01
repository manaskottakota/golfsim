import Foundation

struct AddressCalibration: Codable, Equatable, Sendable {
    let id: UUID
    let capturedAt: Date
    let motionTimestamp: TimeInterval
    let referenceQuaternion: MotionQuaternion
    let sampleCount: Int
    let averageRotationRate: Double
    let maximumAbsoluteGravityZ: Double
}

struct AddressCalibrationThresholds: Equatable, Sendable {
    var stableWindowSeconds: TimeInterval = 0.75
    var minimumSamples = 50
    var maximumAverageRotationRate = 0.18
    var maximumPeakRotationRate = 0.45
    var maximumAbsoluteGravityZ = 0.28
}

enum AddressCalibrationFailure: LocalizedError, Equatable, Sendable {
    case insufficientSamples
    case phoneNotUpright
    case phoneMoving
    case invalidQuaternion

    var errorDescription: String? {
        switch self {
        case .insufficientSamples: "Keep holding the phone still until calibration completes."
        case .phoneNotUpright: "Hold the phone upright, with its screen perpendicular to the ground."
        case .phoneMoving: "Hold phone still at address."
        case .invalidQuaternion: "Address orientation could not be measured. Try again."
        }
    }
}

enum AddressCalibrationBuilder {
    static func evaluate(
        samples: [MotionSample],
        thresholds: AddressCalibrationThresholds = AddressCalibrationThresholds()
    ) -> Result<AddressCalibration, AddressCalibrationFailure> {
        guard
            samples.count >= thresholds.minimumSamples,
            let first = samples.first,
            let last = samples.last,
            last.motionTimestamp - first.motionTimestamp >= thresholds.stableWindowSeconds * 0.9
        else { return .failure(.insufficientSamples) }

        let maximumGravityZ = samples.map { abs($0.gravityZ) }.max() ?? 1
        guard maximumGravityZ <= thresholds.maximumAbsoluteGravityZ else {
            return .failure(.phoneNotUpright)
        }
        let rotations = samples.map(\.rotationRateMagnitude)
        let averageRotation = rotations.reduce(0, +) / Double(rotations.count)
        guard
            averageRotation <= thresholds.maximumAverageRotationRate,
            rotations.max() ?? .infinity <= thresholds.maximumPeakRotationRate
        else { return .failure(.phoneMoving) }
        guard let reference = MotionQuaternion.averaged(samples.map(MotionQuaternion.init(sample:))) else {
            return .failure(.invalidQuaternion)
        }
        return .success(AddressCalibration(
            id: UUID(),
            capturedAt: Date(),
            motionTimestamp: last.motionTimestamp,
            referenceQuaternion: reference,
            sampleCount: samples.count,
            averageRotationRate: averageRotation,
            maximumAbsoluteGravityZ: maximumGravityZ
        ))
    }
}
