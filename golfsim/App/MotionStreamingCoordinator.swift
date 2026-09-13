//
//  MotionStreamingCoordinator.swift
//  golfsim
//

import Foundation
import Observation

/// Keeps Core Motion streaming alive while any feature needs it.
@MainActor
@Observable
final class MotionStreamingCoordinator {
    private(set) var isSensorLabStreamingRequested = false
    private(set) var isSwingSessionActive = false

    var isStreamingActive: Bool {
        isSensorLabStreamingRequested || isSwingSessionActive
    }

    func setSwingSessionActive(_ active: Bool) {
        isSwingSessionActive = active
    }

    func setSensorLabStreamingRequested(_ requested: Bool) {
        isSensorLabStreamingRequested = requested
    }

    func sync(motion: MotionCaptureService) throws {
        if isStreamingActive {
            if !motion.isStreaming {
                try motion.startStreaming()
            }
        } else if motion.isStreaming {
            motion.stopStreaming()
        }
    }
}
