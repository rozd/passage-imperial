// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "passage-imperial",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PassageImperial", targets: ["PassageImperial"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor-community/Imperial.git", from: "2.2.0"),
        .package(url: "https://github.com/vapor-community/passage.git", from: "0.3.5"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
    ],
    targets: [
        .target(
            name: "PassageImperial",
            dependencies: [
                .product(name: "Passage", package: "passage"),
                .product(name: "Imperial", package: "Imperial"),
            ]
        ),
        .testTarget(
            name: "PassageImperialTests",
            dependencies: [
                "PassageImperial",
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
    ]
)
