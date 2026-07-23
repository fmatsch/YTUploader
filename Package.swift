// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YTUploader",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "YTUploader",
            path: "Sources/YTUploader"
        )
    ]
)
