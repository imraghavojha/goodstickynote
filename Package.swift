// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GoodSticky",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "GoodSticky", targets: ["GoodSticky"])],
    targets: [
        .executableTarget(name: "GoodSticky")
    ]
)
