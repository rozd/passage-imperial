// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "vapor-identity-oauth-imperial",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "IdentityImperial", targets: ["IdentityImperial"]),
    ],
    dependencies: [
        .package(url: "https://github.com/rozd/vapor-identity.git", from: "1.0.0"),
        .package(url: "https://github.com/vapor-community/Imperial.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "IdentityImperial",
            dependencies: [
                .product(name: "Identity", package: "vapor-identity"),
                .product(name: "Imperial", package: "Imperial"),
            ]
        ),
    ]
)
