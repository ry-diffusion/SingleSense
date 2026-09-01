// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SingleSense",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SingleSense",
            targets: ["SingleSense"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SingleSense",
            dependencies: [],
            path: "Sources/SingleSense"
        ),
        .testTarget(
            name: "SingleSenseTests",
            dependencies: ["SingleSense"],
            path: "Tests/SingleSenseTests"
        )
    ]
)
