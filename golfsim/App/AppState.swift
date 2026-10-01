//
//  AppState.swift
//  golfsim
//

import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    let motion: MotionCaptureService
    let clubSelection: ClubSelectionStore
    let motionStreaming: MotionStreamingCoordinator
    let simulatorSession: SimulatorSessionCoordinator

    init() {
        let motion = MotionCaptureService()
        let clubSelection = ClubSelectionStore()
        self.motion = motion
        self.clubSelection = clubSelection
        motionStreaming = MotionStreamingCoordinator()
        simulatorSession = SimulatorSessionCoordinator(motion: motion, clubSelection: clubSelection)
    }

    func setSwingSessionActive(_ active: Bool) {
        motionStreaming.setSwingSessionActive(active)
        syncMotionStreaming()
    }

    func setSensorLabStreamingRequested(_ requested: Bool) {
        motionStreaming.setSensorLabStreamingRequested(requested)
        syncMotionStreaming()
    }

    func syncMotionStreaming() {
        do {
            try motionStreaming.sync(motion: motion)
        } catch {
            motion.noteStreamingError(error)
        }
    }
}
