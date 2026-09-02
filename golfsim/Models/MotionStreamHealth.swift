//
//  MotionStreamHealth.swift
//  golfsim
//

import Foundation

/// Rolling diagnostics used to validate capture quality on a physical device.
struct MotionStreamHealth: Equatable, Sendable {
    var sampleCount: Int = 0
    var streamDuration: TimeInterval = 0
    var estimatedSampleRateHz: Double = 0

    var lastIntervalSeconds: TimeInterval = 0
    var averageIntervalSeconds: Double = 0
    var minIntervalSeconds: TimeInterval = 0
    var maxIntervalSeconds: TimeInterval = 0

    var suspectedDropCount: Int = 0
    var configuredIntervalSeconds: TimeInterval = 0

    static let empty = MotionStreamHealth()

    var intervalJitterMilliseconds: Double {
        guard averageIntervalSeconds > 0 else { return 0 }
        return max(0, (maxIntervalSeconds - minIntervalSeconds) * 1000)
    }

    var isReceivingData: Bool {
        sampleCount > 0 && lastIntervalSeconds > 0 && lastIntervalSeconds < 1
    }

    var qualitySummary: String {
        guard sampleCount > 1 else { return "Waiting for samples…" }
        if estimatedSampleRateHz < configuredTargetHz * 0.85 {
            return "Sample rate below target — check device motion availability."
        }
        if suspectedDropCount > 0 {
            return "Stream active with \(suspectedDropCount) possible gap(s)."
        }
        return "Stream looks healthy for Milestone 1 validation."
    }

    private var configuredTargetHz: Double {
        guard configuredIntervalSeconds > 0 else { return 0 }
        return 1 / configuredIntervalSeconds
    }
}
