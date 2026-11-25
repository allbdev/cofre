// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CofreKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CofreKit", targets: ["CofreKit"]),
        .library(name: "CofreKeychain", targets: ["CofreKeychain"]),
    ],
    targets: [
        .target(name: "CofreKit"),
        .target(name: "CofreKeychain", dependencies: ["CofreKit"]),
        .testTarget(name: "CofreKitTests", dependencies: ["CofreKit"]),
        .testTarget(name: "CofreKeychainTests", dependencies: ["CofreKeychain"]),
    ]
)
