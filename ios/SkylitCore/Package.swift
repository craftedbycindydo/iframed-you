// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SkylitCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SkylitCore", targets: ["SkylitCore"])],
    targets: [
        .target(name: "SkylitCore"),
        .testTarget(name: "SkylitCoreTests", dependencies: ["SkylitCore"]),
    ]
)
