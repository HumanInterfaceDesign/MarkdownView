//
//  LTXLabel+Accessibility.swift
//  Litext
//
//  VoiceOver and accessibility support for LTXLabel.
//

import CoreText
import Foundation

extension LTXLabel {
    /// Builds an accessible string by replacing attachment characters (\uFFFC)
    /// with the text representation stored in their ``LTXAttachment``.
    func buildAccessibleString() -> String {
        let attrText = attributedText
        let fullRange = NSRange(location: 0, length: attrText.length)
        let raw = attrText.string

        guard raw.contains("\u{FFFC}") else { return raw }

        var result = raw
        // Walk backwards so replacement indices remain valid.
        attrText.enumerateAttribute(
            LTXAttachmentAttributeName,
            in: fullRange,
            options: .reverse
        ) { value, range, _ in
            guard let attachment = value as? LTXAttachment else { return }
            let replacement = attachment.attributedStringRepresentation().string
            guard let swiftRange = Range(range, in: result) else { return }
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }
}

#if canImport(UIKit)
    import UIKit

    extension LTXLabel {
        func configureAccessibility() {
            isAccessibilityElement = true
            accessibilityTraits = .staticText
        }

        override public var accessibilityValue: String? {
            get { buildAccessibleString() }
            set { /* read-only */ }
        }

        override public var accessibilityLabel: String? {
            get { buildAccessibleString() }
            set { /* read-only */ }
        }
    }

#elseif canImport(AppKit)
    import AppKit

    extension LTXLabel {
        func configureAccessibility() {
            setAccessibilityElement(true)
            setAccessibilityRole(.staticText)
        }

        override public func accessibilityValue() -> Any? {
            buildAccessibleString()
        }

        override public func accessibilityLabel() -> String? {
            buildAccessibleString()
        }

        override public func isAccessibilityElement() -> Bool {
            true
        }
    }
#endif
