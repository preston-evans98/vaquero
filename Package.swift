// swift-tools-version: 6.2
import PackageDescription

var products: [Product] = [
    .library(name: "VaqueroKit", targets: ["VaqueroKit"]),
    .executable(name: "vaquero-server", targets: ["VaqueroServer"]),
]

var targets: [Target] = [
    .target(name: "VaqueroKit"),
    .executableTarget(
        name: "VaqueroServer",
        dependencies: [
            "VaqueroKit",
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
        ]
    ),
    .testTarget(name: "VaqueroKitTests", dependencies: ["VaqueroKit"]),
    .testTarget(
        name: "VaqueroServerTests",
        dependencies: [
            "VaqueroServer",
            .product(name: "HummingbirdTesting", package: "hummingbird"),
        ]
    ),
]

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.28.0"),
    .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
]

// The apps' shared views need SwiftUI, so they exist only on Apple platforms.
#if !os(Linux)
products.append(.library(name: "VaqueroUI", targets: ["VaqueroUI"]))
targets.append(
    .target(
        name: "VaqueroUI",
        dependencies: [
            "VaqueroKit",
            .product(name: "MarkdownUI", package: "swift-markdown-ui"),
        ]
    )
)
targets.append(
    .testTarget(
        name: "VaqueroUITests",
        dependencies: [
            "VaqueroUI",
            "VaqueroServer",
            .product(name: "HummingbirdTesting", package: "hummingbird"),
        ]
    )
)
dependencies.append(.package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1"))
#endif

let package = Package(
    name: "Vaquero",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
