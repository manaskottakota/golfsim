import Foundation
import Observation

/// Bridges current app state to the simulator protocol without coupling networking to motion capture.
@MainActor
@Observable
final class SimulatorSessionCoordinator {
    let connection = SimulatorConnectionService()

    private let motion: MotionCaptureService
    private let clubSelection: ClubSelectionStore
    private var telemetryTimer: Timer?
    private var lastSentMotionTimestamp: TimeInterval?
    private var sequenceNumber: UInt64 = 0
    private var lastPairingPayload: PairingPayload?
    private var latestSwingStatus = SwingStatusPayload(state: "waiting_for_address", message: nil)

    var canReconnect: Bool { lastPairingPayload != nil }

    init(motion: MotionCaptureService, clubSelection: ClubSelectionStore) {
        self.motion = motion
        self.clubSelection = clubSelection
        connection.onConnectionAccepted = { [weak self] in
            self?.sendSelectedClub()
            if let status = self?.latestSwingStatus {
                self?.connection.send(.swingStatus(status))
            }
        }
        telemetryTimer = Timer.scheduledTimer(
            withTimeInterval: SimulatorProtocolConfiguration.telemetryInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.sendNewestPoseIfAvailable() }
        }
    }

    func connect(using payload: PairingPayload) {
        lastPairingPayload = payload
        sequenceNumber = 0
        lastSentMotionTimestamp = nil
        connection.connect(using: payload)
    }

    func disconnect() {
        connection.disconnect()
    }

    func reconnect() {
        guard let lastPairingPayload else { return }
        connect(using: lastPairingPayload)
    }

    func sendSelectedClub() {
        guard connection.state.isConnected else { return }
        connection.send(.clubSelection(ClubSelectionPayload(club: clubSelection.selectedClub.rawValue)))
    }

    func sendSwingStatus(_ state: SwingAnalysisWorkflowState) {
        let payload: SwingStatusPayload
        switch state {
        case .waitingForAddress: payload = SwingStatusPayload(state: "waiting_for_address", message: nil)
        case .ready: payload = SwingStatusPayload(state: "address_calibrated", message: nil)
        case .capturing: payload = SwingStatusPayload(state: "waiting_for_swing", message: nil)
        case .analyzing: payload = SwingStatusPayload(state: "analyzing", message: nil)
        case .complete: payload = SwingStatusPayload(state: "swing_complete", message: nil)
        case .invalid(let message): payload = SwingStatusPayload(state: "invalid", message: message)
        }
        latestSwingStatus = payload
        guard connection.state.isConnected else { return }
        connection.send(.swingStatus(payload))
    }

    func sendSwingResult(_ result: SwingAnalysisResult) {
        guard connection.state.isConnected else { return }
        let offsets = Dictionary(uniqueKeysWithValues: result.phases.map { ($0.phase.rawValue, $0.offsetSeconds) })
        connection.send(.swingResult(SwingResultPayload(
            resultID: result.id.uuidString,
            recordingID: result.recordingID.uuidString,
            club: result.club.rawValue,
            swingDuration: result.metrics.totalSwingDuration,
            backswingDuration: result.metrics.backswingDuration,
            downswingDuration: result.metrics.downswingDuration,
            tempoRatio: result.metrics.tempoRatio,
            peakRotationalVelocity: result.metrics.peakRotationalVelocity,
            peakAcceleration: result.metrics.peakUserAcceleration,
            maximumRelativeOrientationChangeDegrees: result.metrics.maximumRelativeOrientationChangeDegrees,
            phaseOffsets: offsets,
            confidence: result.confidence,
            diagnostics: result.diagnostics
        )))
    }

    private func sendNewestPoseIfAvailable() {
        guard
            connection.state.isConnected,
            let sample = motion.latestSample,
            sample.motionTimestamp != lastSentMotionTimestamp
        else { return }

        sequenceNumber &+= 1
        lastSentMotionTimestamp = sample.motionTimestamp
        connection.sendLivePose(LivePosePayload(
            sequenceNumber: sequenceNumber,
            motionTimestamp: sample.motionTimestamp,
            sentAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
            quaternion: ProtocolQuaternion(
                w: sample.quaternionW,
                x: sample.quaternionX,
                y: sample.quaternionY,
                z: sample.quaternionZ
            ),
            rotationRate: ProtocolVector3(
                x: sample.rotationRateX,
                y: sample.rotationRateY,
                z: sample.rotationRateZ
            ),
            userAccelerationMagnitude: sample.userAccelerationMagnitude
        ))
    }
}
