// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OTSMunkajelentoTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OTSMunkajelentoTracker",
            path: "Sources/OTSMunkajelentoTracker"
        )
    ]
)
