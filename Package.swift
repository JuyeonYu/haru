// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCMaxOK",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "CCMaxOKCore", targets: ["CCMaxOKCore"])
    ],
    targets: [
        .target(
            name: "CCMaxOKCore",
            resources: [.copy("Resources/statusline.sh")]
        ),
        .testTarget(
            name: "CCMaxOKCoreTests",
            dependencies: ["CCMaxOKCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
