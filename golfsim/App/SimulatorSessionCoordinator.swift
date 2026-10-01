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

    var canReconnect: Bool { lastPairingPayload != nil }

    init(motion: MotionCaptureService, clubSelection: ClubSelectionStore) {
        self.motion = motion
        self.clubSelection = clubSelection
        connection.onConnectionAccepted = { [weak self] in
            self?.sendSelectedClub()
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
