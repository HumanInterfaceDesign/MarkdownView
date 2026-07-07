// swift-tools-version: 6.2
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
    traits: [
        // Default to the web-focused languages v0 chat renders. Trait *selection*
        // by a consumer isn't carried through Xcode / CocoaPods-generated projects
        // (the pbxproj has no per-consumer trait field, so Xcode always resolves
        // with the package default) — so the default is the only lever that prunes
        // grammars in that environment. The rest stay available by overriding the
        // default in a SwiftPM (CLI) consumer, e.g. `traits: ["Swift", "Go"]`.
        .default(enabledTraits: [
            "JavaScript",
            "TypeScript",
            "JSON",
            "HTML",
            "CSS",
            "Bash",
        ]),
        .trait(name: "Python", description: "Python syntax highlighting"),
        .trait(name: "JavaScript", description: "JavaScript syntax highlighting"),
        .trait(name: "TypeScript", description: "TypeScript and TSX syntax highlighting"),
        .trait(name: "Go", description: "Go syntax highlighting"),
        .trait(name: "Rust", description: "Rust syntax highlighting"),
        .trait(name: "Swift", description: "Swift syntax highlighting"),
        .trait(name: "C", description: "C syntax highlighting"),
        .trait(name: "CPP", description: "C++ syntax highlighting"),
        .trait(name: "Java", description: "Java syntax highlighting"),
        .trait(name: "Ruby", description: "Ruby syntax highlighting"),
        .trait(name: "Bash", description: "Bash/shell syntax highlighting"),
        .trait(name: "JSON", description: "JSON syntax highlighting"),
        .trait(name: "HTML", description: "HTML syntax highlighting"),
        .trait(name: "CSS", description: "CSS syntax highlighting"),
        .trait(name: "CSharp", description: "C# syntax highlighting"),
        .trait(name: "Kotlin", description: "Kotlin syntax highlighting"),
        .trait(name: "SQL", description: "SQL syntax highlighting"),
        .trait(name: "YAML", description: "YAML syntax highlighting"),
    ],
    dependencies: [
        .package(url: "https://github.com/mgriebling/SwiftMath", from: "1.7.3"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", "0.23.0"..<"0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", "0.23.0"..<"0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-rust", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-cpp", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-ruby", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", from: "0.24.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-css", "0.23.0"..<"0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-c-sharp", "0.23.0"..<"0.25.0"),
        .package(url: "https://github.com/fwcd/tree-sitter-kotlin", from: "0.3.8"),
        .package(url: "https://github.com/HumanInterfaceDesign/tree-sitter-swift", branch: "main"),
        .package(url: "https://github.com/HumanInterfaceDesign/tree-sitter-c", branch: "master"),
        .package(url: "https://github.com/HumanInterfaceDesign/tree-sitter-sql", branch: "main"),
        .package(url: "https://github.com/HumanInterfaceDesign/tree-sitter-yaml", branch: "master"),
        .package(url: "https://github.com/swiftlang/swift-cmark", branch: "gfm"),
    ],
    targets: [
        .target(
            name: "Litext",
            resources: [.process("Resources")],
            // UIView/NSView-based text label — main-actor by default.
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .target(
            name: "MarkdownView",
            dependencies: [
                "Litext",
                "MarkdownParser",
                "SwiftMath",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python",
                         condition: .when(traits: ["Python"])),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript",
                         condition: .when(traits: ["JavaScript"])),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript",
                         condition: .when(traits: ["TypeScript"])),
                .product(name: "TreeSitterGo", package: "tree-sitter-go",
                         condition: .when(traits: ["Go"])),
                .product(name: "TreeSitterRust", package: "tree-sitter-rust",
                         condition: .when(traits: ["Rust"])),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift",
                         condition: .when(traits: ["Swift"])),
                .product(name: "TreeSitterC", package: "tree-sitter-c",
                         condition: .when(traits: ["C"])),
                .product(name: "TreeSitterCPP", package: "tree-sitter-cpp",
                         condition: .when(traits: ["CPP"])),
                .product(name: "TreeSitterJava", package: "tree-sitter-java",
                         condition: .when(traits: ["Java"])),
                .product(name: "TreeSitterRuby", package: "tree-sitter-ruby",
                         condition: .when(traits: ["Ruby"])),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash",
                         condition: .when(traits: ["Bash"])),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json",
                         condition: .when(traits: ["JSON"])),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html",
                         condition: .when(traits: ["HTML"])),
                .product(name: "TreeSitterCSS", package: "tree-sitter-css",
                         condition: .when(traits: ["CSS"])),
                .product(name: "TreeSitterCSharp", package: "tree-sitter-c-sharp",
                         condition: .when(traits: ["CSharp"])),
                .product(name: "TreeSitterKotlin", package: "tree-sitter-kotlin",
                         condition: .when(traits: ["Kotlin"])),
                .product(name: "TreeSitterSql", package: "tree-sitter-sql",
                         condition: .when(traits: ["SQL"])),
                .product(name: "TreeSitterYAML", package: "tree-sitter-yaml",
                         condition: .when(traits: ["YAML"])),
            ],
            resources: [.process("Resources")],
            // SwiftUI/UIKit rendering layer — main-actor by default.
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .target(
            name: "MarkdownParser",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            // Pure data / parsing — safe to run off the main actor, so it stays
            // nonisolated and models are `Sendable`.
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MarkdownViewTests",
            dependencies: [
                "MarkdownView",
                "MarkdownParser",
            ]
        ),
    ],
    // Targets are migrated to the Swift 6 language mode individually (see each
    // target's `swiftSettings`). This package default keeps any not-yet-migrated
    // target in the Swift 5 mode so its pre-existing concurrency warnings don't
    // become errors mid-migration.
    swiftLanguageModes: [.v5]
)
