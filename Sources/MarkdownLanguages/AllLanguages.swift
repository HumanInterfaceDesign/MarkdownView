//
//  AllLanguages.swift
//  MarkdownView
//

import MarkdownView
import SwiftTreeSitter
import TreeSitterPython
import TreeSitterJavaScript
import TreeSitterTypeScript
import TreeSitterTSX
import TreeSitterGo
import TreeSitterRust
import TreeSitterSwift
import TreeSitterC
import TreeSitterCPP
import TreeSitterJava
import TreeSitterRuby
import TreeSitterBash
import TreeSitterJSON
import TreeSitterHTML
import TreeSitterCSS
import TreeSitterCSharp
import TreeSitterKotlin
import TreeSitterSql
import TreeSitterYAML

/// Provides registration functions for all bundled tree-sitter language parsers.
///
/// Use ``registerAll()`` at app launch to enable syntax highlighting for all 19 languages,
/// or call individual functions (e.g. ``registerPython()``) to include only what you need.
public enum MarkdownLanguages {

    /// Registers all 19 bundled language parsers with `CodeHighlighter`.
    public static func registerAll() {
        registerSwift()
        registerPython()
        registerJavaScript()
        registerTypeScript()
        registerTSX()
        registerGo()
        registerRust()
        registerC()
        registerCPP()
        registerJava()
        registerRuby()
        registerBash()
        registerJSON()
        registerHTML()
        registerCSS()
        registerCSharp()
        registerKotlin()
        registerSQL()
        registerYAML()
    }

    // MARK: - Individual Language Registration

    public static func registerSwift() {
        CodeHighlighter.registerLanguage(aliases: ["swift"]) {
            try CodeHighlighter.makeConfig(tree_sitter_swift(), name: "Swift")
        }
    }

    public static func registerPython() {
        CodeHighlighter.registerLanguage(aliases: ["python", "py", "python3"]) {
            try CodeHighlighter.makeConfig(tree_sitter_python(), name: "Python")
        }
    }

    public static func registerJavaScript() {
        CodeHighlighter.registerLanguage(aliases: ["javascript", "js", "jsx"]) {
            try CodeHighlighter.makeConfig(tree_sitter_javascript(), name: "JavaScript")
        }
    }

    public static func registerTypeScript() {
        CodeHighlighter.registerLanguage(aliases: ["typescript", "ts"]) {
            try CodeHighlighter.makeConfig(tree_sitter_typescript(), name: "TypeScript",
                                           bundleName: "TreeSitterTypeScript_TreeSitterTypeScript")
        }
    }

    public static func registerTSX() {
        CodeHighlighter.registerLanguage(aliases: ["tsx"]) {
            try CodeHighlighter.makeConfig(tree_sitter_tsx(), name: "TSX",
                                           bundleName: "TreeSitterTypeScript_TreeSitterTSX")
        }
    }

    public static func registerGo() {
        CodeHighlighter.registerLanguage(aliases: ["go", "golang"]) {
            try CodeHighlighter.makeConfig(tree_sitter_go(), name: "Go")
        }
    }

    public static func registerRust() {
        CodeHighlighter.registerLanguage(aliases: ["rust", "rs"]) {
            try CodeHighlighter.makeConfig(tree_sitter_rust(), name: "Rust")
        }
    }

    public static func registerC() {
        CodeHighlighter.registerLanguage(aliases: ["c", "h"]) {
            try CodeHighlighter.makeConfig(tree_sitter_c(), name: "C")
        }
    }

    public static func registerCPP() {
        CodeHighlighter.registerLanguage(aliases: ["cpp", "c++", "cc", "cxx", "hpp"]) {
            try CodeHighlighter.makeConfig(tree_sitter_cpp(), name: "CPP")
        }
    }

    public static func registerJava() {
        CodeHighlighter.registerLanguage(aliases: ["java"]) {
            try CodeHighlighter.makeConfig(tree_sitter_java(), name: "Java")
        }
    }

    public static func registerRuby() {
        CodeHighlighter.registerLanguage(aliases: ["ruby", "rb"]) {
            try CodeHighlighter.makeConfig(tree_sitter_ruby(), name: "Ruby")
        }
    }

    public static func registerBash() {
        CodeHighlighter.registerLanguage(aliases: ["bash", "sh", "shell", "zsh"]) {
            try CodeHighlighter.makeConfig(tree_sitter_bash(), name: "Bash")
        }
    }

    public static func registerJSON() {
        CodeHighlighter.registerLanguage(aliases: ["json", "jsonc"]) {
            try CodeHighlighter.makeConfig(tree_sitter_json(), name: "JSON")
        }
    }

    public static func registerHTML() {
        CodeHighlighter.registerLanguage(aliases: ["html", "htm"]) {
            try CodeHighlighter.makeConfig(tree_sitter_html(), name: "HTML")
        }
    }

    public static func registerCSS() {
        CodeHighlighter.registerLanguage(aliases: ["css"]) {
            try CodeHighlighter.makeConfig(tree_sitter_css(), name: "CSS")
        }
    }

    public static func registerCSharp() {
        CodeHighlighter.registerLanguage(aliases: ["csharp", "c#", "cs"]) {
            try CodeHighlighter.makeConfig(tree_sitter_c_sharp(), name: "CSharp",
                                           bundleName: "TreeSitterCSharp_TreeSitterCSharp")
        }
    }

    public static func registerKotlin() {
        CodeHighlighter.registerLanguage(aliases: ["kotlin", "kt", "kts"]) {
            try CodeHighlighter.makeConfig(tree_sitter_kotlin(), name: "Kotlin",
                                           bundleName: "TreeSitterKotlin_TreeSitterKotlin")
        }
    }

    public static func registerSQL() {
        CodeHighlighter.registerLanguage(aliases: ["sql"]) {
            try CodeHighlighter.makeConfig(tree_sitter_sql(), name: "SQL",
                                           bundleName: "TreeSitterSql_TreeSitterSql")
        }
    }

    public static func registerYAML() {
        CodeHighlighter.registerLanguage(aliases: ["yaml", "yml"]) {
            try CodeHighlighter.makeConfig(tree_sitter_yaml(), name: "YAML",
                                           bundleName: "TreeSitterYAML_TreeSitterYAML")
        }
    }
}
