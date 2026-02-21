//
//  MathRenderer.swift
//  MarkdownView
//
//  Created by 秋星桥 on 5/26/25.
//

import Foundation
import Litext
import SwiftMath

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

public enum MathRenderer {
    private final class CacheKey: NSObject {
        let latex: String
        let fontSize: CGFloat
        let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat

        init(latex: String, fontSize: CGFloat, textColor: PlatformColor) {
            self.latex = latex
            self.fontSize = fontSize
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #if canImport(UIKit)
                let resolvedColor = textColor.resolvedColor(with: UITraitCollection.current)
                resolvedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            #elseif canImport(AppKit)
                NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                    let resolvedColor = textColor.usingColorSpace(.sRGB) ?? textColor
                    resolvedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
                }
            #endif
            self.r = r; self.g = g; self.b = b; self.a = a
            super.init()
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(latex)
            hasher.combine(fontSize)
            hasher.combine(r)
            hasher.combine(g)
            hasher.combine(b)
            hasher.combine(a)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else { return false }
            return latex == other.latex && fontSize == other.fontSize
                && r == other.r && g == other.g && b == other.b && a == other.a
        }
    }

    private static let renderCache: NSCache<CacheKey, PlatformImage> = {
        let cache = NSCache<CacheKey, PlatformImage>()
        cache.countLimit = 256
        return cache
    }()

    private static func preprocessLatex(_ latex: String) -> String {
        latex
            .replacingOccurrences(of: "\\dots", with: "\\ldots")
            .replacingOccurrences(of: "\\implies", with: "\\Rightarrow")
            .replacingOccurrences(of: "\\begin{align}", with: "\\begin{aligned}")
            .replacingOccurrences(of: "\\end{align}", with: "\\end{aligned}")
            .replacingOccurrences(of: "\\begin{align*}", with: "\\begin{aligned}")
            .replacingOccurrences(of: "\\end{align*}", with: "\\end{aligned}")
            .replacingOccurrences(of: "\\begin{cases}", with: "\\left\\{\\begin{matrix}")
            .replacingOccurrences(of: "\\end{cases}", with: "\\end{matrix}\\right.")
            .replacingOccurrences(of: "\\dfrac", with: "\\frac")
            .replacingBoxedCommand()
    }

    public static func renderToImage(
        latex: String,
        fontSize: CGFloat = 16,
        textColor: PlatformColor = .black
    ) -> PlatformImage? {
        let cacheKey = CacheKey(latex: latex, fontSize: fontSize, textColor: textColor)
        if let cachedImage = renderCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let processedLatex = preprocessLatex(latex)

        #if canImport(UIKit)
            let resolvedTextColor = textColor
        #elseif canImport(AppKit)
            // Resolve dynamic colors in the current appearance context for SwiftMath
            var resolvedTextColor = textColor
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                resolvedTextColor = textColor.usingColorSpace(.sRGB) ?? textColor
            }
        #endif

        let mathImage = MTMathImage(
            latex: processedLatex,
            fontSize: fontSize,
            textColor: resolvedTextColor,
            labelMode: .text
        )
        let (error, image) = mathImage.asImage()

        guard error == nil, let image else {
            print("[!] MathRenderer failed to render image for content: \(latex) \(error?.localizedDescription ?? "?")")
            return nil
        }

        #if canImport(UIKit)
            let result = image.withRenderingMode(.alwaysTemplate).withTintColor(.label)
        #elseif canImport(AppKit)
            image.isTemplate = true
            let result = image
        #endif

        renderCache.setObject(result, forKey: cacheKey)
        return result
    }
}

// MARK: - String Extension

private extension String {
    func substring(with range: NSRange) -> String? {
        guard let swiftRange = Range(range, in: self) else { return nil }
        return String(self[swiftRange])
    }

    func replacingBoxedCommand() -> String {
        var result = self
        while let range = result.range(of: "\\boxed{") {
            let startIndex = range.upperBound
            var braceCount = 1
            var endIndex = startIndex

            // 找到匹配的右大括号
            while endIndex < result.endIndex, braceCount > 0 {
                let char = result[endIndex]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                }
                if braceCount > 0 {
                    endIndex = result.index(after: endIndex)
                }
            }

            if braceCount == 0 {
                // 提取内容并替换整个\boxed{...}
                let content = String(result[startIndex ..< endIndex])
                let fullRange = result.index(range.lowerBound, offsetBy: 0) ... endIndex
                result.replaceSubrange(fullRange, with: content)
            } else {
                // 如果没有找到匹配的括号，只移除\boxed{
                result.replaceSubrange(range, with: "")
                break
            }
        }
        return result
    }
}
