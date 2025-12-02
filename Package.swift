// swift-tools-version:6.0
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
        .package(url: "https://github.com/rozd/passage.git", from: "0.0.1"),
        .package(url: "https://github.com/vapor-community/Imperial.git", from: "2.2.0"),
    ],
    targets: [
        .target(
            name: "PassageImperial",
            dependencies: [
                .product(name: "Passage", package: "passage"),
                .product(name: "Imperial", package: "Imperial"),
            ]
        ),
    ]
)
