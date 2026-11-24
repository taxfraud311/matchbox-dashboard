// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Plinth",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Plinth",
            path: "Sources/Plinth",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Network"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
