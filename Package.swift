// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MarkView",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-cmark.git", branch: "gfm"),
    ],
    targets: [
        .executableTarget(
            name: "MarkView",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            path: "Sources/MarkView"
        ),
    ]
)
