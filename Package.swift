// swift-tools-version:6.0
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
        .package(path: "../vapor-identity"),
        .package(url: "https://github.com/vapor-community/Imperial.git", from: "2.2.0"),
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
