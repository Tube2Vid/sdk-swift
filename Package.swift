// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tube2Vid",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8), .visionOS(.v1)],
    products: [
        .library(name: "Tube2Vid", targets: ["Tube2Vid"]),
    ],
    targets: [
        .target(name: "Tube2Vid"),
        .testTarget(name: "Tube2VidTests", dependencies: ["Tube2Vid"]),
    ]
)
