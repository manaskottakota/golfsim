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
    let swingAnalysis: SwingAnalysisCoordinator

    init() {
        let motion = MotionCaptureService()
        let clubSelection = ClubSelectionStore()
        self.motion = motion
        self.clubSelection = clubSelection
        motionStreaming = MotionStreamingCoordinator()
        simulatorSession = SimulatorSessionCoordinator(motion: motion, clubSelection: clubSelection)
        let swingAnalysis = SwingAnalysisCoordinator(motion: motion)
        self.swingAnalysis = swingAnalysis
        swingAnalysis.onStatusChanged = { [weak simulatorSession] state in
            simulatorSession?.sendSwingStatus(state)
        }
        swingAnalysis.onResult = { [weak simulatorSession] result in
            simulatorSession?.sendSwingResult(result)
        }
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
