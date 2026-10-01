import Foundation

enum SwingPhase: String, CaseIterable, Codable, Sendable {
    case address
    case takeaway
    case backswing
    case transition
    case downswing
    case impactRegion = "impact_region"
    case followThrough = "follow_through"
    case motionEnd = "motion_end"
}

struct SwingPhaseBoundary: Codable, Equatable, Sendable {
    let phase: SwingPhase
    let sampleIndex: Int
    let motionTimestamp: TimeInterval
    let offsetSeconds: TimeInterval
}

struct SwingSignalPoint: Codable, Equatable, Sendable {
    let offsetSeconds: TimeInterval
    let rawRotationRate: Double
    let smoothedRotationRate: Double
    let rawAcceleration: Double
    let smoothedAcceleration: Double
}

struct SwingMetrics: Codable, Equatable, Sendable {
    let totalSwingDuration: TimeInterval
    let backswingDuration: TimeInterval
    let downswingDuration: TimeInterval
    let tempoRatio: Double
    let peakRotationalVelocity: Double
    let peakUserAcceleration: Double
    let maximumRelativeOrientationChangeDegrees: Double
}

struct SwingAnalysisResult: Codable, Equatable, Sendable {
    let id: UUID
    let recordingID: UUID
    let calibrationID: UUID
    let club: GolfClub
    let analyzedAt: Date
    let phases: [SwingPhaseBoundary]
    let metrics: SwingMetrics
    let confidence: Double
    let diagnostics: [String]
    let signalTimeline: [SwingSignalPoint]
}

enum SwingAnalysisFailure: LocalizedError, Codable, Equatable, Sendable {
    case noCalibration
    case captureTooShort
    case nonMonotonicTimestamps(index: Int)
    case excessiveSampleGap(seconds: Double)
    case insufficientMotion
    case ambiguousSwingWindow
    case noMeaningfulTransition

    var errorDescription: String? {
        switch self {
        case .noCalibration: "Set Address before recording a swing."
        case .captureTooShort: "The recording is too short to contain a complete swing."
        case .nonMonotonicTimestamps: "The recording contains non-monotonic motion timestamps."
        case .excessiveSampleGap: "The recording contains a sensor-data gap that is too large."
        case .insufficientMotion: "No complete swing was detected. Try again with a full swing."
        case .ambiguousSwingWindow: "The primary swing could not be isolated from other movement."
        case .noMeaningfulTransition: "A clear backswing-to-downswing transition was not detected."
        }
    }
}
