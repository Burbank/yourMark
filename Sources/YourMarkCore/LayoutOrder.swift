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

    /// One fragment per text line. Character bounds only place the line.
    public static func fragments(on page: PDFPage) -> [Fragment] {
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
            var xs: [CGFloat] = []
            var ys: [CGFloat] = []
            for index in start..<end {
                let box = page.characterBounds(at: index)
                if box.width > 0.4, box.minX > 0.5 {
                    xs.append(box.minX)
                    ys.append(box.minY)
                }
            }
            xs.sort()
            let x = xs.first ?? 0
            let right = xs.last ?? x
            let y = ys.max() ?? 0
            items.append(Fragment(text: text, x: x, y: y, width: max(right - x, 1)))
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
    /// A right-hand column (left edge past 40% of the page) is a sidebar.
    /// A narrow left column is a sidebar. Words are copied whole.
    public static func markdown(from fragments: [Fragment], pageWidth: CGFloat) -> String {
        let lines = fragments.filter { !$0.text.isEmpty }
        guard !lines.isEmpty else { return "" }
        let columns = cluster(lines)
        if columns.count < 2 {
            return lines.map(\.text).joined(separator: "\n")
        }
        let ordered = columns.sorted { ($0.map(\.x).min() ?? 0) < ($1.map(\.x).min() ?? 0) }
        var body: [Fragment] = []
        var side: [Fragment] = []
        for (index, column) in ordered.enumerated() {
            let left = column.map(\.x).min() ?? 0
            let right = column.map { $0.x + $0.width }.max() ?? left
            let width = right - left
            let rightSidebar = left > pageWidth * 0.40
            let leftSidebar = index == 0 && width < pageWidth * 0.30 && ordered.count > 1
            if rightSidebar || leftSidebar {
                side.append(contentsOf: column)
            } else {
                body.append(contentsOf: column)
            }
        }
        guard !side.isEmpty else {
            return lines.map(\.text).joined(separator: "\n")
        }
        let bodyText = body.map(\.text).joined(separator: "\n")
        let sideText = side.map { "> \($0.text)" }.joined(separator: "\n")
        if bodyText.isEmpty {
            return "> **Sidebar**\n" + sideText + "\n"
        }
        return bodyText + "\n\n> **Sidebar**\n" + sideText + "\n"
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
            if cluster(parts).count > 1 { foundColumns = true }
            let text = markdown(from: parts, pageWidth: width)
            var block = "## Page \(index + 1)\n"
            if !text.isEmpty { block += "\n" + text }
            pages.append(block)
        }
        guard foundColumns, !pages.isEmpty else { return false }
        try? pages.joined(separator: "\n\n").write(to: markdownURL, atomically: true, encoding: .utf8)
        return true
    }

    /// Group lines that share a left edge. Keep PDFKit reading order inside each column.
    private static func cluster(_ fragments: [Fragment]) -> [[Fragment]] {
        var columns: [[Fragment]] = []
        var anchors: [CGFloat] = []
        for item in fragments {
            if let index = anchors.firstIndex(where: { item.x >= $0 - 8 && item.x - $0 < 120 }) {
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
