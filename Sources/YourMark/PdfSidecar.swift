import AppKit
import Foundation
import PDFKit

struct ManualBookmark: Identifiable, Hashable, Codable, Sendable {
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

/// PDF outline (the tree Preview.app shows) plus page markers.
/// MarkItDown/pdfminer does not emit bookmarks or headings — we restore them.
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
        if let action = outline.action as? PDFActionGoTo, let page = action.destination.page {
            let idx = doc.index(for: page)
            if idx >= 0 { return idx }
        }
        return nil
    }

    /// Large-font lines, used only when the PDF has no outline of its own.
    static func fontHeadings(from url: URL) -> [ManualBookmark] {
        guard url.pathExtension.lowercased() == "pdf" else { return [] }
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return [] }
        let deadline = Date().addingTimeInterval(8)
        var items: [ManualBookmark] = []
        var seen = Set<String>()
        let pages = min(doc.pageCount, 120)
        for i in 0..<pages {
            if Date() > deadline { break }
            guard let page = doc.page(at: i) else { continue }
            // attributedString is newer PDFKit; probe so we still compile on macOS 14.
            guard page.responds(to: Selector(("attributedString"))),
                  let attr = page.value(forKey: "attributedString") as? NSAttributedString,
                  attr.length > 0 else { continue }
            let full = NSRange(location: 0, length: attr.length)
            var sizes: [CGFloat] = []
            attr.enumerateAttribute(.font, in: full) { value, _, _ in
                if let font = value as? NSFont { sizes.append(font.pointSize) }
            }
            guard sizes.count >= 8 else { continue }
            let sorted = sizes.sorted()
            let median = sorted[sorted.count / 2]
            let cutoff = max(median + 1.5, median * 1.28)
            var best: (size: CGFloat, text: String)?
            attr.enumerateAttribute(.font, in: full) { value, range, _ in
                guard let font = value as? NSFont, font.pointSize >= cutoff else { return }
                let raw = (attr.string as NSString).substring(with: range)
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard raw.count >= 4, raw.count <= 90 else { return }
                if best == nil || font.pointSize > best!.size {
                    best = (font.pointSize, raw)
                }
            }
            guard let title = best?.text else { continue }
            let key = folded(title)
            if seen.contains(key) { continue }
            seen.insert(key)
            items.append(ManualBookmark(title: title, level: 2, pageIndex: i))
            if items.count >= 80 { break }
        }
        return items
    }

    static func insertPageComments(_ markdown: String, pdf: URL?) -> String {
        let text = promotePageBreaks(markdown)
        let existing = pageCommentMap(
            text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        )
        if existing.count >= 2 { return text }
        guard let pdf, pdf.pathExtension.lowercased() == "pdf",
              let doc = PDFDocument(url: pdf), doc.pageCount > 0 else { return text }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let deadline = Date().addingTimeInterval(10)
        var cursor = 0
        var inserts: [(Int, Int)] = []
        for i in 0..<doc.pageCount {
            if Date() > deadline { break }
            let sample = distinctiveLine(doc.page(at: i)?.string)
            var found: Int?
            if let sample, sample.count >= 16 {
                let needle = folded(sample)
                found = lines[cursor...].firstIndex { line in
                    let a = folded(line)
                    return a.contains(needle) || needle.contains(a) && a.count >= 16
                }
            }
            if found == nil, i > 0, let last = inserts.last {
                let remainPages = max(1, doc.pageCount - i)
                let remainLines = max(1, lines.count - last.1)
                found = min(lines.count - 1, last.1 + max(1, remainLines / remainPages))
            }
            if let at = found {
                inserts.append((i + 1, at))
                cursor = min(lines.count, at + 1)
            }
        }
        guard !inserts.isEmpty else { return text }
        for (page, at) in inserts.reversed() {
            let idx = min(max(0, at), lines.count)
            let already = lines.indices.contains(idx) && lines[idx].contains("<!-- page")
            let before = idx > 0 && lines[idx - 1].contains("<!-- page \(page)")
            if already || before { continue }
            lines.insert("<!-- page \(page) -->", at: idx)
        }
        return lines.joined(separator: "\n")
    }

    /// Insert the PDF outline as ATX headings at the matching page / title.
    static func stitch(
        bookmarks: [ManualBookmark],
        markdown: String,
        pdf: URL?
    ) -> (text: String, bookmarks: [ManualBookmark]) {
        let text = insertPageComments(markdown, pdf: pdf)
        guard !bookmarks.isEmpty else {
            return (text, bookmarks)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var pageStarts = pageCommentMap(lines)
        if pageStarts.isEmpty, let pdf {
            pageStarts = pageLineMap(pdf: pdf, lines: lines, from: 0)
        }

        var insertAt: [Int: [(order: Int, level: Int, title: String)]] = [:]
        var located: [ManualBookmark] = bookmarks
        var cursor = 0

        for (order, mark) in bookmarks.enumerated() {
            let title = mark.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let hashes = min(6, max(1, mark.level))
            if let existing = indexOfHeading(title, in: lines, from: cursor) {
                located[order].lineIndex = existing
                cursor = existing + 1
                continue
            }
            var found = indexOfTitle(title, in: lines, from: cursor)
            if found == nil, let page = mark.pageIndex, let start = pageStarts[page] {
                let end = nextPageStart(after: page, in: pageStarts, lineCount: lines.count)
                found = indexOfTitle(title, in: lines, from: start, until: end) ?? start
            }
            if found == nil {
                found = indexOfTitle(title, in: lines, from: 0)
            }
            let at = min(found ?? min(cursor, lines.count), lines.count)
            insertAt[at, default: []].append((order, hashes, title))
            cursor = at
        }

        var out: [String] = [
            "> \(bookmarks.count) bookmarks taken from the PDF — the same tree Preview.app shows. They are also headings in this file, so they survive if you open it elsewhere.",
            "",
        ]
        var headingLine: [Int: Int] = [:]
        for i in 0...lines.count {
            if let batch = insertAt[i] {
                for item in batch.sorted(by: { $0.order < $1.order }) {
                    out.append("")
                    out.append(String(repeating: "#", count: item.level) + " " + item.title)
                    headingLine[item.order] = out.count - 1
                    out.append("")
                }
            }
            if i < lines.count {
                let line = lines[i]
                if headingText(line)?.caseInsensitiveCompare("Outline") == .orderedSame {
                    continue
                }
                out.append(line)
            }
        }
        for i in located.indices {
            if let emitted = headingLine[i] {
                located[i].lineIndex = emitted
            } else if let old = located[i].lineIndex {
                let ahead = insertAt.filter { $0.key <= old }.reduce(0) { $0 + $1.value.count * 3 }
                located[i].lineIndex = old + 2 + ahead
            }
        }
        return (out.joined(separator: "\n"), located)
    }

    static func sidecarURL(for markdown: URL) -> URL {
        markdown.deletingPathExtension().appendingPathExtension("outline.json")
    }

    static func writeSidecar(_ bookmarks: [ManualBookmark], nextTo markdown: URL) {
        guard !bookmarks.isEmpty,
              let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: sidecarURL(for: markdown), options: .atomic)
    }

    static func readSidecar(nextTo markdown: URL) -> [ManualBookmark] {
        guard let data = try? Data(contentsOf: sidecarURL(for: markdown)),
              let items = try? JSONDecoder().decode([ManualBookmark].self, from: data)
        else { return [] }
        return items
    }

    static func promotePageBreaks(_ markdown: String) -> String {
        guard markdown.contains("\u{0c}") else { return markdown }
        let parts = markdown.components(separatedBy: "\u{0c}")
        var leading = 0
        if let first = parts.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            leading = 1
        }
        var chunks: [String] = []
        for (i, part) in parts.enumerated() {
            let body = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if i >= leading {
                chunks.append("<!-- page \(i - leading + 1) -->")
            }
            if !body.isEmpty {
                chunks.append(body)
            }
        }
        return chunks.joined(separator: "\n\n")
    }

    static func pageCommentMap(_ lines: [String]) -> [Int: Int] {
        var map: [Int: Int] = [:]
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("<!-- page "), t.hasSuffix("-->") else { continue }
            let inner = t
                .dropFirst("<!-- page ".count)
                .dropLast(3)
                .trimmingCharacters(in: .whitespaces)
            if let n = Int(inner), n > 0 {
                map[n - 1] = i
            }
        }
        return map
    }

    private static func nextPageStart(after page: Int, in map: [Int: Int], lineCount: Int) -> Int {
        let later = map.keys.filter { $0 > page }.sorted()
        if let n = later.first, let idx = map[n] { return idx }
        return lineCount
    }

    private static func indexOfHeading(_ title: String, in lines: [String], from start: Int) -> Int? {
        let from = min(max(0, start), lines.count)
        return lines[from...].firstIndex { headingText($0).map { folded($0) } == folded(title) }
    }

    private static func indexOfTitle(_ title: String, in lines: [String], from start: Int, until end: Int? = nil) -> Int? {
        let lo = min(max(0, start), lines.count)
        let hi = min(end ?? lines.count, lines.count)
        guard lo < hi else { return nil }
        let needle = folded(title)
        guard needle.count >= 3 else { return nil }
        if let idx = lines[lo..<hi].firstIndex(where: { lineMatches($0, needle: needle) }) {
            return idx
        }
        return nil
    }

    static func folded(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "\u{00a0}", with: " ")
        while t.hasPrefix("#") { t.removeFirst() }
        t = t.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("[]") {
            t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        t = t.replacingOccurrences(of: "[–—−]", with: "-", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.lowercased()
    }

    private static func lineMatches(_ line: String, needle: String) -> Bool {
        let a = folded(line)
        guard a.count >= 3 else { return false }
        if a == needle { return true }
        if a.hasPrefix(needle) {
            let rest = a.dropFirst(needle.count)
            return rest.isEmpty || rest.first?.isLetter == false
        }
        if headingText(line) != nil { return false }
        if a.count > 120 { return false }
        return a.contains(needle) && needle.count >= 8
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

    static func bodyStart(in lines: [String]) -> Int {
        if let idx = lines.firstIndex(where: { $0.contains("<!-- page 1 -->") }) {
            return idx
        }
        return 0
    }

    static func line(for bookmark: ManualBookmark, in lines: [String], pdf: URL?) -> Int? {
        if let idx = bookmark.lineIndex, lines.indices.contains(idx) { return idx }
        let start = bodyStart(in: lines)
        let needle = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            if let idx = indexOfHeading(needle, in: lines, from: start) {
                return idx
            }
            if let idx = indexOfTitle(needle, in: lines, from: start) {
                return idx
            }
        }
        if let page = bookmark.pageIndex {
            let comments = pageCommentMap(lines)
            if let idx = comments[page] { return idx }
            let map = pageLineMap(pdf: pdf, lines: lines, from: start)
            if let idx = map[page] { return idx }
        }
        return nil
    }

    static func pageLineMap(pdf: URL?, lines: [String], from start: Int) -> [Int: Int] {
        guard let pdf, pdf.pathExtension.lowercased() == "pdf",
              let doc = PDFDocument(url: pdf), doc.pageCount > 0 else { return [:] }
        var map: [Int: Int] = [:]
        var cursor = start
        let bodyCount = max(1, lines.count - start)
        let deadline = Date().addingTimeInterval(8)
        for i in 0..<doc.pageCount {
            if Date() > deadline { break }
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
            .filter { $0.count >= 20 && $0.count <= 160 }
        return parts.first(where: { $0.count >= 28 }) ?? parts.first
    }
}
