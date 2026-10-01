// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GolfSimProtocol",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GolfSimProtocol", targets: ["GolfSimProtocol"])
    ],
    targets: [
        .target(
            name: "GolfSimProtocol",
            path: "golfsim/Connectivity",
            exclude: ["SimulatorConnectionService.swift"],
            sources: ["PairingPayload.swift", "SimulatorProtocol.swift"]
        ),
        .testTarget(
            name: "GolfSimProtocolTests",
            dependencies: ["GolfSimProtocol"],
            path: "Tests/GolfSimProtocolTests"
        )
    ]
)
