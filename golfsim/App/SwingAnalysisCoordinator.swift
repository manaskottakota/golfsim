import Foundation
import Observation

enum SwingAnalysisWorkflowState: Equatable, Sendable {
    case waitingForAddress
    case ready
    case capturing
    case analyzing
    case complete
    case invalid(message: String)
}

@MainActor
@Observable
final class SwingAnalysisCoordinator {
    let addressCalibration = AddressCalibrationService()
    private(set) var workflowState: SwingAnalysisWorkflowState = .waitingForAddress
    private(set) var latestResult: SwingAnalysisResult?

    var onStatusChanged: ((SwingAnalysisWorkflowState) -> Void)?
    var onResult: ((SwingAnalysisResult) -> Void)?

    private let motion: MotionCaptureService
    private let analyzer: SwingAnalyzer

    init(motion: MotionCaptureService, analyzer: SwingAnalyzer = SwingAnalyzer()) {
        self.motion = motion
        self.analyzer = analyzer
        motion.sampleIngestedHandler = { [weak self] sample in
            self?.addressCalibration.ingest(sample)
        }
        motion.swingCompletedHandler = { [weak self] recording in
            self?.analyze(recording)
        }
        addressCalibration.onCalibrationCompleted = { [weak self] _ in
            self?.setState(.ready)
        }
    }

    func setAddress() {
        latestResult = nil
        setState(.waitingForAddress)
        addressCalibration.start()
    }

    func startSwingCapture(club: GolfClub) {
        guard addressCalibration.calibration != nil else {
            setState(.invalid(message: SwingAnalysisFailure.noCalibration.localizedDescription))
            return
        }
        guard motion.isStreaming else {
            setState(.invalid(message: "Motion streaming is unavailable. Keep the Swing screen open and try again."))
            return
        }
        guard case .idle = motion.swingPhase else { return }
        latestResult = nil
        setState(.capturing)
        motion.triggerSwingCapture(club: club)
    }

    private func analyze(_ recording: SwingRecording) {
        let calibration = addressCalibration.calibration
        setState(.analyzing)
        Task { [weak self, analyzer] in
            let outcome = await Task.detached {
                analyzer.analyze(recording: recording, calibration: calibration)
            }.value
            guard let self else { return }
            switch outcome {
            case .success(let result):
                latestResult = result
                motion.attachAnalysis(result, to: recording.id)
                setState(.complete)
                onResult?(result)
            case .failure(let failure):
                setState(.invalid(message: failure.localizedDescription))
            }
        }
    }

    private func setState(_ state: SwingAnalysisWorkflowState) {
        workflowState = state
        onStatusChanged?(state)
    }
}
