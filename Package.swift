// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BackgroundButler",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BackgroundButler", targets: ["BackgroundButler"])
    ],
    targets: [
        .executableTarget(name: "BackgroundButler"),
        .testTarget(name: "BackgroundButlerTests", dependencies: ["BackgroundButler"])
    ]
)
