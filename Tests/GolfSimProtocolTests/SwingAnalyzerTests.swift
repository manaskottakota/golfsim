import Foundation
import Testing
@testable import GolfSimProtocol

@Test func rejectsNonMonotonicTimestamps() {
    var samples = syntheticSwingSamples()
    let previous = samples[120]
    samples[120] = sample(time: samples[119].motionTimestamp, rotation: previous.rotationRateMagnitude, acceleration: 0.1)
    let outcome = SwingAnalyzer().analyze(recording: recording(samples), calibration: calibration())
    guard case .failure(.nonMonotonicTimestamps(index: 120)) = outcome else {
        Issue.record("Expected non-monotonic timestamp failure")
        return
    }
}

@Test func rejectsInsufficientMotion() {
    let samples = (0..<400).map { sample(time: Double($0) * 0.01, rotation: 0.03, acceleration: 0.01) }
    let outcome = SwingAnalyzer().analyze(recording: recording(samples), calibration: calibration())
    #expect(outcome == .failure(.insufficientMotion))
}


@Test func ignoresSensorGapOutsideIsolatedSwing() throws {
    var samples = syntheticSwingSamples()
    for index in 1..<80 {
        samples[index].motionTimestamp += 0.12
    }
    // Restore monotonic timestamps with a single large pre-swing gap.
    for index in 80..<samples.count {
        samples[index].motionTimestamp += 0.12
    }
    let result = try SwingAnalyzer().analyze(recording: recording(samples), calibration: calibration()).get()
    #expect(result.metrics.peakRotationalVelocity >= 5)
}

@Test func acceptsTransitionWithoutDeepMagnitudeValley() throws {
    let samples = (0..<500).map { index in
        let time = Double(index) * 0.01
        let rotation: Double
        let acceleration: Double
        switch time {
        case ..<1.0: (rotation, acceleration) = (0.04, 0.02)
        case 1.0..<1.9: (rotation, acceleration) = (1.5 + (time - 1.0), 0.20)
        case 1.9..<2.05: (rotation, acceleration) = (1.35, 0.22)
        case 2.05..<2.42: (rotation, acceleration) = (2.0 + (time - 2.05) * 8.0, time > 2.33 ? 1.7 : 0.38)
        case 2.42..<3.1: (rotation, acceleration) = (1.8, 0.20)
        default: (rotation, acceleration) = (0.05, 0.02)
        }
        return sample(time: time, rotation: rotation, acceleration: acceleration)
    }
    let result = try SwingAnalyzer().analyze(recording: recording(samples), calibration: calibration()).get()
    #expect(result.metrics.downswingDuration > 0)
}

@Test func detectsOrderedSyntheticPhases() throws {
    let outcome = SwingAnalyzer().analyze(recording: recording(syntheticSwingSamples()), calibration: calibration())
    let result = try outcome.get()
    #expect(result.phases.map(\.phase) == SwingPhase.allCases)
    #expect(zip(result.phases, result.phases.dropFirst()).allSatisfy { $0.sampleIndex <= $1.sampleIndex })
    #expect(result.metrics.backswingDuration > result.metrics.downswingDuration)
    #expect(result.metrics.peakRotationalVelocity >= 5)
    #expect(result.metrics.tempoRatio > 1)
}

private func syntheticSwingSamples() -> [MotionSample] {
    (0..<500).map { index in
        let time = Double(index) * 0.01
        let rotation: Double
        let acceleration: Double
        switch time {
        case ..<1.0: (rotation, acceleration) = (0.04, 0.02)
        case 1.0..<1.85: (rotation, acceleration) = (1.4 + (time - 1.0) * 1.1, 0.18)
        case 1.85..<2.05: (rotation, acceleration) = (0.3, 0.12)
        case 2.05..<2.42: (rotation, acceleration) = (2.0 + (time - 2.05) * 9.0, time > 2.34 ? 1.8 : 0.35)
        case 2.42..<3.15: (rotation, acceleration) = (2.1 - (time - 2.42) * 1.8, 0.24)
        default: (rotation, acceleration) = (0.05, 0.02)
        }
        let angle = max(0, min(.pi, (time - 1) * 1.2))
        return sample(time: time, rotation: rotation, acceleration: acceleration, angle: angle)
    }
}

private func sample(time: Double, rotation: Double, acceleration: Double, angle: Double = 0) -> MotionSample {
    MotionSample(
        motionTimestamp: time,
        quaternionW: cos(angle / 2), quaternionX: 0, quaternionY: 0, quaternionZ: sin(angle / 2),
        rotationRateX: rotation, rotationRateY: 0, rotationRateZ: 0,
        userAccelerationX: acceleration, userAccelerationY: 0, userAccelerationZ: 0,
        gravityX: 0, gravityY: -1, gravityZ: 0
    )
}

private func recording(_ samples: [MotionSample]) -> SwingRecording {
    SwingRecording(id: UUID(), club: .sevenIron, triggeredAt: Date(), triggerMotionTimestamp: 0.5, samples: samples)
}

private func calibration() -> AddressCalibration {
    AddressCalibration(
        id: UUID(), capturedAt: Date(), motionTimestamp: 0.75,
        referenceQuaternion: .identity, sampleCount: 75,
        averageRotationRate: 0.02, maximumAbsoluteGravityZ: 0.01
    )
}
