import Foundation

enum PairingPayloadError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedVersion
    case missingSession
    case missingToken
    case invalidWebSocketURL

    var errorDescription: String? {
        switch self {
        case .invalidURL: "This QR code is not a golfsim pairing code."
        case .unsupportedVersion: "The simulator uses an unsupported pairing version."
        case .missingSession: "The pairing code does not contain a session identifier."
        case .missingToken: "The pairing code does not contain a connection token."
        case .invalidWebSocketURL: "The pairing code contains an invalid simulator address."
        }
    }
}

struct PairingPayload: Equatable, Sendable {
    static let supportedVersion = 1

    let version: Int
    let sessionID: String
    let token: String
    let webSocketURL: URL

    init(scannedValue: String) throws {
        guard
            let url = URL(string: scannedValue),
            url.scheme?.lowercased() == "golfsim",
            url.host?.lowercased() == "pair",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw PairingPayloadError.invalidURL
        }

        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard values[item.name] == nil else { throw PairingPayloadError.invalidURL }
            values[item.name] = item.value ?? ""
        }
        guard Int(values["v"] ?? "") == Self.supportedVersion else {
            throw PairingPayloadError.unsupportedVersion
        }
        guard let sessionID = values["session"], Self.isSafeIdentifier(sessionID) else {
            throw PairingPayloadError.missingSession
        }
        guard let token = values["token"], Self.isSafeIdentifier(token) else {
            throw PairingPayloadError.missingToken
        }
        guard
            let rawWebSocketURL = values["ws"],
            var webSocketComponents = URLComponents(string: rawWebSocketURL),
            ["ws", "wss"].contains(webSocketComponents.scheme?.lowercased() ?? ""),
            webSocketComponents.host != nil
        else {
            throw PairingPayloadError.invalidWebSocketURL
        }

        var queryItems = (webSocketComponents.queryItems ?? []).filter {
            $0.name != "session" && $0.name != "token"
        }
        queryItems.append(URLQueryItem(name: "session", value: sessionID))
        queryItems.append(URLQueryItem(name: "token", value: token))
        webSocketComponents.queryItems = queryItems
        guard let authenticatedURL = webSocketComponents.url else {
            throw PairingPayloadError.invalidWebSocketURL
        }

        version = Self.supportedVersion
        self.sessionID = sessionID
        self.token = token
        webSocketURL = authenticatedURL
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
        }
    }
}
