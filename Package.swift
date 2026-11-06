// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VideoPlayer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VideoPlayer",
            path: "Sources/VideoPlayer"
        )
    ]
)
