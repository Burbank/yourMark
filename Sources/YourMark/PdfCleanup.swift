import Foundation
import PDFKit

/// MarkItDown/pdfminer often glues a page into one line: running header,
/// footer, logos, and the real chapter mashed together. Rebuild the page
/// from PDFKit (which keeps line breaks), drop repeating chrome when asked,
/// and turn 8.1 / 8.1.1 titles into Markdown headings.
enum PdfCleanup {
    static func tidy(markdown: String, pdf: URL?, stripChrome: Bool) -> String {
        guard let pdf, pdf.pathExtension.lowercased() == "pdf",
              let doc = PDFDocument(url: pdf), doc.pageCount > 0
        else { return markdown }

        let chrome = stripChrome ? chromeKeys(in: doc) : []
        var pages = splitPages(markdown)
        if pages.count < 2, doc.pageCount >= 2 {
            pages = (0..<doc.pageCount).map { _ in "" }
        }

        var out: [String] = []
        let n = max(pages.count, doc.pageCount)
        for i in 0..<n {
            let raw = i < pages.count ? pages[i] : ""
            let rebuilt = rebuildPage(
                mashed: raw,
                pdfPage: doc.page(at: i),
                chrome: chrome,
                stripChrome: stripChrome
            )
            guard !rebuilt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            out.append("<!-- page \(i + 1) -->")
            out.append("")
            out.append(rebuilt)
            out.append("")
        }
        let body = out.joined(separator: "\n")
        return body.isEmpty ? markdown : body
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
        let mashedTrim = mashed.trimmingCharacters(in: .whitespacesAndNewlines)
        let mashedLines = mashedTrim
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
        let n = doc.pageCount
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
        if t.range(of: #"(?i)^page\s*:\s*\S"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"(?i)^date\s*:\s*"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"(?i)^iss\.?\s*/\s*revision"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"(?i)revision no\.?\s*:"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"(?i)^fcom\s*ii$"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"(?i)^747-400(\s+fcom)?\s*(ii)?$"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"^\d{1,2}[-/][A-Za-z]{3}[-/]\d{2,4}$"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"^(Page|Pág|Seite)\s+\d+(\s*/\s*\d+)?$"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Break a glued header+body line into pieces we can classify.
    private static func splitMashedLine(_ line: String, chrome: Set<String>) -> [String] {
        if line.count < 90 { return [line] }
        var text = line
        let cutters: [String] = [
            #"Page:\s*\S+"#,
            #"Date:\s*\d{1,2}[-/][A-Za-z]{3}[-/]\d{2,4}"#,
            #"Iss\.?\s*/\s*Revision no\.?:\s*[\d\s/]+"#,
            #"747-400\s+FCOM\s*II"#,
            #"FCOM\s*II"#,
        ]
        for pat in cutters {
            text = text.replacingOccurrences(of: pat, with: "\n", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(
            of: #"(?<![\d.])(\d+(?:\.\d+){1,5})\s+(?=[A-Z])"#,
            with: "\n$1 ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?<=[a-z])(\d{1,2})\s{2,}(?=[A-Z])"#,
            with: "\n$1 ",
            options: .regularExpression
        )
        return text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isChrome($0, chrome: chrome) }
    }

    /// "8.1 Controls and Indicators" → "## 8.1 Controls and Indicators"
    private static func numberedHeading(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let match = t.range(
            of: #"^(\d+(?:\.\d+){1,6})\s+([A-Za-z].{2,90})$"#,
            options: .regularExpression
        ) else { return nil }
        let s = String(t[match])
        guard let space = s.firstIndex(of: " ") else { return nil }
        let number = String(s[..<space])
        let title = s[s.index(after: space)...].trimmingCharacters(in: .whitespaces)
        guard title.first?.isLetter == true else { return nil }
        if title.range(of: #"(?i)^(page|date|iss)"#, options: .regularExpression) != nil { return nil }
        let parts = number.split(separator: ".").count
        let level = min(6, max(2, parts))
        return String(repeating: "#", count: level) + " " + number + " " + title
    }

    /// "1 Engine Fire Switches" → "**1 Engine Fire Switches**"
    private static func numberedCallout(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.range(of: #"^\d{1,2}\s+[A-Z][A-Za-z].{5,80}$"#, options: .regularExpression) != nil else {
            return nil
        }
        if t.contains(".") { return nil }
        return "**\(t)**"
    }

    private static func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}
