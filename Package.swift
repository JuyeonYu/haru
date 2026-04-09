// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCMaxOK",
    defaultLocalization: "ko",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "CCMaxOKCore", targets: ["CCMaxOKCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3")
    ],
    targets: [
        .target(
            name: "CCMaxOKCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            resources: [
                .copy("Resources/statusline.sh"),
                .process("Resources/Localizable.xcstrings")
            ]
        ),
        .testTarget(
            name: "CCMaxOKCoreTests",
            dependencies: ["CCMaxOKCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
