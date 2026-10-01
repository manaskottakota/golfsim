import Foundation

enum SimulatorProtocolConfiguration {
    static let version = 1
    static let telemetryInterval: TimeInterval = 1.0 / 30.0
    static let pingInterval: TimeInterval = 10
}

struct ProtocolQuaternion: Codable, Equatable, Sendable {
    let w: Double
    let x: Double
    let y: Double
    let z: Double
}

struct ProtocolVector3: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
}

struct PhoneHelloPayload: Codable, Equatable, Sendable {
    let deviceName: String
    let appVersion: String
}

struct ConnectionAcceptedPayload: Codable, Equatable, Sendable {
    let sessionID: String
}

struct LivePosePayload: Codable, Equatable, Sendable {
    let sequenceNumber: UInt64
    let motionTimestamp: TimeInterval
    let sentAtUnixMilliseconds: Int64
    let quaternion: ProtocolQuaternion
    let rotationRate: ProtocolVector3
    let userAccelerationMagnitude: Double?
}

struct ClubSelectionPayload: Codable, Equatable, Sendable {
    let club: String
}

struct HeartbeatPayload: Codable, Equatable, Sendable {
    let id: String
    let sentAtUnixMilliseconds: Int64
}

struct DisconnectPayload: Codable, Equatable, Sendable {
    let reason: String
}

struct ProtocolErrorPayload: Codable, Equatable, Sendable {
    let message: String
}

enum SimulatorMessage: Equatable, Sendable {
    case phoneHello(PhoneHelloPayload)
    case connectionAccepted(ConnectionAcceptedPayload)
    case livePose(LivePosePayload)
    case clubSelection(ClubSelectionPayload)
    case ping(HeartbeatPayload)
    case pong(HeartbeatPayload)
    case disconnect(DisconnectPayload)
    case error(ProtocolErrorPayload)
}

extension SimulatorMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case phoneHello
        case connectionAccepted
        case livePose
        case clubSelection
        case ping
        case pong
        case disconnect
        case error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(SimulatorProtocolConfiguration.version, forKey: .protocolVersion)
        switch self {
        case .phoneHello(let payload):
            try container.encode(MessageType.phoneHello, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .connectionAccepted(let payload):
            try container.encode(MessageType.connectionAccepted, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .livePose(let payload):
            try container.encode(MessageType.livePose, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .clubSelection(let payload):
            try container.encode(MessageType.clubSelection, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .ping(let payload):
            try container.encode(MessageType.ping, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .pong(let payload):
            try container.encode(MessageType.pong, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .disconnect(let payload):
            try container.encode(MessageType.disconnect, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .error(let payload):
            try container.encode(MessageType.error, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .protocolVersion)
        guard version == SimulatorProtocolConfiguration.version else {
            throw DecodingError.dataCorruptedError(
                forKey: .protocolVersion,
                in: container,
                debugDescription: "Unsupported protocol version \(version)"
            )
        }

        switch try container.decode(MessageType.self, forKey: .type) {
        case .phoneHello: self = .phoneHello(try container.decode(PhoneHelloPayload.self, forKey: .payload))
        case .connectionAccepted: self = .connectionAccepted(try container.decode(ConnectionAcceptedPayload.self, forKey: .payload))
        case .livePose: self = .livePose(try container.decode(LivePosePayload.self, forKey: .payload))
        case .clubSelection: self = .clubSelection(try container.decode(ClubSelectionPayload.self, forKey: .payload))
        case .ping: self = .ping(try container.decode(HeartbeatPayload.self, forKey: .payload))
        case .pong: self = .pong(try container.decode(HeartbeatPayload.self, forKey: .payload))
        case .disconnect: self = .disconnect(try container.decode(DisconnectPayload.self, forKey: .payload))
        case .error: self = .error(try container.decode(ProtocolErrorPayload.self, forKey: .payload))
        }
    }
}
