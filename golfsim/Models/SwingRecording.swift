//
//  SwingRecording.swift
//  golfsim
//

import Foundation

enum SwingCapturePhase: Equatable, Sendable {
    case idle
    case capturing(postTriggerDeadline: TimeInterval)
}

struct SwingRecording: Identifiable, Codable, Sendable {
    var id: UUID
    var club: GolfClub
    var triggeredAt: Date
    var triggerMotionTimestamp: TimeInterval
    var samples: [MotionSample]

    var durationSeconds: TimeInterval {
        guard
            let first = samples.first,
            let last = samples.last
        else { return 0 }
        return max(0, last.motionTimestamp - first.motionTimestamp)
    }
}

struct SwingRecordingExport: Codable {
    var exportedAt: Date
    var club: GolfClub
    var triggeredAt: Date
    var triggerMotionTimestamp: TimeInterval
    var preTriggerSampleCount: Int
    var postTriggerSampleCount: Int
    var sampleCount: Int
    var durationSeconds: TimeInterval
    var samples: [MotionSample]
}
