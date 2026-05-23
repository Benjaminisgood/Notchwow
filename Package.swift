// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "notchwow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "notchwow", targets: ["NotchNotes"])
    ],
    dependencies: [
        .package(path: "Vendor/swift-markdown-engine")
    ],
    targets: [
        .executableTarget(
            name: "NotchNotes",
            dependencies: [
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
                .product(name: "MarkdownEngineLatex", package: "swift-markdown-engine")
            ],
            path: "Sources/NotchNotes"
        )
    ]
)
