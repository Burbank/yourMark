import Foundation
import PDFKit

/// Reading order for pages that have a sidebar or a second column.
/// Lines come from PDFKit's string, so a word is never split on a glyph.
public enum LayoutOrder {
    public struct Fragment: Sendable {
        public var text: String
        public var x: CGFloat
        public var y: CGFloat
        public var width: CGFloat
    }

    /// One fragment per PDFKit line. A line is never cut inside a word.
    public static func fragments(on page: PDFPage) -> [Fragment] {
        let media = page.bounds(for: .mediaBox)
        if let selection = page.selection(for: media) {
            let lines = selection.selectionsByLine().compactMap { line -> Fragment? in
                let text = (line.string ?? "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let box = line.bounds(for: page)
                guard box.width > 0.5, box.height > 0.2, !box.isNull, !box.isInfinite else { return nil }
                return Fragment(text: text, x: box.minX, y: box.minY, width: box.width)
            }
            if !lines.isEmpty { return lines }
        }
        return fragmentsFromNewlines(on: page)
    }

    /// Fallback when PDFKit has a string but no line selections.
    /// Breaks only on newlines, so a descender cannot split a word.
    private static func fragmentsFromNewlines(on page: PDFPage) -> [Fragment] {
        guard let raw = page.string, !raw.isEmpty else { return [] }
        let ns = raw as NSString
        var items: [Fragment] = []
        var start = 0
        func emit(_ end: Int) {
            defer { start = end + 1 }
            guard end > start else { return }
            let text = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            var minX = CGFloat.greatestFiniteMagnitude
            var maxX = CGFloat.leastNormalMagnitude
            var top = CGFloat.leastNormalMagnitude
            for index in start..<end {
                let box = page.characterBounds(at: index)
                guard box.width > 0.4, box.minX > 0.5, !box.isNull, !box.isInfinite else { continue }
                minX = min(minX, box.minX)
                maxX = max(maxX, box.maxX)
                top = max(top, box.maxY)
            }
            let x = minX == .greatestFiniteMagnitude ? 0 : minX
            let width = maxX > minX ? maxX - minX : 1
            items.append(Fragment(text: text, x: x, y: top, width: width))
        }
        for index in 0..<ns.length {
            if ns.substring(with: NSRange(location: index, length: 1)) == "\n" {
                emit(index)
            }
        }
        emit(ns.length)
        return items
    }

    /// Body column first, then a blockquote labelled Sidebar.
    /// A column whose left edge is past 40% of the page is a sidebar (About Bitwise).
    /// A left column is a sidebar only when it is much narrower than the column beside it.
    /// Words are copied whole.
    public static func markdown(from fragments: [Fragment], pageWidth: CGFloat) -> String {
        let lines = fragments.filter { !$0.text.isEmpty }
        guard !lines.isEmpty else { return "" }
        let columns = cluster(lines, pageWidth: pageWidth)
        if columns.count < 2 {
            return lines.sorted { $0.y > $1.y }.map(\.text).joined(separator: "\n")
        }
        let ordered = columns.sorted { ($0.map(\.x).min() ?? 0) < ($1.map(\.x).min() ?? 0) }
        var body: [Fragment] = []
        var side: [Fragment] = []
        let rightWidth = ordered.dropFirst().map { span($0).width }.max() ?? 0
        for (index, column) in ordered.enumerated() {
            let box = span(column)
            let rightSidebar = box.left > pageWidth * 0.40
            let leftSidebar = index == 0 && rightWidth > 0 && box.width < rightWidth * 0.55
            let reading = column.sorted { $0.y > $1.y }
            if rightSidebar || leftSidebar {
                side.append(contentsOf: reading)
            } else {
                body.append(contentsOf: reading)
            }
        }
        guard !side.isEmpty else {
            return lines.sorted { $0.y > $1.y }.map(\.text).joined(separator: "\n")
        }
        let bodyText = body.map(\.text).joined(separator: "\n")
        let sideText = side.map { "> \($0.text)" }.joined(separator: "\n")
        if bodyText.isEmpty {
            return "> **Sidebar**\n" + sideText + "\n"
        }
        return bodyText + "\n\n> **Sidebar**\n" + sideText + "\n"
    }

    private static func span(_ column: [Fragment]) -> (left: CGFloat, width: CGFloat) {
        let left = column.map(\.x).min() ?? 0
        let right = column.map { $0.x + $0.width }.max() ?? left
        return (left, max(right - left, 1))
    }

    /// Rewrite the markdown when any page has two columns.
    /// Keeps a `## Page N` heading on every page.
    /// `keepExisting` leaves Docling or MarkItDown markdown untouched.
    @discardableResult
    public static func apply(to markdownURL: URL, pdf: URL, keepExisting: Bool = false) -> Bool {
        if keepExisting { return false }
        guard let doc = PDFDocument(url: pdf), doc.pageCount > 0 else { return false }
        var pages: [String] = []
        var foundColumns = false
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let parts = fragments(on: page)
            let width = page.bounds(for: .mediaBox).width
            if cluster(parts, pageWidth: width).count > 1 { foundColumns = true }
            let text = markdown(from: parts, pageWidth: width)
            var block = "## Page \(index + 1)\n"
            if !text.isEmpty { block += "\n" + text }
            pages.append(block)
        }
        guard foundColumns, !pages.isEmpty else { return false }
        try? pages.joined(separator: "\n\n").write(to: markdownURL, atomically: true, encoding: .utf8)
        return true
    }

    /// Group lines whose left edges sit in the same column.
    /// The gap keeps a TOC number with its title and leaves a right-hand sidebar alone.
    private static func cluster(_ fragments: [Fragment], pageWidth: CGFloat) -> [[Fragment]] {
        let gap = max(96, pageWidth * 0.20)
        var columns: [[Fragment]] = []
        var anchors: [CGFloat] = []
        for item in fragments {
            if let index = anchors.firstIndex(where: { abs(item.x - $0) < gap }) {
                columns[index].append(item)
                anchors[index] = min(anchors[index], item.x)
            } else {
                columns.append([item])
                anchors.append(item.x)
            }
        }
        return columns
    }
}
