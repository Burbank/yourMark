import Foundation
import PDFKit

struct ManualBookmark: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var level: Int
    var pageIndex: Int?

    init(id: UUID = UUID(), title: String, level: Int, pageIndex: Int?) {
        self.id = id
        self.title = title
        self.level = level
        self.pageIndex = pageIndex
    }
}

/// Reads the PDF outline Preview.app shows. Does not replace MarkItDown —
/// the converter still owns text and tables; this only recovers bookmarks.
enum PdfSidecar {
    static func bookmarks(from url: URL) -> [ManualBookmark] {
        guard url.pathExtension.lowercased() == "pdf" else { return [] }
        guard let doc = PDFDocument(url: url), let root = doc.outlineRoot else { return [] }
        var items: [ManualBookmark] = []

        func walk(_ outline: PDFOutline, level: Int) {
            let title = (outline.label ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var next = level
            if !title.isEmpty {
                let page = outline.destination?.page.map { doc.index(for: $0) }
                items.append(ManualBookmark(title: title, level: max(1, level), pageIndex: page))
                next = level + 1
            }
            for i in 0..<outline.numberOfChildren {
                if let child = outline.child(at: i) {
                    walk(child, level: next)
                }
            }
        }

        walk(root, level: 1)
        return items
    }

    static func outlineMarkdown(_ bookmarks: [ManualBookmark]) -> String {
        guard !bookmarks.isEmpty else { return "" }
        var lines = [
            "> Bookmarks from the PDF outline (same tree as Preview.app). Click an item in the Bookmarks pane to jump to the matching heading or first match in the converted text.",
            "",
            "## Outline",
            "",
        ]
        for item in bookmarks {
            let indent = String(repeating: "  ", count: max(0, item.level - 1))
            let page = item.pageIndex.map { " (p. \($0 + 1))" } ?? ""
            lines.append("\(indent)- \(item.title)\(page)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
