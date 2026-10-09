// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OlleeFrames",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "OlleeFrames", targets: ["OlleeFrames"]),
    ],
    targets: [
        .target(name: "OlleeFrames", path: "Sources/OlleeFrames"),
        .testTarget(
            name: "OlleeFramesTests",
            dependencies: ["OlleeFrames"],
            path: "Tests/OlleeFramesTests"
        ),
    ]
)
