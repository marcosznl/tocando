// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tocando",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tocando",
            path: "Sources/Tocando",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
