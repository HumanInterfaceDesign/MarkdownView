//
//  Created by ktiays on 2025/1/22.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation
import SwiftTreeSitter
import TreeSitterPython
import TreeSitterJavaScript
import TreeSitterTypeScript
import TreeSitterTSX
import TreeSitterGo
import TreeSitterRust
import TreeSitterCPP
import TreeSitterJava
import TreeSitterRuby
import TreeSitterBash
import TreeSitterJSON
import TreeSitterHTML
import TreeSitterCSS

#if canImport(UIKit)
    import UIKit

    public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
    import AppKit

    public typealias PlatformColor = NSColor
#endif

private final class HighlightMapBox {
    let value: CodeHighlighter.HighlightMap
    init(_ value: CodeHighlighter.HighlightMap) { self.value = value }
}

public final class CodeHighlighter {
    public typealias HighlightMap = [NSRange: PlatformColor]

    private var renderCache: NSCache<NSNumber, HighlightMapBox> = {
        let cache = NSCache<NSNumber, HighlightMapBox>()
        cache.countLimit = 256
        return cache
    }()

    private init() {}

    public static let current = CodeHighlighter()

    // MARK: - Dynamic Color Helper

    static func dynamicColor(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
        #if canImport(UIKit)
            return UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? dark : light
            }
        #elseif canImport(AppKit)
            return NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                    dark
                } else {
                    light
                }
            }
        #endif
    }

    // MARK: - Language Registry

    /// Finds the queries directory URL for a given grammar bundle name.
    /// Handles both SPM flat bundles (`queries/`) and Xcode bundles (`Contents/Resources/queries/`).
    private static func queriesURL(for bundleName: String) -> URL? {
        let containerURL: URL? = {
            #if DEBUG
            if NSClassFromString("XCTest") != nil {
                return Bundle.allBundles
                    .first { $0.bundlePath.hasSuffix(".xctest") }?
                    .bundleURL
                    .deletingLastPathComponent()
            }
            #endif
            return Bundle.main.resourceURL
        }()

        guard let containerURL else { return nil }
        let bundleURL = containerURL.appendingPathComponent("\(bundleName).bundle")
        guard let bundle = Bundle(url: bundleURL) else { return nil }
        return bundle.resourceURL?.appendingPathComponent("queries")
    }

    private static func makeConfig(
        _ tsLanguage: OpaquePointer,
        name: String,
        bundleName: String? = nil,
        queriesSubpath: String? = nil
    ) throws -> LanguageConfiguration {
        let resolvedBundleName = bundleName ?? "TreeSitter\(name)_TreeSitter\(name)"
        if let queriesURL = queriesURL(for: resolvedBundleName) {
            let url = queriesSubpath.map { queriesURL.deletingLastPathComponent().appendingPathComponent($0) } ?? queriesURL
            return try LanguageConfiguration(tsLanguage, name: name, queriesURL: url)
        }
        return try LanguageConfiguration(tsLanguage, name: name)
    }

    private static let languageRegistry: [String: LanguageConfiguration] = {
        var registry: [String: LanguageConfiguration] = [:]

        func register(_ aliases: [String], _ factory: () throws -> LanguageConfiguration) {
            guard let config = try? factory() else { return }
            for alias in aliases {
                registry[alias] = config
            }
        }

        register(["python", "py", "python3"]) {
            try makeConfig(tree_sitter_python(), name: "Python")
        }
        register(["javascript", "js", "jsx"]) {
            try makeConfig(tree_sitter_javascript(), name: "JavaScript")
        }
        register(["typescript", "ts"]) {
            try makeConfig(tree_sitter_typescript(), name: "TypeScript",
                           bundleName: "TreeSitterTypeScript_TreeSitterTypeScript")
        }
        register(["tsx"]) {
            try makeConfig(tree_sitter_tsx(), name: "TSX",
                           bundleName: "TreeSitterTypeScript_TreeSitterTSX")
        }
        register(["go", "golang"]) {
            try makeConfig(tree_sitter_go(), name: "Go")
        }
        register(["rust", "rs"]) {
            try makeConfig(tree_sitter_rust(), name: "Rust")
        }
        register(["c", "h", "cpp", "c++", "cc", "cxx", "hpp"]) {
            try makeConfig(tree_sitter_cpp(), name: "CPP")
        }
        register(["java"]) {
            try makeConfig(tree_sitter_java(), name: "Java")
        }
        register(["ruby", "rb"]) {
            try makeConfig(tree_sitter_ruby(), name: "Ruby")
        }
        register(["bash", "sh", "shell", "zsh"]) {
            try makeConfig(tree_sitter_bash(), name: "Bash")
        }
        register(["json", "jsonc"]) {
            try makeConfig(tree_sitter_json(), name: "JSON")
        }
        register(["html", "htm"]) {
            try makeConfig(tree_sitter_html(), name: "HTML")
        }
        register(["css"]) {
            try makeConfig(tree_sitter_css(), name: "CSS")
        }

        return registry
    }()

    // MARK: - Capture-to-Color Theme Map

    private static let captureColorMap: [String: PlatformColor] = {
        let keyword = dynamicColor(
            light: PlatformColor(red: 0.667, green: 0.051, blue: 0.569, alpha: 1),
            dark: PlatformColor(red: 0.988, green: 0.373, blue: 0.647, alpha: 1)
        )
        let string = dynamicColor(
            light: PlatformColor(red: 0.769, green: 0.102, blue: 0.086, alpha: 1),
            dark: PlatformColor(red: 0.988, green: 0.416, blue: 0.365, alpha: 1)
        )
        let comment = dynamicColor(
            light: PlatformColor(red: 0, green: 0.455, blue: 0, alpha: 1),
            dark: PlatformColor(red: 0.447, green: 0.694, blue: 0.427, alpha: 1)
        )
        let type = dynamicColor(
            light: PlatformColor(red: 0.361, green: 0.149, blue: 0.6, alpha: 1),
            dark: PlatformColor(red: 0.631, green: 0.475, blue: 0.886, alpha: 1)
        )
        let function = dynamicColor(
            light: PlatformColor(red: 0.247, green: 0.431, blue: 0.455, alpha: 1),
            dark: PlatformColor(red: 0.431, green: 0.714, blue: 0.745, alpha: 1)
        )
        let number = dynamicColor(
            light: PlatformColor(red: 0.11, green: 0, blue: 0.812, alpha: 1),
            dark: PlatformColor(red: 0.557, green: 0.627, blue: 0.988, alpha: 1)
        )
        let property = dynamicColor(
            light: PlatformColor(red: 0.514, green: 0.424, blue: 0.157, alpha: 1),
            dark: PlatformColor(red: 0.835, green: 0.749, blue: 0.427, alpha: 1)
        )
        let tag = dynamicColor(
            light: PlatformColor(red: 0.392, green: 0.22, blue: 0.125, alpha: 1),
            dark: PlatformColor(red: 0.765, green: 0.569, blue: 0.439, alpha: 1)
        )

        return [
            "keyword": keyword,
            "string": string,
            "comment": comment,
            "type": type,
            "type.builtin": type,
            "constructor": type,
            "function": function,
            "function.method": function,
            "function.builtin": function,
            "function.call": function,
            "function.macro": function,
            "method": function,
            "method.call": function,
            "number": number,
            "number.float": number,
            "float": number,
            "constant.builtin": number,
            "property": property,
            "attribute": property,
            "field": property,
            "tag": tag,
            "tag.attribute": property,
            "tag.delimiter": tag,
            "variable.builtin": keyword,
            "boolean": keyword,
            "label": property,
            "include": keyword,
            "namespace": type,
        ]
    }()

    private static func color(forCapture name: String) -> PlatformColor? {
        if let color = captureColorMap[name] {
            return color
        }
        // Prefix fallback: "keyword.function" → "keyword"
        let components = name.split(separator: ".")
        if components.count > 1 {
            return captureColorMap[String(components[0])]
        }
        return nil
    }

    // MARK: - Tree-sitter Highlighting

    private func highlightWithTreeSitter(language: String, content: String) -> HighlightMap {
        guard !content.isEmpty else { return [:] }

        let lang = language.lowercased()
        guard let config = Self.languageRegistry[lang] else { return [:] }
        guard let query = config.queries[.highlights] else { return [:] }

        let parser = Parser()
        do {
            try parser.setLanguage(config.language)
        } catch {
            return [:]
        }

        guard let tree = parser.parse(content) else { return [:] }

        let cursor = query.execute(in: tree)
        let context = Predicate.Context(string: content)
        let highlights = cursor.resolve(with: context).highlights()

        var map: HighlightMap = [:]
        for highlight in highlights {
            if let color = Self.color(forCapture: highlight.name) {
                map[highlight.range] = color
            }
        }
        return map
    }
}

public extension CodeHighlighter {
    func key(for content: String, language: String?) -> Int {
        var hasher = Hasher()
        hasher.combine(content)
        hasher.combine(language?.lowercased() ?? "")
        return hasher.finalize()
    }

    func highlight(
        key: Int?,
        content: String,
        language: String?,
        theme: MarkdownTheme = .default
    ) -> [NSRange: PlatformColor] {
        let key = key ?? self.key(for: content, language: language)
        let nsKey = NSNumber(value: key)
        if let value = renderCache.object(forKey: nsKey) {
            return value.value
        }
        let map = highlightWithTreeSitter(language: language ?? "", content: content)
        renderCache.setObject(HighlightMapBox(map), forKey: nsKey)
        return map
    }
}

public extension CodeHighlighter.HighlightMap {
    func apply(to content: String, with theme: MarkdownTheme) -> NSMutableAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CodeViewConfiguration.codeLineSpacing

        let plainTextColor = theme.colors.code
        let attributedContent: NSMutableAttributedString = .init(
            string: content,
            attributes: [
                .font: theme.fonts.code,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: plainTextColor,
            ]
        )

        let length = attributedContent.length
        for (range, color) in self {
            guard range.location >= 0, range.upperBound <= length else { continue }
            guard color != plainTextColor else { continue }
            attributedContent.addAttributes([.foregroundColor: color], range: range)
        }
        return attributedContent
    }
}
