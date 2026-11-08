// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ishot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ishot", targets: ["ishot"])],
    targets: [
        .target(name: "IShotCore"),
        .executableTarget(name: "ishot", dependencies: ["IShotCore"]),
        .executableTarget(name: "ishot-checks", dependencies: ["IShotCore"], path: "Tests/IShotCoreTests")
    ]
)
