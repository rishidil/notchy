// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchIsland",
            path: "Sources/NotchIsland",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("CoreLocation"),
                .linkedLibrary("sqlite3"),
            ]
        )
    ]
)
