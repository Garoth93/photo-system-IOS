// swift-tools-version: 5.9
// Logic package for the Sweep app. Pure Swift, no UIKit/SwiftUI/Photos:
// it must build and test on Linux with `swift test`.
import PackageDescription

let package = Package(
    name: "SweepCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SweepCore", targets: ["SweepCore"])
    ],
    targets: [
        .target(
            name: "SweepCore",
            path: "Sources/SweepCore"
        ),
        .testTarget(
            name: "SweepCoreTests",
            dependencies: ["SweepCore"],
            path: "Tests/SweepCoreTests"
        )
    ]
)
