// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Worklog",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure Foundation: day-file format and storage. Kept UI-free so an iOS app can reuse it.
        .target(name: "WorklogCore", path: "Sources/WorklogCore"),
        .executableTarget(name: "Worklog", dependencies: ["WorklogCore"], path: "Sources/Worklog"),
        .testTarget(name: "WorklogCoreTests", dependencies: ["WorklogCore"], path: "Tests/WorklogCoreTests"),
    ]
)
