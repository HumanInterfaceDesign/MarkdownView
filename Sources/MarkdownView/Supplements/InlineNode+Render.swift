//
//  InlineNode+Render.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2025/1/3.
//

import Foundation
import Litext
import MarkdownParser
import SwiftMath
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Cached attribute dictionaries to avoid repeated allocations.
/// Keyed by theme identity (font + color) which changes infrequently.
final class InlineAttributeCache {
    let bodyAttributes: [NSAttributedString.Key: Any]
    let codeAttributes: [NSAttributedString.Key: Any]

    init(theme: MarkdownTheme) {
        bodyAttributes = [
            .font: theme.fonts.body,
            .foregroundColor: theme.colors.body,
        ]
        codeAttributes = [
            .font: theme.fonts.codeInline,
            .backgroundColor: theme.colors.codeBackground.withAlphaComponent(0.05),
        ]
    }
}

extension [MarkdownInlineNode] {
    func render(theme: MarkdownTheme, context: MarkdownTextView.PreprocessedContent, viewProvider: ReusableViewProvider) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let cache = InlineAttributeCache(theme: theme)
        for node in self {
            result.append(node.render(theme: theme, context: context, viewProvider: viewProvider, attrCache: cache))
        }
        return result
    }
}

extension MarkdownInlineNode {
    func render(theme: MarkdownTheme, context: MarkdownTextView.PreprocessedContent, viewProvider: ReusableViewProvider) -> NSAttributedString {
        render(theme: theme, context: context, viewProvider: viewProvider, attrCache: InlineAttributeCache(theme: theme))
    }

    func render(theme: MarkdownTheme, context: MarkdownTextView.PreprocessedContent, viewProvider: ReusableViewProvider, attrCache: InlineAttributeCache) -> NSAttributedString {
        assert(Thread.isMainThread)
        switch self {
        case let .text(string):
            return NSMutableAttributedString(
                string: string,
                attributes: attrCache.bodyAttributes
            )
        case .softBreak:
            return NSAttributedString(string: " ", attributes: attrCache.bodyAttributes)
        case .lineBreak:
            return NSAttributedString(string: "\n", attributes: attrCache.bodyAttributes)
        case let .code(string), let .html(string):
            let text = NSMutableAttributedString(string: string, attributes: [.foregroundColor: theme.colors.code])
            text.addAttributes(attrCache.codeAttributes, range: .init(location: 0, length: text.length))
            return text
        case let .emphasis(children):
            let ans = NSMutableAttributedString()
            for child in children { ans.append(child.render(theme: theme, context: context, viewProvider: viewProvider, attrCache: attrCache)) }
            ans.addAttributes(
                [
                    .underlineStyle: NSUnderlineStyle.thick.rawValue,
                    .underlineColor: theme.colors.emphasis,
                ],
                range: NSRange(location: 0, length: ans.length)
            )
            return ans
        case let .strong(children):
            let ans = NSMutableAttributedString()
            for child in children { ans.append(child.render(theme: theme, context: context, viewProvider: viewProvider, attrCache: attrCache)) }
            ans.addAttributes(
                [.font: theme.fonts.bold],
                range: NSRange(location: 0, length: ans.length)
            )
            return ans
        case let .strikethrough(children):
            let ans = NSMutableAttributedString()
            for child in children { ans.append(child.render(theme: theme, context: context, viewProvider: viewProvider, attrCache: attrCache)) }
            ans.addAttributes(
                [.strikethroughStyle: NSUnderlineStyle.thick.rawValue],
                range: NSRange(location: 0, length: ans.length)
            )
            return ans
        case let .link(destination, children):
            let ans = NSMutableAttributedString()
            for child in children { ans.append(child.render(theme: theme, context: context, viewProvider: viewProvider, attrCache: attrCache)) }
            ans.addAttributes(
                [
                    .link: destination,
                    .foregroundColor: theme.colors.highlight,
                ],
                range: NSRange(location: 0, length: ans.length)
            )
            return ans
        case let .image(source, children):
            let altText = children.map { node -> String in
                if case let .text(text) = node { return text }
                return ""
            }.joined()

            // Check if image is already cached
            if let image = ImageLoader.shared.cachedImage(for: source) {
                return Self.renderImage(image, source: source, altText: altText, theme: theme)
            }

            // Show placeholder with link while loading
            let placeholderText = altText.isEmpty ? source : altText
            return NSAttributedString(
                string: placeholderText,
                attributes: [
                    .link: source,
                    .font: theme.fonts.body,
                    .foregroundColor: theme.colors.highlight,
                ]
            )
        case let .math(content, replacementIdentifier):
            // Get LaTeX content from rendered context or fallback to raw content
            let latexContent = context.rendered[replacementIdentifier]?.text ?? content

            if let item = context.rendered[replacementIdentifier], let image = item.image {
                var imageSize = image.size

                let drawingCallback = LTXLineDrawingAction { context, line, lineOrigin in
                    let glyphRuns = CTLineGetGlyphRuns(line) as NSArray
                    var runOffsetX: CGFloat = 0
                    for i in 0 ..< glyphRuns.count {
                        let run = glyphRuns[i] as! CTRun
                        let attributes = CTRunGetAttributes(run) as! [NSAttributedString.Key: Any]
                        if attributes[.contextIdentifier] as? String == replacementIdentifier {
                            break
                        }
                        runOffsetX += CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil)
                    }

                    var ascent: CGFloat = 0
                    var descent: CGFloat = 0
                    CTLineGetTypographicBounds(line, &ascent, &descent, nil)
                    if imageSize.height > ascent { // we only draw above the line
                        let newWidth = imageSize.width * (ascent / imageSize.height)
                        imageSize = CGSize(width: newWidth, height: ascent)
                    }

                    let rect = CGRect(
                        x: lineOrigin.x + runOffsetX,
                        y: lineOrigin.y,
                        width: imageSize.width,
                        height: imageSize.height
                    )

                    context.saveGState()

                    #if canImport(UIKit)
                        context.translateBy(x: 0, y: rect.origin.y + rect.size.height)
                        context.scaleBy(x: 1, y: -1)
                        context.translateBy(x: 0, y: -rect.origin.y)
                        image.draw(in: rect)
                    #else
                        assert(image.isTemplate)
                        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                            // Resolve label color at draw time for dynamic appearance updates
                            let labelColor = NSColor.labelColor.cgColor
                            context.clip(to: rect, mask: cgImage)
                            context.setFillColor(labelColor)
                            context.fill(rect)
                        } else {
                            assertionFailure()
                        }
                    #endif

                    context.restoreGState()
                }
                let attachment = LTXAttachment.hold(attrString: .init(string: latexContent))
                attachment.size = imageSize

                let attributes: [NSAttributedString.Key: Any] = [
                    LTXAttachmentAttributeName: attachment,
                    LTXLineDrawingCallbackName: drawingCallback,
                    kCTRunDelegateAttributeName as NSAttributedString.Key: attachment.runDelegate,
                    .contextIdentifier: replacementIdentifier,
                    .mathLatexContent: latexContent, // Store LaTeX content for on-demand rendering
                ]

                return NSAttributedString(
                    string: LTXReplacementText,
                    attributes: attributes
                )
            } else {
                // Fallback: render failed, show original LaTeX as inline code
                return NSAttributedString(
                    string: latexContent,
                    attributes: [
                        .font: theme.fonts.codeInline,
                        .foregroundColor: theme.colors.code,
                        .backgroundColor: theme.colors.codeBackground.withAlphaComponent(0.05),
                    ]
                )
            }
        }
    }

    /// Renders a loaded image as an inline attachment using the same LTXAttachment pattern as math.
    static func renderImage(
        _ image: PlatformImage,
        source: String,
        altText: String,
        theme: MarkdownTheme
    ) -> NSAttributedString {
        var imageSize = image.size
        // Scale down if needed (will be further constrained at draw time by container width)
        let maxWidth: CGFloat = 600
        if imageSize.width > maxWidth {
            let scale = maxWidth / imageSize.width
            imageSize = CGSize(width: maxWidth, height: imageSize.height * scale)
        }

        let drawingCallback = LTXLineDrawingAction { context, line, lineOrigin in
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray
            var runOffsetX: CGFloat = 0
            for i in 0 ..< glyphRuns.count {
                let run = glyphRuns[i] as! CTRun
                let attributes = CTRunGetAttributes(run) as! [NSAttributedString.Key: Any]
                if attributes[.contextIdentifier] as? String == source {
                    break
                }
                runOffsetX += CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil)
            }

            let rect = CGRect(
                x: lineOrigin.x + runOffsetX,
                y: lineOrigin.y,
                width: imageSize.width,
                height: imageSize.height
            )

            context.saveGState()

            #if canImport(UIKit)
                context.translateBy(x: 0, y: rect.origin.y + rect.size.height)
                context.scaleBy(x: 1, y: -1)
                context.translateBy(x: 0, y: -rect.origin.y)
                image.draw(in: rect)
            #elseif canImport(AppKit)
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    context.draw(cgImage, in: rect)
                }
            #endif

            context.restoreGState()
        }

        let representedText = altText.isEmpty ? source : altText
        let attachment = LTXAttachment.hold(attrString: .init(string: representedText))
        attachment.size = imageSize

        let attributes: [NSAttributedString.Key: Any] = [
            LTXAttachmentAttributeName: attachment,
            LTXLineDrawingCallbackName: drawingCallback,
            kCTRunDelegateAttributeName as NSAttributedString.Key: attachment.runDelegate,
            .contextIdentifier: source,
        ]

        return NSAttributedString(
            string: LTXReplacementText,
            attributes: attributes
        )
    }
}
