// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PeanutServiceManager",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "peanut-service-manager", targets: ["PeanutServiceManager"]),
        .executable(name: "peanut-service-supervisor", targets: ["PeanutServiceSupervisor"]),
        .library(name: "PeanutServiceIPC", targets: ["PeanutServiceIPC"])
    ],
    targets: [
        .target(name: "PeanutServiceIPC"),
        .executableTarget(name: "PeanutServiceManager", dependencies: ["PeanutServiceIPC"]),
        .executableTarget(name: "PeanutServiceSupervisor", dependencies: ["PeanutServiceIPC"])
    ]
)
