import Foundation
import Observation

enum AddressCalibrationState: Equatable, Sendable {
    case notCalibrated
    case collecting(progress: Double)
    case calibrated(AddressCalibration)
    case failed(message: String)
}

@MainActor
@Observable
final class AddressCalibrationService {
    private(set) var state: AddressCalibrationState = .notCalibrated
    private(set) var calibration: AddressCalibration?

    var onCalibrationCompleted: ((AddressCalibration) -> Void)?
    private let thresholds: AddressCalibrationThresholds
    private var samples: [MotionSample] = []

    init(thresholds: AddressCalibrationThresholds = AddressCalibrationThresholds()) {
        self.thresholds = thresholds
    }

    func start() {
        samples.removeAll(keepingCapacity: true)
        calibration = nil
        state = .collecting(progress: 0)
    }

    func ingest(_ sample: MotionSample) {
        guard case .collecting = state else { return }
        samples.append(sample)
        guard let first = samples.first else { return }
        let elapsed = sample.motionTimestamp - first.motionTimestamp
        state = .collecting(progress: min(1, elapsed / thresholds.stableWindowSeconds))
        guard elapsed >= thresholds.stableWindowSeconds else { return }

        switch AddressCalibrationBuilder.evaluate(samples: samples, thresholds: thresholds) {
        case .success(let calibration):
            self.calibration = calibration
            state = .calibrated(calibration)
            onCalibrationCompleted?(calibration)
        case .failure(let failure):
            calibration = nil
            state = .failed(message: failure.localizedDescription)
        }
        samples.removeAll(keepingCapacity: true)
    }

    func clear() {
        samples.removeAll(keepingCapacity: false)
        calibration = nil
        state = .notCalibrated
    }
}
