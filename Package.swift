// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Beacon",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Beacon",
            path: "Sources/Beacon",
            swiftSettings: [
                .unsafeFlags(["-swift-version", "5"])
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("EventKit"),
                .linkedFramework("QuartzCore")
            ]
        ),
        .testTarget(
            name: "BeaconTests",
            dependencies: ["Beacon"],
            path: "Tests/BeaconTests",
            swiftSettings: [
                .unsafeFlags(["-swift-version", "5"])
            ]
        )
    ]
)
