// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lookshift",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lookshift", targets: ["Lookshift"]),
    ],
    targets: [
        // Pure logic: measurements, calibration, switching and camera rules. No AppKit, no camera.
        .target(name: "LookshiftCore"),
        // The menu-bar app: camera, Vision, windows, UI.
        .executableTarget(name: "Lookshift", dependencies: ["LookshiftCore"]),
        .testTarget(name: "LookshiftCoreTests", dependencies: ["LookshiftCore"]),
    ]
)
