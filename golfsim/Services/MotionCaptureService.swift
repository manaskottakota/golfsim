//
//  MotionCaptureService.swift
//  golfsim
//

import CoreMotion
import Foundation
import Observation

enum MotionCaptureError: LocalizedError {
    case deviceMotionUnavailable
    case alreadyStreaming

    var errorDescription: String? {
        switch self {
        case .deviceMotionUnavailable:
            "Device motion is not available on this hardware."
        case .alreadyStreaming:
            "Motion streaming is already active."
        }
    }
}

@MainActor
@Observable
final class MotionCaptureService {
    private(set) var isStreaming = false
    private(set) var isRecording = false
    private(set) var latestSample: MotionSample?
    private(set) var health = MotionStreamHealth.empty
    private(set) var recordedSamples: [MotionSample] = []
    private(set) var lastErrorMessage: String?

    /// Target interval passed to Core Motion (actual rate is device-dependent).
    var preferredUpdateInterval: TimeInterval = 1.0 / 100.0

    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.manaskottakota.golfsim.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()

    private var streamStartMotionTime: TimeInterval?
    private var previousMotionTimestamp: TimeInterval?
    private var intervalSum: TimeInterval = 0
    private var intervalCount: Int = 0
    private var minInterval: TimeInterval = .greatestFiniteMagnitude
    private var maxInterval: TimeInterval = 0

    func startStreaming() throws {
        guard motionManager.isDeviceMotionAvailable else {
            throw MotionCaptureError.deviceMotionUnavailable
        }
        guard !isStreaming else {
            throw MotionCaptureError.alreadyStreaming
        }

        resetStreamStats()
        motionManager.deviceMotionUpdateInterval = preferredUpdateInterval
        health.configuredIntervalSeconds = preferredUpdateInterval

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryCorrectedZVertical,
            to: motionQueue
        ) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.lastErrorMessage = error.localizedDescription
                }
                return
            }
            guard let motion else { return }
            let sample = MotionSample(from: motion)
            Task { @MainActor in
                self.ingest(sample)
            }
        }

        isStreaming = true
        lastErrorMessage = nil
    }

    func stopStreaming() {
        motionManager.stopDeviceMotionUpdates()
        isStreaming = false
        isRecording = false
    }

    func startRecording() {
        guard isStreaming else { return }
        recordedSamples.removeAll(keepingCapacity: true)
        isRecording = true
    }

    func stopRecording() {
        isRecording = false
    }

    func clearRecording() {
        recordedSamples.removeAll(keepingCapacity: false)
    }

    func makeRecordingExportURL() throws -> URL {
        let payload = MotionRecordingExport(
            exportedAt: Date(),
            preferredUpdateIntervalSeconds: preferredUpdateInterval,
            sampleCount: recordedSamples.count,
            samples: recordedSamples
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("golfsim-motion-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func resetStreamStats() {
        streamStartMotionTime = nil
        previousMotionTimestamp = nil
        intervalSum = 0
        intervalCount = 0
        minInterval = .greatestFiniteMagnitude
        maxInterval = 0
        health = MotionStreamHealth.empty
        health.configuredIntervalSeconds = preferredUpdateInterval
    }

    private func ingest(_ sample: MotionSample) {
        latestSample = sample

        if streamStartMotionTime == nil {
            streamStartMotionTime = sample.motionTimestamp
        }

        var interval: TimeInterval = 0
        if let previousMotionTimestamp {
            interval = sample.motionTimestamp - previousMotionTimestamp
            if interval > 0 {
                intervalSum += interval
                intervalCount += 1
                minInterval = min(minInterval, interval)
                maxInterval = max(maxInterval, interval)

                let dropThreshold = preferredUpdateInterval * 2.5
                if interval > dropThreshold {
                    health.suspectedDropCount += 1
                }
            }
        }
        previousMotionTimestamp = sample.motionTimestamp

        health.sampleCount += 1
        if let streamStartMotionTime {
            health.streamDuration = max(0, sample.motionTimestamp - streamStartMotionTime)
        }
        if health.streamDuration > 0 {
            health.estimatedSampleRateHz = Double(health.sampleCount) / health.streamDuration
        }
        health.lastIntervalSeconds = interval
        if intervalCount > 0 {
            health.averageIntervalSeconds = intervalSum / Double(intervalCount)
            health.minIntervalSeconds = minInterval == .greatestFiniteMagnitude ? 0 : minInterval
            health.maxIntervalSeconds = maxInterval
        }

        if isRecording {
            recordedSamples.append(sample)
        }
    }
}

private struct MotionRecordingExport: Codable {
    var exportedAt: Date
    var preferredUpdateIntervalSeconds: TimeInterval
    var sampleCount: Int
    var samples: [MotionSample]
}
