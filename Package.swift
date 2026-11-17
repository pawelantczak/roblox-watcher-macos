// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RobloxWatcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "RobloxWatcherCore",
            targets: ["RobloxWatcherCore"]
        ),
        .executable(
            name: "roblox-watcher",
            targets: ["roblox-watcher"]
        ),
        .executable(
            name: "RobloxWatcherApp",
            targets: ["RobloxWatcherApp"]
        )
    ],
    targets: [
        .target(
            name: "RobloxWatcherCore",
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "roblox-watcher",
            dependencies: ["RobloxWatcherCore"],
            path: "Sources/CLI"
        ),
        .executableTarget(
            name: "RobloxWatcherApp",
            dependencies: ["RobloxWatcherCore"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "WatcherTests",
            dependencies: ["RobloxWatcherCore"],
            path: "Tests"
        )
    ]
)
