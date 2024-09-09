// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

func envEnable(_ key: String, default defaultValue: Bool = false) -> Bool {
    guard let value = Context.environment[key] else {
        return defaultValue
    }
    if value == "1" {
        return true
    } else if value == "0" {
        return false
    } else {
        return defaultValue
    }
}

let shellApp = envEnable("KY_SHELL_APP", default: false)

let sharedSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ConciseMagicFile"),
    .enableUpcomingFeature("ForwardTrailingClosures"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("BareSlashRegexLiterals"),
    .enableUpcomingFeature("ImportObjcForwardDeclarations"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("IsolatedDefaultValues"),
    .enableUpcomingFeature("FullTypedThrows"),
] + (shellApp ? [.define("SHELL_APP")] : [])

let package = Package(
    name: "KYBundleManager",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(name: "KYBundleManager", targets: ["KYBundleManager"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Kyle-Ye/BSDiffSwift", from: "0.0.1"),
        .package(url: "https://github.com/marmelroy/Zip", from: "2.1.2"),
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "KYBundleManager",
            dependencies: [
                .product(name: "BSDiffSwift", package: "BSDiffSwift"),
                .product(name: "Zip", package: "Zip"),
                .product(name: "Algorithms", package: "swift-algorithms"),
            ],
            resources: [.process("Resources")],
            swiftSettings: sharedSettings
        ),
        .testTarget(
            name: "KYBundleManagerTests",
            dependencies: ["KYBundleManager"],
            resources: [.process("Resources")]
        )
    ]
)
