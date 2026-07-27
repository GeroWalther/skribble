// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Skribble",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Skribble",
            path: "Sources/Skribble"
        )
    ]
)
