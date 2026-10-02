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
        // The capture intentionally contains setup and post-swing movement. Keep only
        // the strongest sustained motion sequence and trim it to takeaway -> settled follow-through.
        primary = trimSwingWindow(primary, rotation: smoothRotation, acceleration: smoothAcceleration)

        // Sensor scheduling hiccups outside the isolated swing are irrelevant. Inside
        // the swing, tolerate a small number of gaps and reject only badly corrupted data.
        let swingGaps = sampleGaps(in: primary, samples: samples)
        if swingGaps.filter({ $0 > thresholds.severeSampleGapSeconds }).count > thresholds.maximumSevereGapsInSwing {
            return .failure(.excessiveSampleGap(seconds: swingGaps.max() ?? 0))
        }

        let impactStart = primary.lowerBound + Int(Double(primary.count) * thresholds.impactSearchStartFraction)
        guard impactStart < primary.upperBound else { return .failure(.insufficientMotion) }
        let impactIndex = (impactStart...primary.upperBound).max { left, right in
            impactScore(index: left, rotation: smoothRotation, acceleration: smoothAcceleration)
                < impactScore(index: right, rotation: smoothRotation, acceleration: smoothAcceleration)
        } ?? primary.upperBound

        let minimumTransitionTime = samples[primary.lowerBound].motionTimestamp + thresholds.minimumBackswingDuration
        let latestTransitionTime = samples[impactIndex].motionTimestamp - thresholds.minimumDownswingDuration
        let transitionCandidates = (primary.lowerBound..<impactIndex).filter {
            samples[$0].motionTimestamp >= minimumTransitionTime
                && samples[$0].motionTimestamp <= latestTransitionTime
        }
        guard !transitionCandidates.isEmpty else { return .failure(.noMeaningfulTransition) }

        // A real golf transition is a reversal of angular-velocity direction, not
        // necessarily a deep dip in total rotation-rate magnitude. Score each
        // candidate using direction reversal first and magnitude valley second.
        let transitionIndex = transitionCandidates.max { left, right in
            transitionScore(index: left, samples: samples, smoothRotation: smoothRotation)
                < transitionScore(index: right, samples: samples, smoothRotation: smoothRotation)
        } ?? transitionCandidates[0]

        let backswingPeak = smoothRotation[primary.lowerBound...transitionIndex].max() ?? 0
        let downswingPeak = smoothRotation[transitionIndex...impactIndex].max() ?? 0
        guard
            backswingPeak >= thresholds.minimumBackswingPeakRotation,
            downswingPeak >= thresholds.minimumDownswingPeakRotation
        else { return .failure(.noMeaningfulTransition) }

        // Direction reversal and a magnitude valley improve confidence, but are not
        // hard validity requirements. Whole-body rotation can keep phone angular
        // velocity high through a perfectly legitimate golf transition.
        let transitionHasReversal = hasDirectionReversal(near: transitionIndex, samples: samples)
        let transitionHasValley = smoothRotation[transitionIndex]
            <= min(backswingPeak, downswingPeak) * thresholds.transitionMagnitudeFallbackFraction

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
        if !transitionHasReversal && !transitionHasValley {
            diagnostics.append("Transition inferred from the best motion candidate; reversal signal was weak.")
        }
        if !swingGaps.isEmpty {
            let notableGaps = swingGaps.filter { $0 > thresholds.notableSampleGapSeconds }
            if !notableGaps.isEmpty {
                diagnostics.append("Motion stream contained \(notableGaps.count) brief sample gap(s) inside the swing.")
            }
        }
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

    private func trimSwingWindow(
        _ range: ClosedRange<Int>,
        rotation: [Double],
        acceleration: [Double]
    ) -> ClosedRange<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound

        // Require sustained motion before declaring takeaway so isolated setup/body
        // adjustments at the beginning are discarded.
        if range.count >= thresholds.swingOnsetSustainSamples {
            for index in range.lowerBound...max(range.lowerBound, range.upperBound - thresholds.swingOnsetSustainSamples + 1) {
                let end = min(range.upperBound, index + thresholds.swingOnsetSustainSamples - 1)
                let activeCount = (index...end).filter {
                    rotation[$0] >= thresholds.swingOnsetRotationRate
                        || acceleration[$0] >= thresholds.swingOnsetAcceleration
                }.count
                if activeCount >= thresholds.swingOnsetRequiredSamples {
                    lower = index
                    break
                }
            }
        }

        // End only after sustained settling. This keeps legitimate body rotation and
        // follow-through while removing repositioning after the swing.
        var quiet = 0
        if lower < range.upperBound {
            for index in (lower + 1)...range.upperBound {
                if rotation[index] <= thresholds.swingEndRotationRate
                    && acceleration[index] <= thresholds.swingEndAcceleration {
                    quiet += 1
                    if quiet >= thresholds.swingEndSettleSamples {
                        upper = max(lower + 1, index - quiet + 1)
                        break
                    }
                } else {
                    quiet = 0
                }
            }
        }
        return lower...max(lower + 1, upper)
    }

    private func sampleGaps(in range: ClosedRange<Int>, samples: [MotionSample]) -> [TimeInterval] {
        guard range.lowerBound < range.upperBound else { return [] }
        return ((range.lowerBound + 1)...range.upperBound).compactMap { index in
            let gap = samples[index].motionTimestamp - samples[index - 1].motionTimestamp
            return gap > thresholds.notableSampleGapSeconds ? gap : nil
        }
    }

    private func transitionScore(index: Int, samples: [MotionSample], smoothRotation: [Double]) -> Double {
        let radius = thresholds.transitionDirectionWindowSamples
        let beforeStart = max(0, index - radius)
        let afterEnd = min(samples.count - 1, index + radius)
        guard beforeStart < index, index < afterEnd else { return -Double.greatestFiniteMagnitude }

        let before = averageRotationVector(samples[beforeStart..<index])
        let after = averageRotationVector(samples[(index + 1)...afterEnd])
        let beforeMagnitude = vectorMagnitude(before)
        let afterMagnitude = vectorMagnitude(after)
        let reversal: Double
        if beforeMagnitude > 0.15, afterMagnitude > 0.15 {
            let cosine = dot(before, after) / (beforeMagnitude * afterMagnitude)
            reversal = max(0, -cosine)
        } else {
            reversal = 0
        }
        let localPeak = max(
            smoothRotation[beforeStart...index].max() ?? 0,
            smoothRotation[index...afterEnd].max() ?? 0
        )
        let valley = localPeak > 0 ? max(0, 1 - smoothRotation[index] / localPeak) : 0
        return reversal * thresholds.transitionDirectionWeight + valley * thresholds.transitionValleyWeight
    }

    private func hasDirectionReversal(near index: Int, samples: [MotionSample]) -> Bool {
        let radius = thresholds.transitionDirectionWindowSamples
        let beforeStart = max(0, index - radius)
        let afterEnd = min(samples.count - 1, index + radius)
        guard beforeStart < index, index < afterEnd else { return false }
        let before = averageRotationVector(samples[beforeStart..<index])
        let after = averageRotationVector(samples[(index + 1)...afterEnd])
        let a = vectorMagnitude(before)
        let b = vectorMagnitude(after)
        guard a >= thresholds.minimumDirectionalRotation, b >= thresholds.minimumDirectionalRotation else { return false }
        return dot(before, after) / (a * b) <= thresholds.maximumTransitionDirectionCosine
    }

    private func averageRotationVector<S: Sequence>(_ samples: S) -> (Double, Double, Double) where S.Element == MotionSample {
        var x = 0.0, y = 0.0, z = 0.0, count = 0.0
        for sample in samples {
            x += sample.rotationRateX; y += sample.rotationRateY; z += sample.rotationRateZ; count += 1
        }
        guard count > 0 else { return (0, 0, 0) }
        return (x / count, y / count, z / count)
    }

    private func vectorMagnitude(_ v: (Double, Double, Double)) -> Double {
        (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
    }

    private func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        a.0 * b.0 + a.1 * b.1 + a.2 * b.2
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
