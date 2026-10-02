import Foundation

struct SwingAnalysisThresholds: Equatable, Sendable {
    var smoothingWindowSamples = 7
    var minimumCaptureSamples = 80
    var maximumSampleGapSeconds: TimeInterval = 0.08

    var activityRotationRate = 0.75
    var activityAcceleration = 0.28
    var activitySustainSamples = 8
    var activityMergeGapSamples = 30
    var settlingRotationRate = 0.38
    var settlingAcceleration = 0.16
    var settlingSamples = 18

    var minimumActivityDuration: TimeInterval = 0.65
    var expectedMinimumSwingDuration: TimeInterval = 0.8
    var expectedMaximumSwingDuration: TimeInterval = 4.5
    var minimumBackswingDuration: TimeInterval = 0.25
    var minimumDownswingDuration: TimeInterval = 0.12
    var minimumBackswingPeakRotation = 1.0
    var minimumDownswingPeakRotation = 1.8
    // Transition is primarily detected from angular-velocity direction reversal.
    // Magnitude is only a fallback for swings whose reversal is noisy.
    var transitionDirectionWindowSamples = 8
    var minimumDirectionalRotation = 0.35
    var maximumTransitionDirectionCosine = -0.12
    var transitionDirectionWeight = 0.78
    var transitionValleyWeight = 0.22
    var transitionMagnitudeFallbackFraction = 0.88

    var impactSearchStartFraction = 0.45
    var impactRegionHalfWidthSeconds: TimeInterval = 0.06
    var accelerationImpactWeight = 1.0
    var rotationImpactWeight = 0.32
}
