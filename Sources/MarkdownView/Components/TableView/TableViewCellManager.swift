//
//  TableViewCellManager.swift
//  MarkdownView
//
//  Created by ktiays on 2025/1/27.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Litext

#if canImport(UIKit)
    import UIKit

    final class TableViewCellManager {
        // MARK: - Properties

        private(set) var cells: [LTXLabel] = []
        private(set) var cellSizes: [CGSize] = []
        private(set) var widths: [CGFloat] = []
        private(set) var heights: [CGFloat] = []
        private var theme: MarkdownTheme = .default
        private weak var delegate: LTXLabelDelegate?
        /// Content hashes from previous configuration, for diff-based updates.
        private var previousContentHashes: [Int] = []

        // MARK: - Cell Configuration

        func configureCells(
            for contents: [[NSAttributedString]],
            in containerView: UIView,
            cellPadding: CGFloat,
            maximumCellWidth: CGFloat
        ) {
            let numberOfRows = contents.count
            let numberOfColumns = contents.first?.count ?? 0
            let totalCells = numberOfRows * numberOfColumns

            // Compute content hashes for diffing
            var newHashes = [Int]()
            newHashes.reserveCapacity(totalCells)
            for row in contents {
                for cell in row {
                    newHashes.append(cell.string.hashValue)
                }
            }

            // Check if we can do a diff-based update (same grid dimensions)
            let canDiff = previousContentHashes.count == totalCells
                && cells.count == totalCells

            if !canDiff {
                // Full rebuild
                cellSizes = Array(repeating: .zero, count: totalCells)
                cells.forEach { $0.removeFromSuperview() }
                cells.removeAll()
            } else {
                cellSizes = Array(repeating: .zero, count: totalCells)
            }

            widths = Array(repeating: 0, count: numberOfColumns)
            heights = Array(repeating: 0, count: numberOfRows)

            // Configure cells for each row and column
            for (row, rowContent) in contents.enumerated() {
                var rowHeight: CGFloat = 0

                for (column, cellString) in rowContent.enumerated() {
                    let index = row * rowContent.count + column
                    let isHeaderCell = row == 0

                    // Skip update if content hasn't changed
                    if canDiff, previousContentHashes[index] == newHashes[index] {
                        let cell = cells[index]
                        let cellSize = calculateCellSize(for: cell, cellPadding: cellPadding)
                        cellSizes[index] = cellSize
                        rowHeight = max(rowHeight, cellSize.height)
                        widths[column] = max(widths[column], cellSize.width)
                        continue
                    }

                    let cell = createOrUpdateCell(
                        at: index,
                        with: cellString,
                        maximumWidth: maximumCellWidth,
                        isHeader: isHeaderCell,
                        in: containerView
                    )

                    let cellSize = calculateCellSize(for: cell, cellPadding: cellPadding)
                    cellSizes[index] = cellSize

                    // Update row and column dimensions
                    rowHeight = max(rowHeight, cellSize.height)
                    widths[column] = max(widths[column], cellSize.width)
                }

                heights[row] = rowHeight
            }

            previousContentHashes = newHashes
        }

        // MARK: - Public Methods

        func setTheme(_ theme: MarkdownTheme) {
            self.theme = theme
            updateCellsAppearance()
        }

        func setDelegate(_ delegate: LTXLabelDelegate?) {
            self.delegate = delegate
            cells.forEach { $0.delegate = delegate }
        }

        // MARK: - Private Methods

        private func createOrUpdateCell(
            at index: Int,
            with attributedText: NSAttributedString,
            maximumWidth: CGFloat,
            isHeader: Bool,
            in containerView: UIView
        ) -> LTXLabel {
            let cell: LTXLabel

            if index >= cells.count {
                cell = LTXLabel()
                cell.isSelectable = true
                cell.backgroundColor = .clear
                cell.selectionBackgroundColor = theme.colors.selectionBackground
                cell.preferredMaxLayoutWidth = maximumWidth
                cell.delegate = delegate
                containerView.addSubview(cell)
                cells.append(cell)
            } else {
                cell = cells[index]
            }

            cell.attributedText = attributedText

            if isHeader {
                applyCellHeaderStyling(to: cell)
            } else {
                applyCellNormalStyling(to: cell)
            }

            return cell
        }

        private func calculateCellSize(for cell: LTXLabel, cellPadding: CGFloat) -> CGSize {
            let contentSize = cell.intrinsicContentSize
            return CGSize(
                width: ceil(contentSize.width) + cellPadding * 2,
                height: ceil(contentSize.height) + cellPadding * 2
            )
        }

        private func applyCellHeaderStyling(to cell: LTXLabel) {
            if let attributedText = cell.attributedText.mutableCopy() as? NSMutableAttributedString {
                let range = NSRange(location: 0, length: attributedText.length)

                attributedText.enumerateAttribute(.font, in: range, options: []) {
                    value, subRange, _ in
                    if let existingFont = value as? UIFont {
                        let boldFont = UIFont.boldSystemFont(ofSize: existingFont.pointSize)
                        attributedText.addAttribute(.font, value: boldFont, range: subRange)
                    } else {
                        attributedText.addAttribute(.font, value: theme.fonts.bold, range: subRange)
                    }
                }

                cell.attributedText = attributedText
            }
        }

        private func applyCellNormalStyling(to cell: LTXLabel) {
            if let attributedText = cell.attributedText.mutableCopy() as? NSMutableAttributedString {
                let range = NSRange(location: 0, length: attributedText.length)

                attributedText.enumerateAttribute(.foregroundColor, in: range, options: []) {
                    value, subRange, _ in
                    if value == nil {
                        attributedText.addAttribute(
                            .foregroundColor, value: theme.colors.body, range: subRange
                        )
                    }
                }

                cell.attributedText = attributedText
            }
        }

        private func updateCellsAppearance() {
            for (index, cell) in cells.enumerated() {
                cell.selectionBackgroundColor = theme.colors.selectionBackground
                let numberOfColumns = widths.count
                let row = index / numberOfColumns
                let isHeaderCell = row == 0

                if isHeaderCell {
                    applyCellHeaderStyling(to: cell)
                } else {
                    applyCellNormalStyling(to: cell)
                }
            }
        }
    }

#elseif canImport(AppKit)
    import AppKit

    final class TableViewCellManager {
        private(set) var cells: [LTXLabel] = []
        private(set) var cellSizes: [CGSize] = []
        private(set) var widths: [CGFloat] = []
        private(set) var heights: [CGFloat] = []
        private var theme: MarkdownTheme = .default
        private weak var delegate: LTXLabelDelegate?
        /// Content hashes from previous configuration, for diff-based updates.
        private var previousContentHashes: [Int] = []

        func configureCells(
            for contents: [[NSAttributedString]],
            in containerView: NSView,
            cellPadding: CGFloat,
            maximumCellWidth: CGFloat
        ) {
            let numberOfRows = contents.count
            let numberOfColumns = contents.first?.count ?? 0
            let totalCells = numberOfRows * numberOfColumns

            // Compute content hashes for diffing
            var newHashes = [Int]()
            newHashes.reserveCapacity(totalCells)
            for row in contents {
                for cell in row {
                    newHashes.append(cell.string.hashValue)
                }
            }

            // Check if we can do a diff-based update (same grid dimensions)
            let canDiff = previousContentHashes.count == totalCells
                && cells.count == totalCells

            if !canDiff {
                cellSizes = Array(repeating: .zero, count: totalCells)
                cells.forEach { $0.removeFromSuperview() }
                cells.removeAll()
            } else {
                cellSizes = Array(repeating: .zero, count: totalCells)
            }

            widths = Array(repeating: 0, count: numberOfColumns)
            heights = Array(repeating: 0, count: numberOfRows)

            for (row, rowContent) in contents.enumerated() {
                var rowHeight: CGFloat = 0

                for (column, cellString) in rowContent.enumerated() {
                    let index = row * rowContent.count + column
                    let isHeaderCell = row == 0

                    // Skip update if content hasn't changed
                    if canDiff, previousContentHashes[index] == newHashes[index] {
                        let cell = cells[index]
                        let cellSize = calculateCellSize(for: cell, cellPadding: cellPadding)
                        cellSizes[index] = cellSize
                        rowHeight = max(rowHeight, cellSize.height)
                        widths[column] = max(widths[column], cellSize.width)
                        continue
                    }

                    let cell = createOrUpdateCell(
                        at: index,
                        with: cellString,
                        maximumWidth: maximumCellWidth,
                        isHeader: isHeaderCell,
                        in: containerView
                    )

                    let cellSize = calculateCellSize(for: cell, cellPadding: cellPadding)
                    cellSizes[index] = cellSize

                    rowHeight = max(rowHeight, cellSize.height)
                    widths[column] = max(widths[column], cellSize.width)
                }

                heights[row] = rowHeight
            }

            previousContentHashes = newHashes
        }

        func setTheme(_ theme: MarkdownTheme) {
            self.theme = theme
            updateCellsAppearance()
        }

        func setDelegate(_ delegate: LTXLabelDelegate?) {
            self.delegate = delegate
            cells.forEach { $0.delegate = delegate }
        }

        private func createOrUpdateCell(
            at index: Int,
            with attributedText: NSAttributedString,
            maximumWidth: CGFloat,
            isHeader: Bool,
            in containerView: NSView
        ) -> LTXLabel {
            let cell: LTXLabel

            if index >= cells.count {
                cell = LTXLabel()
                cell.isSelectable = true
                cell.wantsLayer = true
                cell.layer?.backgroundColor = NSColor.clear.cgColor
                cell.selectionBackgroundColor = theme.colors.selectionBackground
                cell.preferredMaxLayoutWidth = maximumWidth
                cell.delegate = delegate
                containerView.addSubview(cell)
                cells.append(cell)
            } else {
                cell = cells[index]
            }

            cell.attributedText = attributedText

            if isHeader {
                applyCellHeaderStyling(to: cell)
            } else {
                applyCellNormalStyling(to: cell)
            }

            return cell
        }

        private func calculateCellSize(for cell: LTXLabel, cellPadding: CGFloat) -> CGSize {
            let contentSize = cell.intrinsicContentSize
            return CGSize(
                width: ceil(contentSize.width) + cellPadding * 2,
                height: ceil(contentSize.height) + cellPadding * 2
            )
        }

        private func applyCellHeaderStyling(to cell: LTXLabel) {
            if let attributedText = cell.attributedText.mutableCopy() as? NSMutableAttributedString {
                let range = NSRange(location: 0, length: attributedText.length)

                attributedText.enumerateAttribute(.font, in: range, options: []) {
                    value, subRange, _ in
                    if let existingFont = value as? NSFont {
                        let boldFont = NSFont.boldSystemFont(ofSize: existingFont.pointSize)
                        attributedText.addAttribute(.font, value: boldFont, range: subRange)
                    } else {
                        attributedText.addAttribute(.font, value: theme.fonts.bold, range: subRange)
                    }
                }

                cell.attributedText = attributedText
            }
        }

        private func applyCellNormalStyling(to cell: LTXLabel) {
            if let attributedText = cell.attributedText.mutableCopy() as? NSMutableAttributedString {
                let range = NSRange(location: 0, length: attributedText.length)

                attributedText.enumerateAttribute(.foregroundColor, in: range, options: []) {
                    value, subRange, _ in
                    if value == nil {
                        attributedText.addAttribute(
                            .foregroundColor, value: theme.colors.body, range: subRange
                        )
                    }
                }

                cell.attributedText = attributedText
            }
        }

        private func updateCellsAppearance() {
            for (index, cell) in cells.enumerated() {
                cell.selectionBackgroundColor = theme.colors.selectionBackground
                let numberOfColumns = widths.count
                let row = index / numberOfColumns
                let isHeaderCell = row == 0

                if isHeaderCell {
                    applyCellHeaderStyling(to: cell)
                } else {
                    applyCellNormalStyling(to: cell)
                }
            }
        }
    }
#endif
