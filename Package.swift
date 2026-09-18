// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MenuHome",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "MenuHome",
            path: "Sources/MenuHome",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
