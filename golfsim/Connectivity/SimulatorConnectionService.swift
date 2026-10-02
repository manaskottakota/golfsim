import Foundation
import Observation
import UIKit

enum SimulatorConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected(sessionID: String)
    case failed(message: String)

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .failed: "Connection failed"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

@MainActor
@Observable
final class SimulatorConnectionService {
    private(set) var state: SimulatorConnectionState = .disconnected
    private(set) var lastErrorMessage: String?

    var onConnectionAccepted: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var livePoseSendTask: Task<Void, Never>?
    private var pendingLivePose: LivePosePayload?
    private var expectedSessionID: String?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func connect(using payload: PairingPayload) {
        disconnect(sendMessage: false)
        expectedSessionID = payload.sessionID
        state = .connecting
        lastErrorMessage = nil

        let webSocketTask = URLSession.shared.webSocketTask(with: payload.webSocketURL)
        task = webSocketTask
        webSocketTask.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveMessages(from: webSocketTask)
        }
        heartbeatTask = Task { [weak self] in
            await self?.runHeartbeat()
        }
        handshakeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, self?.state == .connecting else { return }
            self?.handleConnectionFailure(SimulatorConnectionFailure.handshakeTimedOut)
        }
        let hello = SimulatorMessage.phoneHello(PhoneHelloPayload(
            deviceName: UIDevice.current.name,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        ))
        do {
            let data = try encoder.encode(hello)
            Task { [weak self] in
                do {
                    try await webSocketTask.send(.data(data))
                } catch {
                    guard self?.task === webSocketTask else { return }
                    await self?.handleConnectionFailure(error)
                }
            }
        } catch {
            handleConnectionFailure(error)
        }
    }

    func disconnect() {
        disconnect(sendMessage: true)
    }

    func send(_ message: SimulatorMessage) {
        guard let task else { return }
        do {
            let data = try encoder.encode(message)
            Task { [weak self] in
                do {
                    try await task.send(.data(data))
                } catch {
                    guard self?.task === task else { return }
                    await self?.handleConnectionFailure(error)
                }
            }
        } catch {
            handleConnectionFailure(error)
        }
    }

    /// Retains only the newest unsent pose while a WebSocket send is in flight.
    func sendLivePose(_ payload: LivePosePayload) {
        pendingLivePose = payload
        guard livePoseSendTask == nil else { return }
        livePoseSendTask = Task { [weak self] in
            await self?.drainLivePoses()
        }
    }

    private func drainLivePoses() async {
        defer { livePoseSendTask = nil }
        while let payload = pendingLivePose {
            pendingLivePose = nil
            guard let task else { return }
            do {
                let data = try encoder.encode(SimulatorMessage.livePose(payload))
                try await task.send(.data(data))
            } catch {
                guard self.task === task else { return }
                handleConnectionFailure(error)
                return
            }
        }
    }

    private func receiveMessages(from webSocketTask: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await webSocketTask.receive()
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: continue
                }
                let decoded = try decoder.decode(SimulatorMessage.self, from: data)
                handle(decoded)
            }
        } catch is CancellationError {
            return
        } catch {
            guard task === webSocketTask else { return }
            handleConnectionFailure(error)
        }
    }

    private func handle(_ message: SimulatorMessage) {
        switch message {
        case .connectionAccepted(let payload):
            guard payload.sessionID == expectedSessionID else {
                handleConnectionFailure(ProtocolErrorPayload(message: "Simulator accepted the wrong session."))
                return
            }
            state = .connected(sessionID: payload.sessionID)
            handshakeTimeoutTask?.cancel()
            handshakeTimeoutTask = nil
            lastErrorMessage = nil
            onConnectionAccepted?()
        case .ping(let payload):
            send(.pong(payload))
        case .disconnect(let payload):
            finishDisconnected(message: payload.reason)
        case .error(let payload):
            handleConnectionFailure(payload)
        case .phoneHello, .livePose, .clubSelection, .swingStatus, .swingResult, .pong:
            break
        }
    }

    private func runHeartbeat() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(SimulatorProtocolConfiguration.pingInterval))
            guard !Task.isCancelled, state.isConnected else { continue }
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            send(.ping(HeartbeatPayload(id: UUID().uuidString, sentAtUnixMilliseconds: now)))
        }
    }

    private func disconnect(sendMessage: Bool) {
        if sendMessage, task != nil {
            send(.disconnect(DisconnectPayload(reason: "Disconnected by iPhone")))
        }
        let oldTask = task
        task = nil
        expectedSessionID = nil
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        handshakeTimeoutTask?.cancel()
        livePoseSendTask?.cancel()
        pendingLivePose = nil
        receiveTask = nil
        heartbeatTask = nil
        handshakeTimeoutTask = nil
        livePoseSendTask = nil
        oldTask?.cancel(with: .normalClosure, reason: nil)
        state = .disconnected
    }

    private func handleConnectionFailure(_ error: Error) {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        handshakeTimeoutTask?.cancel()
        livePoseSendTask?.cancel()
        pendingLivePose = nil
        livePoseSendTask = nil
        handshakeTimeoutTask = nil
        let message = Self.userFacingMessage(for: error)
        lastErrorMessage = message
        state = .failed(message: message)
    }

    private func finishDisconnected(message: String) {
        disconnect(sendMessage: false)
        lastErrorMessage = message
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let failure = error as? SimulatorConnectionFailure {
            return failure.localizedDescription
        }
        guard let urlError = error as? URLError else {
            return "WebSocket connection failed: \(error.localizedDescription)"
        }
        switch urlError.code {
        case .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed:
            return "Local network unavailable. Join the same Wi-Fi network as the laptop and allow Local Network access in iOS Settings."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut:
            return "Laptop unreachable. Check that the simulator is running and that the QR code uses the laptop's Wi-Fi address."
        case .networkConnectionLost:
            return "The laptop connection was lost. Check Wi-Fi, then tap Reconnect."
        case .badServerResponse, .userAuthenticationRequired, .userCancelledAuthentication:
            return "The simulator rejected the WebSocket handshake. Restart the laptop server and scan its new QR code."
        default:
            return "WebSocket connection failed: \(urlError.localizedDescription)"
        }
    }
}

private enum SimulatorConnectionFailure: LocalizedError {
    case handshakeTimedOut

    var errorDescription: String? {
        "The laptop did not accept the handshake. Confirm both devices are on the same Wi-Fi network, then restart the simulator and scan its new QR code."
    }
}

extension ProtocolErrorPayload: LocalizedError {
    var errorDescription: String? { message }
}
