// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PeanutServiceManager",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "peanut-service-manager", targets: ["PeanutServiceManager"])
    ],
    targets: [
        .executableTarget(name: "PeanutServiceManager")
    ]
)
