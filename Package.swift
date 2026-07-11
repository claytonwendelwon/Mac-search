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
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("EventKit")
            ]
        )
    ]
)
