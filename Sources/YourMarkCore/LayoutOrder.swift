import Foundation
import PDFKit

/// Reading order for pages that have a sidebar or a second column.
public enum LayoutOrder {
    public struct Fragment: Sendable {
        public var text: String
        public var x: CGFloat
        public var y: CGFloat
        public var width: CGFloat
    }

    public static func fragments(on page: PDFPage) -> [Fragment] {
        guard let raw = page.string, !raw.isEmpty else { return [] }
        let ns = raw as NSString
        var items: [Fragment] = []
        var buffer = ""
        var bounds = CGRect.null
        func flush() {
            let text = buffer.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty, !bounds.isNull {
                items.append(Fragment(text: text, x: bounds.minX, y: bounds.minY, width: bounds.width))
            }
            buffer = ""
            bounds = .null
        }
        for index in 0..<ns.length {
            let ch = ns.substring(with: NSRange(location: index, length: 1))
            let box = page.characterBounds(at: index)
            if ch == "\n" || (!bounds.isNull && abs(box.minY - bounds.minY) > 3) {
                flush()
            }
            if ch == "\n" { continue }
            buffer.append(ch)
            bounds = bounds.isNull ? box : bounds.union(box)
        }
        flush()
        return items
    }

    /// Body column first, then a blockquote labelled Sidebar.
    public static func markdown(from fragments: [Fragment], pageWidth: CGFloat) -> String {
        let lines = fragments.filter { !$0.text.isEmpty }
        guard !lines.isEmpty else { return "" }
        let columns = cluster(lines)
        if columns.count < 2 {
            return lines.sorted { $0.y > $1.y }.map(\.text).joined(separator: "\n\n")
        }
        let ordered = columns.sorted { $0.map(\.x).min() ?? 0 < $1.map(\.x).min() ?? 0 }
        let left = ordered[0]
        let right = Array(ordered.dropFirst().joined())
        let leftWidth = (left.map(\.width).max() ?? 0)
        let sidebarIsLeft = leftWidth < pageWidth * 0.42
        let sidebar = sidebarIsLeft ? left : right
        let body = sidebarIsLeft ? right : left
        let bodyText = body.sorted { $0.y > $1.y }.map(\.text).joined(separator: "\n\n")
        let sideText = sidebar.sorted { $0.y > $1.y }.map { "> \($0.text)" }.joined(separator: "\n")
        return bodyText + "\n\n> **Sidebar**\n" + sideText + "\n"
    }

    /// Rewrite the markdown when any page has two columns. Leaves a single-column file alone.
    @discardableResult
    public static func apply(to markdownURL: URL, pdf: URL) -> Bool {
        guard let doc = PDFDocument(url: pdf), doc.pageCount > 0 else { return false }
        var pages: [String] = []
        var foundColumns = false
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let parts = fragments(on: page)
            let width = page.bounds(for: .mediaBox).width
            if cluster(parts).count > 1 { foundColumns = true }
            let text = markdown(from: parts, pageWidth: width)
            if !text.isEmpty { pages.append(text) }
        }
        guard foundColumns, !pages.isEmpty else { return false }
        try? pages.joined(separator: "\n\n").write(to: markdownURL, atomically: true, encoding: .utf8)
        return true
    }

    private static func cluster(_ fragments: [Fragment]) -> [[Fragment]] {
        let sorted = fragments.sorted { $0.x < $1.x }
        var columns: [[Fragment]] = []
        var current: [Fragment] = []
        var edge: CGFloat = -10_000
        for item in sorted {
            if current.isEmpty || item.x - edge < 36 {
                current.append(item)
            } else {
                columns.append(current)
                current = [item]
            }
            edge = max(edge, item.x + item.width)
        }
        if !current.isEmpty { columns.append(current) }
        return columns
    }
}
