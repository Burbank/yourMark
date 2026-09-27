import Foundation
import PDFKit

/// MarkItDown/pdfminer often glues a page into one line: running header,
/// footer, logos, and the real chapter mashed together. Rebuild the page
/// from PDFKit (which keeps line breaks), drop repeating chrome when asked,
/// and turn 8.1 / 8.1.1 titles into Markdown headings.
///
/// PDFKit is used only on `PdfWork.queue` — never Task.detached / main init.
enum PdfCleanup {
    static func tidyAsync(markdown: String, pdf: URL?, stripChrome: Bool) async -> String {
        guard let pdf, pdf.pathExtension.lowercased() == "pdf" else { return markdown }
        let original = markdown
        let cleaned = await PdfWork.runAsync {
            tidyLocked(markdown: markdown, pdf: pdf, stripChrome: stripChrome)
        }
        let a = original.trimmingCharacters(in: .whitespacesAndNewlines).count
        let b = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).count
        if b < 40 { return original }
        if a > 200, b < a / 5 { return original }
        return cleaned
    }

    private static func tidyLocked(markdown: String, pdf: URL, stripChrome: Bool) -> String {
        guard let doc = PDFDocument(url: pdf), doc.pageCount > 0 else { return markdown }
        let chrome = stripChrome ? chromeKeys(in: doc) : []
        var pages = splitPages(markdown)
        if pages.count < 2, doc.pageCount >= 2 {
            pages = Array(repeating: "", count: doc.pageCount)
        }

        var out: [String] = []
        let n = min(max(pages.count, doc.pageCount), 800)
        for i in 0..<n {
            let raw = i < pages.count ? pages[i] : ""
            let rebuilt = rebuildPage(
                mashed: raw,
                pdfPage: i < doc.pageCount ? doc.page(at: i) : nil,
                chrome: chrome,
                stripChrome: stripChrome
            )
            let body = rebuilt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            out.append("<!-- page \(i + 1) -->")
            out.append("")
            out.append(body)
            out.append("")
        }
        let text = out.joined(separator: "\n")
        return text.isEmpty ? markdown : text
    }

    private static func splitPages(_ markdown: String) -> [String] {
        if markdown.contains("\u{0c}") {
            return markdown.components(separatedBy: "\u{0c}")
        }
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var pages: [String] = []
        var buf: [String] = []
        func flush() {
            let t = buf.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { pages.append(t) }
            buf = []
        }
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("<!-- page "), t.hasSuffix("-->") {
                flush()
                continue
            }
            buf.append(line)
        }
        flush()
        return pages
    }

    private static func rebuildPage(
        mashed: String,
        pdfPage: PDFPage?,
        chrome: Set<String>,
        stripChrome: Bool
    ) -> String {
        let kit = cleanedLines(from: pdfPage?.string, chrome: chrome, stripChrome: stripChrome)
        let mashedLines = mashed
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("![") && !$0.hasPrefix("<!--") }
        let mashedLooksBroken = looksMashed(mashedLines)

        let source: [String]
        if mashedLooksBroken, !kit.isEmpty {
            source = kit
        } else if stripChrome {
            source = mashedLines.flatMap { splitMashedLine($0, chrome: chrome) }
                .filter { !isChrome($0, chrome: chrome) }
        } else if mashedLooksBroken {
            source = kit.isEmpty ? mashedLines.flatMap { splitMashedLine($0, chrome: []) } : kit
        } else {
            source = mashedLines
        }

        var out: [String] = []
        var lastWasHeading = false
        for raw in source {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if stripChrome, isChrome(line, chrome: chrome) { continue }
            if let hit = numberedHeading(line) {
                if !out.isEmpty { out.append("") }
                out.append(hit.heading)
                if hit.rest.isEmpty {
                    lastWasHeading = true
                } else {
                    out.append(hit.rest)
                    lastWasHeading = false
                }
                continue
            }
            if let callout = numberedCallout(line) {
                if lastWasHeading { out.append("") }
                out.append(callout)
                lastWasHeading = false
                continue
            }
            if lastWasHeading { out.append("") }
            out.append(line)
            lastWasHeading = false
        }
        return out.joined(separator: "\n")
    }

    private static func looksMashed(_ lines: [String]) -> Bool {
        let body = lines.filter { !$0.hasPrefix("|") }
        guard !body.isEmpty else { return false }
        if body.count <= 2, body.joined().count > 280 { return true }
        let avg = body.map(\.count).reduce(0, +) / max(1, body.count)
        return avg > 160
    }

    private static func cleanedLines(from raw: String?, chrome: Set<String>, stripChrome: Bool) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                if stripChrome, isChrome(line, chrome: chrome) { return false }
                return true
            }
    }

    private static func chromeKeys(in doc: PDFDocument) -> Set<String> {
        var counts: [String: Int] = [:]
        let n = min(doc.pageCount, 800)
        for i in 0..<n {
            var seen = Set<String>()
            for line in cleanedLines(from: doc.page(at: i)?.string, chrome: [], stripChrome: false) {
                if numberedHeading(line) != nil { continue }
                if numberedCallout(line) != nil { continue }
                let key = fold(line)
                guard key.count >= 4, key.count <= 60 else { continue }
                if seen.contains(key) { continue }
                seen.insert(key)
                counts[key, default: 0] += 1
            }
        }
        let need = max(3, Int((Double(n) * 0.34).rounded(.up)))
        return Set(counts.compactMap { $0.value >= need ? $0.key : nil })
    }

    private static func isChrome(_ line: String, chrome: Set<String>) -> Bool {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        if numberedHeading(t) != nil { return false }
        if numberedCallout(t) != nil { return false }
        let key = fold(t)
        if chrome.contains(key) { return true }
        let lower = key
        if lower.hasPrefix("page:") { return true }
        if lower.hasPrefix("date:") { return true }
        if lower.hasPrefix("iss") && lower.contains("revision") { return true }
        if lower.contains("revision no") { return true }
        if lower == "fcom ii" || lower.hasPrefix("fcom ii ") { return true }
        if lower.hasPrefix("747-400") { return true }
        return false
    }

    /// Break a glued header+body line into pieces we can classify.
    private static func splitMashedLine(_ line: String, chrome: Set<String>) -> [String] {
        if line.count < 90 { return [line] }
        var text = line
        for token in ["Page:", "Date:", "Iss. / Revision no.:", "Iss./Revision no.:", "747-400 FCOM II", "FCOM II"] {
            text = text.replacingOccurrences(of: token, with: "\n", options: .caseInsensitive)
        }
        var pieces: [String] = []
        var current = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\n" {
                let piece = current.trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty, !isChrome(piece, chrome: chrome) { pieces.append(piece) }
                current = ""
                i = text.index(after: i)
                continue
            }
            current.append(text[i])
            i = text.index(after: i)
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty, !isChrome(last, chrome: chrome) { pieces.append(last) }
        return pieces.isEmpty ? [line] : pieces
    }

    /// "8.1 Controls and Indicators" → "## 8.1 Controls and Indicators"
    /// Also splits a glued title+paragraph. Allows "(ERF)" prefixes.
    private static func numberedHeading(_ line: String) -> (heading: String, rest: String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let first = t.first, first.isNumber else { return nil }
        var i = t.startIndex
        var dots = 0
        while i < t.endIndex {
            let ch = t[i]
            if ch.isNumber {
                i = t.index(after: i)
                continue
            }
            if ch == "." {
                let next = t.index(after: i)
                guard next < t.endIndex, t[next].isNumber else { break }
                dots += 1
                i = next
                continue
            }
            break
        }
        guard dots >= 1, dots <= 6, i < t.endIndex else { return nil }
        let numberEnd = i
        if t[i].isWhitespace {
            i = t.index(after: i)
            while i < t.endIndex, t[i].isWhitespace { i = t.index(after: i) }
        } else if !(t[i].isLetter || t[i] == "(") {
            return nil
        }
        guard i < t.endIndex else { return nil }
        let num = String(t[t.startIndex..<numberEnd])
        let after = t[i...].trimmingCharacters(in: .whitespaces)
        guard let title = takeHeadingTitle(after) else { return nil }
        let rest = String(after.dropFirst(title.count)).trimmingCharacters(in: .whitespaces)
        let low = title.lowercased()
        if low.hasPrefix("page") || low.hasPrefix("date") || low.hasPrefix("iss") { return nil }
        let level = min(6, max(2, dots + 1))
        return (String(repeating: "#", count: level) + " " + num + " " + title, rest)
    }

    private static func takeHeadingTitle(_ after: String) -> String? {
        guard !after.isEmpty else { return nil }
        var i = after.startIndex
        if after[i] == "(" {
            guard let close = after[i...].firstIndex(of: ")") else { return nil }
            i = after.index(after: close)
            while i < after.endIndex, after[i].isWhitespace { i = after.index(after: i) }
        }
        guard i < after.endIndex, after[i].isLetter else { return nil }
        if after.count <= 90 {
            return after
        }
        var last = i
        var words = 0
        var j = i
        while j < after.endIndex {
            let start = j
            while j < after.endIndex, !after[j].isWhitespace { j = after.index(after: j) }
            let word = after[start..<j]
            if words > 0, let f = word.first, f.isLowercase { break }
            if word.count > 40 { break }
            if after.distance(from: after.startIndex, to: j) > 90 { break }
            last = j
            words += 1
            if words >= 8 { break }
            while j < after.endIndex, after[j].isWhitespace { j = after.index(after: j) }
        }
        let title = String(after[after.startIndex..<last]).trimmingCharacters(in: .whitespaces)
        return title.count >= 3 ? title : nil
    }

    /// "1 Engine Fire Switches" → "**1 Engine Fire Switches**"
    private static func numberedCallout(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let first = t.first, first.isNumber else { return nil }
        var i = t.startIndex
        var digits = 0
        while i < t.endIndex, t[i].isNumber {
            digits += 1
            i = t.index(after: i)
        }
        guard (1...2).contains(digits), i < t.endIndex, t[i].isWhitespace else { return nil }
        let rest = t[i...].trimmingCharacters(in: .whitespaces)
        guard let head = rest.first, head.isLetter, head.isUppercase else { return nil }
        guard rest.count >= 6, rest.count <= 80 else { return nil }
        if rest.contains(".") { return nil }
        return "**\(t)**"
    }

    private static func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
            .lowercased()
    }

    /// `king-` at the end of a line, then `dom`, becomes `kingdom`.
    /// A hyphen that already sits between words on one line is left alone.
    static func joinLineEndHyphens(_ markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var fence = false
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) {
                fence.toggle()
                out.append(lines[i])
                i += 1
                continue
            }
            if fence {
                out.append(lines[i])
                i += 1
                continue
            }
            var line = lines[i]
            var j = i
            while j + 1 < lines.count {
                let nextTrim = lines[j + 1].trimmingCharacters(in: .whitespaces)
                if isFenceMarker(nextTrim) { break }
                if !canJoinHyphen(line, next: lines[j + 1]) { break }
                line = joinHyphen(line, lines[j + 1])
                j += 1
            }
            out.append(line)
            i = j + 1
        }
        return out.joined(separator: "\n")
    }

    /// After bookmarks are placed: `## Page N` becomes `<!-- page N -->`,
    /// and a line that is only a page number is dropped.
    static func hidePageNumbers(_ markdown: String) -> PageNumberHide {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var resolved = Array(repeating: -1, count: lines.count)
        var fence = false
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) {
                fence.toggle()
                out.append(line)
                resolved[i] = out.count - 1
                continue
            }
            if !fence, let comment = pageHeadingComment(line) {
                out.append(comment)
                resolved[i] = out.count - 1
                continue
            }
            if !fence, isLonePageNumber(trimmed) {
                continue
            }
            out.append(line)
            resolved[i] = out.count - 1
        }
        let fallback = out.isEmpty ? 0 : out.count - 1
        var next = fallback
        if !lines.isEmpty {
            for i in stride(from: lines.count - 1, through: 0, by: -1) {
                if resolved[i] >= 0 {
                    next = resolved[i]
                } else {
                    resolved[i] = next
                }
            }
        }
        return PageNumberHide(text: out.joined(separator: "\n"), oldToNew: resolved)
    }

    /// Drop a blank line that splits a sentence, and keep a single blank line
    /// between real paragraphs. `to` then a gap then `accept` becomes one paragraph.
    static func collapseEmptyLines(_ markdown: String) -> PageNumberHide {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var resolved = Array(repeating: -1, count: lines.count)
        var fence = false
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) {
                fence.toggle()
                out.append(lines[i])
                resolved[i] = out.count - 1
                i += 1
                continue
            }
            if fence || !trimmed.isEmpty {
                out.append(lines[i])
                resolved[i] = out.count - 1
                i += 1
                continue
            }
            let blankStart = i
            var j = i
            while j < lines.count {
                let nextTrim = lines[j].trimmingCharacters(in: .whitespaces)
                if isFenceMarker(nextTrim) || !nextTrim.isEmpty { break }
                j += 1
            }
            let prev = out.last?.trimmingCharacters(in: .whitespaces) ?? ""
            let next = j < lines.count ? lines[j].trimmingCharacters(in: .whitespaces) : ""
            if !prev.isEmpty, !next.isEmpty, continuesSentence(prev, next) {
                let target = max(0, out.count - 1)
                for k in blankStart..<j { resolved[k] = target }
            } else if !prev.isEmpty, !next.isEmpty {
                out.append("")
                let at = out.count - 1
                for k in blankStart..<j { resolved[k] = at }
            } else {
                let target = out.isEmpty ? 0 : max(0, out.count - 1)
                for k in blankStart..<j { resolved[k] = target }
            }
            i = j
        }
        let fallback = out.isEmpty ? 0 : out.count - 1
        var nextIndex = fallback
        if !lines.isEmpty {
            for idx in stride(from: lines.count - 1, through: 0, by: -1) {
                if resolved[idx] >= 0 {
                    nextIndex = resolved[idx]
                } else {
                    resolved[idx] = nextIndex
                }
            }
        }
        return PageNumberHide(text: out.joined(separator: "\n"), oldToNew: resolved)
    }

    private static func continuesSentence(_ prev: String, _ next: String) -> Bool {
        if prev.hasPrefix("#") || next.hasPrefix("#") { return false }
        if prev.hasPrefix("<!--") || next.hasPrefix("<!--") { return false }
        if prev.hasPrefix("![") || next.hasPrefix("![") { return false }
        if prev.hasPrefix("|") || next.hasPrefix("|") { return false }
        if prev.hasPrefix(">") || next.hasPrefix(">") { return false }
        if prev == "---" || next == "---" { return false }
        guard let first = next.first, first.isLetter else { return false }
        return !endsSentence(prev)
    }

    private static func endsSentence(_ line: String) -> Bool {
        var t = line.trimmingCharacters(in: .whitespaces)
        let closers: Set<Character> = ["\"", "”", "’", "'", ")", "]", "}", "»"]
        while let last = t.last, closers.contains(last) {
            t.removeLast()
        }
        guard let last = t.last else { return false }
        return ".!?…".contains(last)
    }

    /// A title sitting in the body, such as "Shifting from Religion to the Kingdom",
    /// becomes a Markdown heading so the reader draws it as a subheading.
    static func promoteSubheadings(_ markdown: String) -> String {
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fence = false
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) {
                fence.toggle()
                continue
            }
            if fence { continue }
            guard isSubheading(trimmed, prev: previousContent(lines, before: i), next: nextContent(lines, after: i)) else { continue }
            let prevLevel = headingLevel(previousContent(lines, before: i))
            let level = prevLevel > 0 ? min(3, prevLevel + 1) : 2
            lines[i] = String(repeating: "#", count: level) + " " + trimmed
        }
        return lines.joined(separator: "\n")
    }

    private static func previousContent(_ lines: [String], before index: Int) -> String {
        var i = index - 1
        while i >= 0 {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
            i -= 1
        }
        return ""
    }

    private static func nextContent(_ lines: [String], after index: Int) -> String {
        var i = index + 1
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
            i += 1
        }
        return ""
    }

    private static func headingLevel(_ line: String) -> Int {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("#") else { return 0 }
        var n = 0
        for ch in t {
            if ch == "#" { n += 1 } else { break }
        }
        guard (1...6).contains(n) else { return 0 }
        let rest = t.dropFirst(n)
        guard rest.first == " " else { return 0 }
        return n
    }

    private static func isSubheading(_ line: String, prev: String, next: String) -> Bool {
        if line.isEmpty || headingLevel(line) > 0 { return false }
        if line.hasPrefix("<!--") || line.hasPrefix("![") || line.hasPrefix("|") || line.hasPrefix(">") { return false }
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("•") { return false }
        if PdfSidecar.isContentsLine(line) { return false }
        guard let first = line.first, first.isLetter, first.isUppercase else { return false }
        if endsSentence(line) { return false }
        if let last = line.last, ",;:".contains(last) { return false }
        let words = line.split { $0.isWhitespace }
        guard (2...14).contains(words.count), (8...80).contains(line.count) else { return false }
        let prevOK = prev.isEmpty || endsSentence(prev) || headingLevel(prev) > 0 || prev.hasPrefix("<!--")
        guard prevOK else { return false }
        guard let nextFirst = next.first, nextFirst.isLetter, nextFirst.isUppercase else { return false }
        return true
    }

    private static func isFenceMarker(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func isBreakHyphen(_ ch: Character) -> Bool {
        ch == "-" || ch == "\u{00ad}" || ch == "\u{2010}"
    }

    private static func canJoinHyphen(_ line: String, next: String) -> Bool {
        if PdfSidecar.headingText(line) != nil { return false }
        let nextTrim = next.trimmingCharacters(in: .whitespaces)
        guard let first = nextTrim.first, first.isLetter else { return false }
        if nextTrim.hasPrefix("<!--") || nextTrim.hasPrefix("![") { return false }
        var left = line
        while let last = left.last, last.isWhitespace { left.removeLast() }
        guard let hyphen = left.last, isBreakHyphen(hyphen) else { return false }
        left.removeLast()
        guard let prev = left.last, prev.isLetter else { return false }
        let body = left.trimmingCharacters(in: .whitespaces)
        if body.isEmpty || body.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) { return false }
        return true
    }

    private static func joinHyphen(_ line: String, _ next: String) -> String {
        var left = line
        while let last = left.last, last.isWhitespace { left.removeLast() }
        if let last = left.last, isBreakHyphen(last) { left.removeLast() }
        return left + next.trimmingCharacters(in: .whitespaces)
    }

    private static func pageHeadingComment(_ line: String) -> String? {
        guard let title = PdfSidecar.headingText(line) else { return nil }
        let digits = title.filter(\.isNumber)
        guard !digits.isEmpty, let n = Int(digits), (1...9999).contains(n) else { return nil }
        if PdfSidecar.isPageLikeHeading(title) {
            return "<!-- page \(n) -->"
        }
        if title.allSatisfy(\.isNumber) {
            return "<!-- page \(n) -->"
        }
        return nil
    }

    private static func isLonePageNumber(_ trimmed: String) -> Bool {
        guard (1...4).contains(trimmed.count) else { return false }
        return trimmed.allSatisfy(\.isNumber)
    }

    /// Drop a column that is blank in the header and every body row.
    /// Fold a gutter whose text sits one column left of its heading, which is how
    /// MarkItDown wrote the two-column comparison as six sparse columns.
    /// Then drop a later plain-text copy of that table, including one whose
    /// columns were mixed together by line wraps. `oldToNew` maps the lines
    /// from before this pass.
    static func dropEmptyTableColumns(_ markdown: String) -> PageNumberHide {
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fence = false
        var i = 0
        var tables: [(start: Int, header: [String], rows: [[String]])] = []
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence.toggle()
                i += 1
                continue
            }
            guard !fence, let end = tableEnd(lines, from: i) else {
                i += 1
                continue
            }
            let header = tableCells(lines[i])
            let body = (i + 2..<end).map { tableCells(lines[$0]) }
            let grid = compactTable(header: header, rows: body)
            let rewritten = tableLines(header: grid.header, rows: grid.rows)
            if rewritten.count == end - i {
                for (offset, line) in rewritten.enumerated() {
                    lines[i + offset] = line
                }
            }
            tables.append((i, grid.header, grid.rows))
            i = end
        }
        if liftTextCutByTables(&lines) {
            tables = rescannedTables(in: lines)
        }
        let doomed = plainTableEchoes(in: lines, tables: tables)
        if doomed.isEmpty {
            return PageNumberHide(text: lines.joined(separator: "\n"), oldToNew: Array(lines.indices))
        }
        var kept: [String] = []
        kept.reserveCapacity(lines.count)
        var oldToNew = Array(repeating: 0, count: lines.count)
        for index in lines.indices {
            if doomed.contains(index) {
                oldToNew[index] = kept.count
            } else {
                oldToNew[index] = kept.count
                kept.append(lines[index])
            }
        }
        let last = max(0, kept.count - 1)
        for index in oldToNew.indices where oldToNew[index] > last {
            oldToNew[index] = last
        }
        return PageNumberHide(text: kept.joined(separator: "\n"), oldToNew: oldToNew)
    }

    /// MarkItDown sometimes emits a table in the middle of the paragraph that sits above it.
    /// Same rule on every file: an unfinished line, then a table, then the rest of that
    /// paragraph. Move the paragraph back above the table. Stop at a blank line, a heading,
    /// a page comment, or the next table. A long run with no break is cut at the first
    /// finished sentence, so a chapter is never pulled up with it.
    @discardableResult
    private static func liftTextCutByTables(_ lines: inout [String]) -> Bool {
        var cuts: [(insertAt: Int, prose: Range<Int>)] = []
        var index = 0
        var fence = false
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence.toggle()
                index += 1
                continue
            }
            guard !fence, let end = tableEnd(lines, from: index) else {
                index += 1
                continue
            }
            if let cut = proseCut(lines, tableStart: index, tableEnd: end) {
                cuts.append(cut)
            }
            index = end
        }
        guard !cuts.isEmpty else { return false }
        for cut in cuts.reversed() {
            let block = Array(lines[cut.prose])
            lines.removeSubrange(cut.prose)
            lines.insert(contentsOf: block, at: cut.insertAt)
        }
        return true
    }

    private static func proseCut(_ lines: [String], tableStart: Int, tableEnd: Int) -> (insertAt: Int, prose: Range<Int>)? {
        var previous = tableStart - 1
        while previous >= 0, lines[previous].trimmingCharacters(in: .whitespaces).isEmpty {
            previous -= 1
        }
        guard previous >= 0 else { return nil }
        let lead = lines[previous].trimmingCharacters(in: .whitespaces)
        guard !lead.hasPrefix("#"), !lead.hasPrefix("<!--"), !sentenceEnded(lead) else { return nil }
        var start = tableEnd
        while start < lines.count, lines[start].trimmingCharacters(in: .whitespaces).isEmpty {
            start += 1
        }
        guard start < lines.count, continuesCut(lines[start]) else { return nil }
        var end = start
        var taken = 0
        while end < lines.count, taken < 40 {
            let trimmed = lines[end].trimmingCharacters(in: .whitespaces)
            if isProseStop(lines, at: end, trimmed: trimmed) { break }
            end += 1
            taken += 1
        }
        guard taken > 0 else { return nil }
        if end < lines.count, isProseStop(lines, at: end, trimmed: lines[end].trimmingCharacters(in: .whitespaces)) {
            return (previous + 1, start..<end)
        }
        var close = start
        var finished = false
        while close < end {
            if sentenceEnded(lines[close]) {
                close += 1
                finished = true
                break
            }
            close += 1
        }
        guard finished else { return nil }
        return (previous + 1, start..<close)
    }

    private static func continuesCut(_ line: String) -> Bool {
        var text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.hasPrefix("#"), !text.hasPrefix("<!--"), !text.contains("|") else { return false }
        while let first = text.first, "\"“‘'([{".contains(first) {
            text.removeFirst()
        }
        guard let opening = text.first else { return false }
        return opening.isLowercase
    }

    private static func isProseStop(_ lines: [String], at index: Int, trimmed: String) -> Bool {
        if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("<!--") { return true }
        return tableEnd(lines, from: index) != nil
    }

    private static func sentenceEnded(_ line: String) -> Bool {
        var text = line.trimmingCharacters(in: .whitespaces)
        while let last = text.last, "\"”'»)]".contains(last) {
            text.removeLast()
        }
        guard let last = text.last else { return true }
        return ".!?…:".contains(last)
    }

    private static func rescannedTables(in lines: [String]) -> [(start: Int, header: [String], rows: [[String]])] {
        var tables: [(start: Int, header: [String], rows: [[String]])] = []
        var index = 0
        var fence = false
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence.toggle()
                index += 1
                continue
            }
            guard !fence, let end = tableEnd(lines, from: index) else {
                index += 1
                continue
            }
            let header = tableCells(lines[index])
            let body = (index + 2..<end).map { tableCells(lines[$0]) }
            let grid = compactTable(header: header, rows: body)
            tables.append((index, grid.header, grid.rows))
            index = end
        }
        return tables
    }

    static func isTableRowLine(_ line: String) -> Bool {
        line.contains("|")
    }

    static func isTableSeparatorLine(_ line: String) -> Bool {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let marks = cell.filter { $0 != ":" && !$0.isWhitespace }
            return !marks.isEmpty && marks.allSatisfy { $0 == "-" }
        }
    }

    static func tableCells(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Header plus body, with blank columns removed and a left gutter folded into the heading beside it.
    static func compactTable(header: [String], rows: [[String]]) -> (header: [String], rows: [[String]]) {
        let width = max(header.count, rows.map(\.count).max() ?? 0)
        guard width > 0 else { return (header, rows) }
        func pad(_ cells: [String]) -> [String] {
            if cells.count >= width { return cells }
            return cells + Array(repeating: "", count: width - cells.count)
        }
        var cols: [[String]] = (0..<width).map { index in
            [pad(header)[index]] + rows.map { pad($0)[index] }
        }
        cols = cols.filter { col in col.contains { !$0.isEmpty } }
        var index = 0
        while index + 1 < cols.count {
            let left = cols[index]
            let right = cols[index + 1]
            let complementary = zip(left, right).allSatisfy { $0.0.isEmpty || $0.1.isEmpty }
            let bodyOnLeft = left.dropFirst().contains { !$0.isEmpty }
            if left[0].isEmpty, !right[0].isEmpty, complementary, bodyOnLeft {
                cols[index + 1] = zip(left, right).map { $0.0.isEmpty ? $0.1 : $0.0 }
                cols.remove(at: index)
            } else {
                index += 1
            }
        }
        guard let sample = cols.first, !cols.isEmpty else { return (header, rows) }
        let newHeader = cols.map { $0[0] }
        let newRows = (0..<(sample.count - 1)).map { row in
            cols.map { $0[row + 1] }
        }
        return (newHeader, newRows)
    }

    static func tableEnd(_ lines: [String], from start: Int) -> Int? {
        guard start + 1 < lines.count,
              isTableRowLine(lines[start]),
              isTableSeparatorLine(lines[start + 1]) else { return nil }
        var end = start + 2
        while end < lines.count {
            let trimmed = lines[end].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || !isTableRowLine(lines[end]) { break }
            end += 1
        }
        return end
    }

    /// Line indexes of a plain-text repeat of a table. The repeat may weave the
    /// columns together, which is how a PDF text layer reads a wrapped grid.
    private static func plainTableEchoes(
        in lines: [String],
        tables: [(start: Int, header: [String], rows: [[String]])]
    ) -> Set<Int> {
        var drop = Set<Int>()
        let runs = plainRuns(in: lines)
        for table in tables where table.header.count >= 2 && table.rows.count >= 4 {
            let withHeader = columnWords(header: table.header, rows: table.rows, includeHeader: true)
            let bodyOnly = columnWords(header: table.header, rows: table.rows, includeHeader: false)
            for run in runs {
                if let span = echoPrefix(in: lines, run: run, columns: withHeader)
                    ?? echoPrefix(in: lines, run: run, columns: bodyOnly) {
                    drop.formUnion(span)
                }
            }
            var above = table.start - 1
            while above >= 0, lines[above].trimmingCharacters(in: .whitespaces).isEmpty {
                above -= 1
            }
            if above >= 0, isRepeatedHeader(lines[above], header: table.header) {
                drop.insert(above)
            }
        }
        return drop
    }

    private static func isRepeatedHeader(_ line: String, header: [String]) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.contains("|") || trimmed.hasPrefix("#") || trimmed.hasPrefix("<!--") {
            return false
        }
        let headline = header.flatMap { tableWords($0) }
        guard headline.count >= 4 else { return false }
        return tableWords(trimmed) == headline
    }

    private static func plainRuns(in lines: [String]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isTableRowLine(lines[index]) || trimmed.hasPrefix("#") || trimmed.hasPrefix("<!--")
                || trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                index += 1
                continue
            }
            let start = index
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || isTableRowLine(lines[index]) || next.hasPrefix("#") || next.hasPrefix("<!--") {
                    break
                }
                index += 1
            }
            if index > start {
                runs.append(start..<index)
            }
        }
        return runs
    }

    private static func columnWords(header: [String], rows: [[String]], includeHeader: Bool) -> [[String]] {
        let width = header.count
        guard width >= 2 else { return [] }
        var cols = Array(repeating: [String](), count: width)
        if includeHeader {
            for (column, cell) in header.enumerated() where column < width {
                cols[column].append(contentsOf: tableWords(cell))
            }
        }
        for row in rows {
            for column in 0..<width where column < row.count {
                cols[column].append(contentsOf: tableWords(row[column]))
            }
        }
        return cols
    }

    private static func tableWords(_ text: String) -> [String] {
        text.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .split { $0.isWhitespace }
            .map(String.init)
    }

    /// The copy may be the start of a paragraph that then continues with new prose.
    private static func echoPrefix(in lines: [String], run: Range<Int>, columns: [[String]]) -> Range<Int>? {
        let total = columns.reduce(0) { $0 + $1.count }
        guard total >= 12 else { return nil }
        var words: [String] = []
        for index in run {
            words.append(contentsOf: tableWords(lines[index]))
            if words.count == total, mergesColumns(words, columns) {
                return run.lowerBound..<(index + 1)
            }
            if words.count > total { return nil }
        }
        return nil
    }

    private static func mergesColumns(_ seq: [String], _ cols: [[String]]) -> Bool {
        let total = cols.reduce(0) { $0 + $1.count }
        guard seq.count == total, total >= 12, cols.count >= 2, cols.allSatisfy({ !$0.isEmpty }) else { return false }
        if cols.count == 2 { return mergesTwo(seq, cols[0], cols[1]) }
        guard cols.count <= 4, total <= 160 else { return false }
        var memo: [String: Bool] = [:]
        func go(_ at: [Int]) -> Bool {
            let used = at.reduce(0, +)
            if used == seq.count { return true }
            let key = at.map(String.init).joined(separator: ",")
            if let known = memo[key] { return known }
            let word = seq[used]
            var found = false
            for column in cols.indices where at[column] < cols[column].count && cols[column][at[column]] == word {
                var next = at
                next[column] += 1
                if go(next) {
                    found = true
                    break
                }
            }
            memo[key] = found
            return found
        }
        return go(Array(repeating: 0, count: cols.count))
    }

    private static func mergesTwo(_ seq: [String], _ left: [String], _ right: [String]) -> Bool {
        var reach = Array(repeating: Array(repeating: false, count: right.count + 1), count: left.count + 1)
        reach[0][0] = true
        for i in 0...left.count {
            for j in 0...right.count {
                let used = i + j
                if i > 0, reach[i - 1][j], used > 0, left[i - 1] == seq[used - 1] {
                    reach[i][j] = true
                }
                if j > 0, reach[i][j - 1], used > 0, right[j - 1] == seq[used - 1] {
                    reach[i][j] = true
                }
            }
        }
        return reach[left.count][right.count]
    }

    private static func tableLines(header: [String], rows: [[String]]) -> [String] {
        guard !header.isEmpty else { return [] }
        var lines = [formatTableRow(header), formatTableSeparator(header.count)]
        lines.append(contentsOf: rows.map { formatTableRow($0) })
        return lines
    }

    private static func formatTableRow(_ cells: [String]) -> String {
        "|" + cells.map { " \($0) " }.joined(separator: "|") + "|"
    }

    private static func formatTableSeparator(_ count: Int) -> String {
        "|" + Array(repeating: " --- ", count: count).joined(separator: "|") + "|"
    }
}

struct PageNumberHide: Sendable {
    var text: String
    var oldToNew: [Int]

    func lineIndex(_ old: Int) -> Int {
        guard !oldToNew.isEmpty else { return 0 }
        if old < 0 { return oldToNew[0] }
        if old >= oldToNew.count { return oldToNew[oldToNew.count - 1] }
        return oldToNew[old]
    }
}

/// A short fragment, a space, another short fragment: `Ma ny`, `Wh en`.
enum SplitWords {
    static func suspectIndexes(in lines: [String], range: Range<Int>) -> [Int] {
        var fence = false
        var hits: [Int] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence.toggle()
                continue
            }
            guard range.contains(i), !fence, isSuspect(line) else { continue }
            hits.append(i)
        }
        return hits
    }

    static func neighborWords(lines: [String], index: Int) -> (before: String, after: String) {
        func take(_ s: String, last: Bool) -> String {
            let parts = s.split { $0.isWhitespace }.map(String.init)
            if last { return parts.suffix(6).joined(separator: " ") }
            return parts.prefix(6).joined(separator: " ")
        }
        let before = index > 0 ? take(lines[index - 1], last: true) : ""
        let after = index + 1 < lines.count ? take(lines[index + 1], last: false) : ""
        return (before, after)
    }

    /// Same letters means the model only removed spaces. Anything else stays.
    static func accept(original: String, proposed: String) -> String {
        let next = proposed.trimmingCharacters(in: .newlines)
        if next == original { return original }
        if original.contains("<!--") { return original }
        if PdfSidecar.headingText(original) != nil { return original }
        if next.isEmpty { return original }
        guard letters(original) == letters(next) else { return original }
        return next
    }

    static func isSuspect(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("<!--") { return false }
        if trimmed.hasPrefix("![") || trimmed.hasPrefix("|") || trimmed.hasPrefix(">") { return false }
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            if !chars[i].isLetter {
                i += 1
                continue
            }
            let start = i
            while i < chars.count, chars[i].isLetter { i += 1 }
            let firstLen = i - start
            guard (2...4).contains(firstLen),
                  i < chars.count, chars[i] == " ",
                  i + 1 < chars.count, chars[i + 1].isLetter, chars[i + 1].isLowercase
            else { continue }
            let secondStart = i + 1
            var j = secondStart
            while j < chars.count, chars[j].isLetter { j += 1 }
            let secondLen = j - secondStart
            guard (2...4).contains(secondLen) else { continue }
            let first = String(chars[start..<i]).lowercased()
            let second = String(chars[secondStart..<j]).lowercased()
            let secondKnown = words.contains(second)
            let firstKnown = words.contains(first)
            if !secondKnown { return true }
            if !firstKnown, firstLen == 2, secondLen == 2 { return true }
        }
        return false
    }

    private static func letters(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Real short words. A fragment such as `ny` is not in here, so `Ma ny` is sent.
    private static let words: Set<String> = [
        "a", "am", "an", "as", "at", "be", "by", "do", "go", "he", "if", "in", "is", "it",
        "me", "my", "no", "of", "ok", "on", "or", "so", "to", "up", "us", "we",
        "all", "and", "any", "are", "but", "can", "did", "for", "get", "got", "had", "has",
        "her", "him", "his", "how", "its", "let", "may", "not", "now", "one", "our", "out",
        "own", "say", "see", "she", "the", "too", "two", "was", "way", "who", "yes", "yet", "you",
        "also", "back", "been", "both", "call", "came", "come", "down", "each", "even", "find",
        "from", "give", "good", "have", "here", "into", "just", "know", "last", "left", "life",
        "like", "long", "look", "made", "make", "many", "more", "most", "much", "must", "name",
        "need", "next", "only", "over", "part", "same", "some", "such", "take", "than", "that",
        "them", "then", "they", "this", "time", "upon", "very", "want", "well", "were", "what",
        "when", "will", "with", "word", "work", "year", "your",
        "al", "el", "la", "lo", "un", "una", "de", "del", "los", "las", "su", "sus", "mi", "tu",
        "que", "por", "con", "sin", "se", "le", "les", "ya", "es", "ha", "son", "hay",
        "muy", "tan", "tal", "como", "para", "pero", "este", "esta", "esto", "ese", "esa",
        "het", "een", "van", "te", "op", "dat", "die", "dit", "niet", "met", "als", "ook",
        "aan", "om", "bij", "tot", "uit", "voor", "naar", "maar", "dan", "nog", "wel",
        "zijn", "haar", "hij", "zij", "wij", "jij", "mij", "hun", "ons", "wat", "wie", "hoe",
        "geen", "kan", "zal", "zou", "heb", "ben", "bent", "uw", "je", "ze", "er", "nu", "zo",
        "toch", "ik", "en",
    ]
}

/// PDFKit is not safe from Task.detached or from AppModel.init on the main thread
/// while SwiftUI is still putting the window up. One serial queue, both sides.
enum PdfWork {
    private static let key = DispatchSpecificKey<UInt8>()
    static let queue: DispatchQueue = {
        let q = DispatchQueue(label: "com.burbank.yourmark.pdf", qos: .userInitiated)
        q.setSpecific(key: key, value: 1)
        return q
    }()

    static func runAsync<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            queue.async {
                cont.resume(returning: body())
            }
        }
    }
}
