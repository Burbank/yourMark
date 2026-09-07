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
            if let heading = numberedHeading(line) {
                if !out.isEmpty { out.append("") }
                out.append(heading)
                lastWasHeading = true
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
    /// Character scan — no NSRegularExpression (invalid patterns abort the process).
    private static func numberedHeading(_ line: String) -> String? {
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
        guard dots >= 1, dots <= 6, i < t.endIndex, t[i].isWhitespace else { return nil }
        let number = String(t[t.startIndex..<i])
        let title = t[i...].trimmingCharacters(in: .whitespaces)
        guard let head = title.first, head.isLetter else { return nil }
        guard title.count >= 3, title.count <= 90 else { return nil }
        let low = title.lowercased()
        if low.hasPrefix("page") || low.hasPrefix("date") || low.hasPrefix("iss") { return nil }
        let level = min(6, max(2, dots + 1))
        return String(repeating: "#", count: level) + " " + number + " " + title
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
