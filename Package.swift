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
            path: "golfsim",
            exclude: [
                "App", "Assets.xcassets", "Services", "Utilities", "Views",
                "ContentView.swift", "Info.plist", "golfsimApp.swift",
                "Connectivity/SimulatorConnectionService.swift",
                "Models/ClubSelectionStore.swift", "Models/MotionStreamHealth.swift"
            ],
            sources: [
                "Analysis",
                "Connectivity/PairingPayload.swift",
                "Connectivity/SimulatorProtocol.swift",
                "Models/GolfClub.swift",
                "Models/MotionSample.swift",
                "Models/SwingRecording.swift"
            ]
        ),
        .testTarget(
            name: "GolfSimProtocolTests",
            dependencies: ["GolfSimProtocol"],
            path: "Tests/GolfSimProtocolTests"
        )
    ]
)
