// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmoothWheel",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SmoothWheel", targets: ["SmoothWheel"])],
    targets: [
        .target(name: "ScrollCore"),
        .executableTarget(name: "SmoothWheel", dependencies: ["ScrollCore"]),
        .testTarget(name: "ScrollCoreTests", dependencies: ["ScrollCore"])
    ]
)
