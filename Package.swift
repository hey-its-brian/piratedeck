// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PirateDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PirateDeckCore"),
        .executableTarget(name: "PirateDeck", dependencies: ["PirateDeckCore"]),
        .testTarget(name: "PirateDeckCoreTests", dependencies: ["PirateDeckCore"]),
    ]
)
