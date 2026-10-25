// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PadKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PadKit", targets: ["PadKit"]),
    ],
    targets: [
        .target(name: "PadKit"),
        .testTarget(name: "PadKitTests", dependencies: ["PadKit"]),
    ]
)
