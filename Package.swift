// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownView",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16),
        .macOS(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "MarkdownView", targets: ["MarkdownView"]),
        .library(name: "MarkdownParser", targets: ["MarkdownParser"]),
    ],
    dependencies: [
        .package(url: "https://github.com/mgriebling/SwiftMath", from: "1.7.3"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", "0.23.0"..<"0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", "0.23.0"..<"0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-rust", from: "0.23.0"),
        .package(url: "https://github.com/gtokman/tree-sitter-swift", branch: "main"),
        .package(url: "https://github.com/gtokman/tree-sitter-c", branch: "master"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-cpp", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-ruby", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", from: "0.24.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-css", "0.23.0"..<"0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-c-sharp", "0.23.0"..<"0.25.0"),
        .package(url: "https://github.com/fwcd/tree-sitter-kotlin", from: "0.3.8"),
        .package(url: "https://github.com/HumanInterfaceDesign/tree-sitter-sql", branch: "main"),
        .package(url: "https://github.com/HumanInterfaceDesign/tree-sitter-yaml", branch: "master"),
        .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.7.1"),
    ],
    targets: [
        .target(
            name: "Litext",
            resources: [.process("Resources")]
        ),
        .target(
            name: "MarkdownView",
            dependencies: [
                "Litext",
                "MarkdownParser",
                "SwiftMath",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterGo", package: "tree-sitter-go"),
                .product(name: "TreeSitterRust", package: "tree-sitter-rust"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterC", package: "tree-sitter-c"),
                .product(name: "TreeSitterCPP", package: "tree-sitter-cpp"),
                .product(name: "TreeSitterJava", package: "tree-sitter-java"),
                .product(name: "TreeSitterRuby", package: "tree-sitter-ruby"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
                .product(name: "TreeSitterCSS", package: "tree-sitter-css"),
                .product(name: "TreeSitterCSharp", package: "tree-sitter-c-sharp"),
                .product(name: "TreeSitterKotlin", package: "tree-sitter-kotlin"),
                .product(name: "TreeSitterSql", package: "tree-sitter-sql"),
                .product(name: "TreeSitterYAML", package: "tree-sitter-yaml"),
            ],
            resources: [.process("Resources")]
        ),
        .target(name: "MarkdownParser", dependencies: [
            .product(name: "cmark-gfm", package: "swift-cmark"),
            .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
        ]),
        .testTarget(
            name: "MarkdownViewTests",
            dependencies: [
                "MarkdownView",
                "MarkdownParser",
            ]
        ),
    ]
)
