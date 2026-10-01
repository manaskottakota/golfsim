import Foundation

struct SwingAnalyzer: Sendable {
    var thresholds = SwingAnalysisThresholds()

    func analyze(
        recording: SwingRecording,
        calibration: AddressCalibration?
    ) -> Result<SwingAnalysisResult, SwingAnalysisFailure> {
        guard let calibration else { return .failure(.noCalibration) }
        let samples = recording.samples
        guard samples.count >= thresholds.minimumCaptureSamples else { return .failure(.captureTooShort) }

        for index in 1..<samples.count {
            let interval = samples[index].motionTimestamp - samples[index - 1].motionTimestamp
            guard interval > 0 else { return .failure(.nonMonotonicTimestamps(index: index)) }
            guard interval <= thresholds.maximumSampleGapSeconds else {
                return .failure(.excessiveSampleGap(seconds: interval))
            }
        }

        let rawRotation = samples.map(\.rotationRateMagnitude)
        let rawAcceleration = samples.map(\.userAccelerationMagnitude)
        let smoothRotation = movingAverage(rawRotation, width: thresholds.smoothingWindowSamples)
        let smoothAcceleration = movingAverage(rawAcceleration, width: thresholds.smoothingWindowSamples)
        let active = zip(smoothRotation, smoothAcceleration).map {
            $0 >= thresholds.activityRotationRate || $1 >= thresholds.activityAcceleration
        }
        let segments = activitySegments(active: active)
        guard !segments.isEmpty else { return .failure(.insufficientMotion) }

        let ranked = segments.sorted {
            activityEnergy(in: $0, rotation: smoothRotation, acceleration: smoothAcceleration)
                > activityEnergy(in: $1, rotation: smoothRotation, acceleration: smoothAcceleration)
        }
        guard var primary = ranked.first else { return .failure(.insufficientMotion) }
        primary = expandAndSettle(
            segment: primary,
            rotation: smoothRotation,
            acceleration: smoothAcceleration
        )
        let activityDuration = samples[primary.upperBound].motionTimestamp - samples[primary.lowerBound].motionTimestamp
        guard activityDuration >= thresholds.minimumActivityDuration else { return .failure(.insufficientMotion) }
        if ranked.count > 1 {
            let firstEnergy = activityEnergy(in: ranked[0], rotation: smoothRotation, acceleration: smoothAcceleration)
            let secondEnergy = activityEnergy(in: ranked[1], rotation: smoothRotation, acceleration: smoothAcceleration)
            if secondEnergy > firstEnergy * 0.82 { return .failure(.ambiguousSwingWindow) }
        }

        let impactStart = primary.lowerBound + Int(Double(primary.count) * thresholds.impactSearchStartFraction)
        guard impactStart < primary.upperBound else { return .failure(.insufficientMotion) }
        let impactIndex = (impactStart...primary.upperBound).max { left, right in
            impactScore(index: left, rotation: smoothRotation, acceleration: smoothAcceleration)
                < impactScore(index: right, rotation: smoothRotation, acceleration: smoothAcceleration)
        } ?? primary.upperBound

        let minimumTransitionTime = samples[primary.lowerBound].motionTimestamp + thresholds.minimumBackswingDuration
        let latestTransitionTime = samples[impactIndex].motionTimestamp - thresholds.minimumDownswingDuration
        let transitionCandidates = primary.lowerBound..<impactIndex
        guard let transitionIndex = transitionCandidates
            .filter({ samples[$0].motionTimestamp >= minimumTransitionTime && samples[$0].motionTimestamp <= latestTransitionTime })
            .min(by: { smoothRotation[$0] < smoothRotation[$1] })
        else { return .failure(.noMeaningfulTransition) }

        let backswingPeak = smoothRotation[primary.lowerBound...transitionIndex].max() ?? 0
        let downswingPeak = smoothRotation[transitionIndex...impactIndex].max() ?? 0
        let referencePeak = min(backswingPeak, downswingPeak)
        guard
            backswingPeak >= thresholds.minimumBackswingPeakRotation,
            downswingPeak >= thresholds.minimumDownswingPeakRotation,
            referencePeak > 0,
            smoothRotation[transitionIndex] <= referencePeak * thresholds.minimumTransitionDropFraction
        else { return .failure(.noMeaningfulTransition) }

        let takeawayIndex = primary.lowerBound
        let addressIndex = max(0, takeawayIndex - thresholds.activitySustainSamples)
        let backswingIndex = min(transitionIndex, takeawayIndex + max(1, (transitionIndex - takeawayIndex) / 6))
        let impactHalfWidth = samplesToCover(
            seconds: thresholds.impactRegionHalfWidthSeconds,
            near: impactIndex,
            samples: samples
        )
        let impactRegionIndex = max(transitionIndex + 1, impactIndex - impactHalfWidth)
        let followThroughIndex = min(primary.upperBound, impactIndex + impactHalfWidth)
        let motionEndIndex = primary.upperBound
        let startTime = samples[takeawayIndex].motionTimestamp

        let phases: [SwingPhaseBoundary] = [
            boundary(.address, addressIndex, samples: samples, origin: startTime),
            boundary(.takeaway, takeawayIndex, samples: samples, origin: startTime),
            boundary(.backswing, backswingIndex, samples: samples, origin: startTime),
            boundary(.transition, transitionIndex, samples: samples, origin: startTime),
            boundary(.downswing, min(impactRegionIndex, transitionIndex + 1), samples: samples, origin: startTime),
            boundary(.impactRegion, impactRegionIndex, samples: samples, origin: startTime),
            boundary(.followThrough, followThroughIndex, samples: samples, origin: startTime),
            boundary(.motionEnd, motionEndIndex, samples: samples, origin: startTime),
        ]

        let backswingDuration = samples[transitionIndex].motionTimestamp - startTime
        let downswingDuration = samples[impactIndex].motionTimestamp - samples[transitionIndex].motionTimestamp
        guard backswingDuration > 0, downswingDuration > 0 else { return .failure(.noMeaningfulTransition) }
        let totalDuration = samples[motionEndIndex].motionTimestamp - startTime
        let maximumOrientationChange = samples[takeawayIndex...motionEndIndex]
            .map { MotionQuaternion(sample: $0).relative(to: calibration.referenceQuaternion).rotationAngleRadians }
            .max() ?? 0
        let metrics = SwingMetrics(
            totalSwingDuration: totalDuration,
            backswingDuration: backswingDuration,
            downswingDuration: downswingDuration,
            tempoRatio: backswingDuration / downswingDuration,
            peakRotationalVelocity: rawRotation[takeawayIndex...motionEndIndex].max() ?? 0,
            peakUserAcceleration: rawAcceleration[takeawayIndex...motionEndIndex].max() ?? 0,
            maximumRelativeOrientationChangeDegrees: maximumOrientationChange * 180 / .pi
        )

        var diagnostics: [String] = []
        if totalDuration < thresholds.expectedMinimumSwingDuration {
            diagnostics.append("Detected activity is shorter than the initial expected range.")
        } else if totalDuration > thresholds.expectedMaximumSwingDuration {
            diagnostics.append("Detected activity is longer than the initial expected range.")
        }
        let confidence = max(0.25, min(1, 0.55
            + min(0.2, (backswingPeak - thresholds.minimumBackswingPeakRotation) * 0.05)
            + min(0.2, (downswingPeak - thresholds.minimumDownswingPeakRotation) * 0.04)
            - Double(diagnostics.count) * 0.15))
        let timelineCount = motionEndIndex - addressIndex + 1
        let signalTimeline = stride(from: addressIndex, through: motionEndIndex, by: max(1, timelineCount / 500)).map { index in
            SwingSignalPoint(
                offsetSeconds: samples[index].motionTimestamp - startTime,
                rawRotationRate: rawRotation[index],
                smoothedRotationRate: smoothRotation[index],
                rawAcceleration: rawAcceleration[index],
                smoothedAcceleration: smoothAcceleration[index]
            )
        }
        return .success(SwingAnalysisResult(
            id: UUID(),
            recordingID: recording.id,
            calibrationID: calibration.id,
            club: recording.club,
            analyzedAt: Date(),
            phases: phases,
            metrics: metrics,
            confidence: confidence,
            diagnostics: diagnostics,
            signalTimeline: signalTimeline
        ))
    }

    private func movingAverage(_ values: [Double], width: Int) -> [Double] {
        guard width > 1 else { return values }
        let radius = width / 2
        var prefix = Array(repeating: 0.0, count: values.count + 1)
        for index in values.indices { prefix[index + 1] = prefix[index] + values[index] }
        return values.indices.map { index in
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            return (prefix[upper + 1] - prefix[lower]) / Double(upper - lower + 1)
        }
    }

    private func activitySegments(active: [Bool]) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for index in active.indices {
            if active[index], start == nil { start = index }
            if (!active[index] || index == active.count - 1), let runStart = start {
                let end = active[index] ? index : index - 1
                if end - runStart + 1 >= thresholds.activitySustainSamples { runs.append(runStart...end) }
                start = nil
            }
        }
        guard var current = runs.first else { return [] }
        var merged: [ClosedRange<Int>] = []
        for next in runs.dropFirst() {
            if next.lowerBound - current.upperBound - 1 <= thresholds.activityMergeGapSamples {
                current = current.lowerBound...next.upperBound
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    private func expandAndSettle(
        segment: ClosedRange<Int>,
        rotation: [Double],
        acceleration: [Double]
    ) -> ClosedRange<Int> {
        var lower = segment.lowerBound
        while lower > 0,
              rotation[lower - 1] > thresholds.settlingRotationRate || acceleration[lower - 1] > thresholds.settlingAcceleration {
            lower -= 1
        }
        var upper = segment.upperBound
        var quietCount = 0
        while upper + 1 < rotation.count {
            upper += 1
            if rotation[upper] < thresholds.settlingRotationRate && acceleration[upper] < thresholds.settlingAcceleration {
                quietCount += 1
                if quietCount >= thresholds.settlingSamples { break }
            } else {
                quietCount = 0
            }
        }
        return lower...upper
    }

    private func activityEnergy(in range: ClosedRange<Int>, rotation: [Double], acceleration: [Double]) -> Double {
        range.reduce(0) { $0 + rotation[$1] + acceleration[$1] * 2 }
    }

    private func impactScore(index: Int, rotation: [Double], acceleration: [Double]) -> Double {
        acceleration[index] * thresholds.accelerationImpactWeight
            + rotation[index] * thresholds.rotationImpactWeight
    }

    private func samplesToCover(seconds: TimeInterval, near index: Int, samples: [MotionSample]) -> Int {
        guard samples.count > 1 else { return 1 }
        let neighbor = index > 0 ? index - 1 : index + 1
        let interval = abs(samples[index].motionTimestamp - samples[neighbor].motionTimestamp)
        return max(1, Int((seconds / max(interval, 0.001)).rounded()))
    }

    private func boundary(
        _ phase: SwingPhase,
        _ index: Int,
        samples: [MotionSample],
        origin: TimeInterval
    ) -> SwingPhaseBoundary {
        SwingPhaseBoundary(
            phase: phase,
            sampleIndex: index,
            motionTimestamp: samples[index].motionTimestamp,
            offsetSeconds: samples[index].motionTimestamp - origin
        )
    }
}
