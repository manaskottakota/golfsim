//
//  AppState.swift
//  golfsim
//

import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    let motion = MotionCaptureService()
    let clubSelection = ClubSelectionStore()
}
