// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Gleam",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Gleam",
            path: "Sources/Gleam",
            exclude: ["Info.plist", "Gleam.entitlements", "Resources"],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        )
    ]
)
