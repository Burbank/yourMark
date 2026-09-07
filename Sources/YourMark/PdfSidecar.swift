import Foundation
import PDFKit

struct ManualBookmark: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var level: Int
    var pageIndex: Int?
    var lineIndex: Int?

    init(id: UUID = UUID(), title: String, level: Int, pageIndex: Int?, lineIndex: Int? = nil) {
        self.id = id
        self.title = title
        self.level = level
        self.pageIndex = pageIndex
        self.lineIndex = lineIndex
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
                items.append(ManualBookmark(
                    title: title,
                    level: max(1, level),
                    pageIndex: pageIndex(from: outline, in: doc)
                ))
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

    static func pageIndex(from outline: PDFOutline, in doc: PDFDocument) -> Int? {
        if let page = outline.destination?.page {
            let idx = doc.index(for: page)
            if idx >= 0 { return idx }
        }
        if let action = outline.action as? PDFActionGoTo, let page = action.destination?.page {
            let idx = doc.index(for: page)
            if idx >= 0 { return idx }
        }
        return nil
    }

    static func outlineMarkdown(_ bookmarks: [ManualBookmark]) -> String {
        guard !bookmarks.isEmpty else { return "" }
        var lines = [
            "> Bookmarks from the PDF outline (same tree as Preview.app). Click an item in the Bookmarks pane to jump into the converted text — not this list.",
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

    /// First line of real content after the injected Outline list, so jumps
    /// do not land on the bookmark list at the top of the file.
    static func bodyStart(in lines: [String]) -> Int {
        guard let start = lines.firstIndex(where: {
            headingText($0)?.caseInsensitiveCompare("Outline") == .orderedSame
        }) else { return 0 }
        var i = start + 1
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if let heading = headingText(t), heading.caseInsensitiveCompare("Outline") != .orderedSame {
                return i
            }
            if t.isEmpty || t.hasPrefix(">") || t.hasPrefix("-") || t.hasPrefix("*") {
                i += 1
                continue
            }
            return i
        }
        return i
    }

    static func headingText(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("#") else { return nil }
        var n = 0
        for ch in t {
            if ch == "#" { n += 1 } else { break }
        }
        guard (1...6).contains(n) else { return nil }
        let title = t.drop(while: { $0 == "#" || $0 == " " }).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    static func line(for bookmark: ManualBookmark, in lines: [String], pdf: URL?) -> Int? {
        if let idx = bookmark.lineIndex, lines.indices.contains(idx) { return idx }
        let start = bodyStart(in: lines)
        let needle = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            if let idx = lines[start...].firstIndex(where: {
                headingText($0)?.caseInsensitiveCompare(needle) == .orderedSame
            }) {
                return idx
            }
            if let idx = lines[start...].firstIndex(where: {
                guard let h = headingText($0) else { return false }
                return h.localizedCaseInsensitiveContains(needle) || needle.localizedCaseInsensitiveContains(h)
            }) {
                return idx
            }
        }
        if let page = bookmark.pageIndex {
            let map = pageLineMap(pdf: pdf, lines: lines, from: start)
            if let idx = map[page] { return idx }
            let labels = ["## Page \(page + 1)", "Page \(page + 1)", "(p. \(page + 1))"]
            if let idx = lines[start...].firstIndex(where: { line in
                labels.contains(where: { line.localizedCaseInsensitiveContains($0) })
            }) {
                return idx
            }
        }
        if !needle.isEmpty, needle.count >= 4 {
            if let idx = lines[start...].firstIndex(where: {
                $0.localizedCaseInsensitiveContains(needle)
            }) {
                return idx
            }
        }
        return nil
    }

    static func pageLineMap(pdf: URL?, lines: [String], from start: Int) -> [Int: Int] {
        guard let pdf, pdf.pathExtension.lowercased() == "pdf",
              let doc = PDFDocument(url: pdf), doc.pageCount > 0 else { return [:] }
        var map: [Int: Int] = [:]
        var cursor = start
        let bodyCount = max(1, lines.count - start)
        for i in 0..<doc.pageCount {
            if let sample = distinctiveLine(doc.page(at: i)?.string), sample.count >= 16 {
                if let idx = lines[cursor...].firstIndex(where: {
                    $0.localizedCaseInsensitiveContains(sample)
                }) {
                    map[i] = idx
                    cursor = idx + 1
                    continue
                }
            }
            let approx = start + Int((Double(i) / Double(max(doc.pageCount, 1))) * Double(bodyCount))
            map[i] = min(lines.count - 1, max(start, approx))
        }
        return map
    }

    private static func distinctiveLine(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parts = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 20 }
        return parts.first(where: { $0.count >= 28 }) ?? parts.first
    }
}
