// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TeXClipper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "TeXClipper",
            targets: ["TeXClipper"]
        )
    ],
    targets: [
        .executableTarget(
            name: "TeXClipper",
            path: "TeXClipper",
            resources: [
                .process("Resources/mathjax-tex-svg.js"),
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "TeXClipperTests",
            dependencies: ["TeXClipper"],
            path: "TeXClipperTests"
        )
    ]
)
