// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TorqueDenAdmin",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TorqueDenAdmin",
            path: ".",
            exclude: [
                "TorqueDenAdminTests",
                "Package.swift"
            ],
            swiftSettings: [
                .unsafeFlags(["-framework", "Cocoa", "-framework", "Charts"])
            ]
        )
    ]
)
