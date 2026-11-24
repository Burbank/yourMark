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

    /// A glyph the converter could not read is U+FFFD (the � mark). Drop it,
    /// and the other characters that are not letters, marks, or punctuation.
    /// A gap those marks left is closed. Fenced code is left alone.
    static func dropUnrecognizedCharacters(_ markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        out.reserveCapacity(lines.count)
        var fence = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) {
                fence.toggle()
                out.append(line)
                continue
            }
            if fence || !line.unicodeScalars.contains(where: isUnrecognized) {
                out.append(line)
                continue
            }
            var kept = ""
            kept.unicodeScalars.reserveCapacity(line.unicodeScalars.count)
            for scalar in line.unicodeScalars where !isUnrecognized(scalar) {
                kept.unicodeScalars.append(scalar)
            }
            out.append(closeGap(kept))
        }
        return out.joined(separator: "\n")
    }

    private static func isUnrecognized(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        if v == 0xFFFD || v == 0xFFFC { return true }
        if v == 0xFFFE || v == 0xFFFF { return true }
        if (0xFDD0...0xFDEF).contains(v) { return true }
        if v > 0xFFFF, (v & 0xFFFE) == 0xFFFE { return true }
        if v < 0x20, v != 0x09, v != 0x0A, v != 0x0D { return true }
        if (0x7F...0x9F).contains(v) { return true }
        return false
    }

    /// The hole left by a run of missing glyphs becomes one space, or two
    /// before a trailing page number so the contents row still reads as one.
    private static func closeGap(_ line: String) -> String {
        var squeezed = ""
        squeezed.reserveCapacity(line.count)
        var spaces = 0
        for ch in line {
            if ch == " " {
                spaces += 1
                continue
            }
            if spaces > 0 {
                squeezed.append(" ")
                spaces = 0
            }
            squeezed.append(ch)
        }
        if spaces > 0 { squeezed.append(" ") }
        guard let regex = try? NSRegularExpression(pattern: #"\s(\d{1,4})\s*$"#) else { return squeezed }
        let ns = squeezed as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: squeezed, range: full), match.numberOfRanges == 2 else { return squeezed }
        let number = ns.substring(with: match.range(at: 1))
        let head = ns.substring(to: match.range.location).trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty else { return squeezed }
        return head + "  " + number
    }

    /// A styled initial on its own line, `T` then `he final…`, becomes `The final…`.
    /// A quote in front of the letter stays: `“A` then `ll roads` becomes `“All roads`.
    /// The next line must begin with a lowercase letter, so a chapter number before a heading stays.
    static func joinDropCaps(_ markdown: String) -> String {
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
            if !fence, let cap = dropCapPieces(trimmed),
               i + 1 < lines.count,
               let joined = joinedDropCap(cap, next: lines[i + 1]) {
                out.append(joined)
                i += 2
                continue
            }
            out.append(lines[i])
            i += 1
        }
        return out.joined(separator: "\n")
    }

    private static func dropCapPieces(_ trimmed: String) -> (prefix: String, letter: Character)? {
        var rest = trimmed
        var prefix = ""
        let openers: Set<Character> = ["\"", "“", "‘", "'", "«", "(", "["]
        while let first = rest.first, openers.contains(first) {
            prefix.append(first)
            rest.removeFirst()
        }
        let closers: Set<Character> = ["\"", "”", "’", "'", "»", ")", "]"]
        while let last = rest.last, closers.contains(last) {
            rest.removeLast()
        }
        guard rest.count == 1, let letter = rest.first, letter.isLetter else { return nil }
        return (prefix, letter)
    }

    private static func joinedDropCap(_ cap: (prefix: String, letter: Character), next: String) -> String? {
        let nextTrim = next.trimmingCharacters(in: .whitespaces)
        if nextTrim.isEmpty || isFenceMarker(nextTrim) { return nil }
        if nextTrim.hasPrefix("#") || nextTrim.hasPrefix("<!--") || nextTrim.hasPrefix("![") || nextTrim.hasPrefix("|") {
            return nil
        }
        guard let first = nextTrim.first, first.isLowercase else { return nil }
        return cap.prefix + String(cap.letter) + nextTrim
    }

    /// `king-` at the end of a line, then `dom`, becomes `kingdom`.
    /// A hyphen that already sits between words on one line is left alone.
    static func joinLineEndHyphens(_ markdown: String) -> String {
        let lines = joinDropCaps(dropUnrecognizedCharacters(markdown))
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
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
        return SplitWords.rejoinKnownWords(out.joined(separator: "\n"))
    }

    /// Keep the first `<!-- page N -->`. A later copy of the same number is
    /// dropped, and so is a chapter title repeated as the first line of a page.
    /// The sentence join that follows can then close the gap.
    static func dropRepeatedPageMarks(_ markdown: String) -> PageNumberHide {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var resolved = Array(repeating: -1, count: lines.count)
        var fence = false
        var seenPages = Set<Int>()
        var seenTitles = Set<String>()
        var atPageStart = false
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) {
                fence.toggle()
                out.append(line)
                resolved[i] = out.count - 1
                atPageStart = false
                continue
            }
            if fence {
                out.append(line)
                resolved[i] = out.count - 1
                continue
            }
            if let page = pageCommentNumber(trimmed) {
                if seenPages.contains(page) { continue }
                seenPages.insert(page)
                out.append(line)
                resolved[i] = out.count - 1
                atPageStart = true
                continue
            }
            if trimmed.isEmpty {
                out.append(line)
                resolved[i] = out.count - 1
                continue
            }
            if atPageStart, isRepeatedRunningHeader(trimmed, seen: seenTitles) {
                atPageStart = false
                continue
            }
            atPageStart = false
            if let title = PdfSidecar.headingText(line) {
                rememberTitle(title, into: &seenTitles)
            }
            out.append(line)
            resolved[i] = out.count - 1
        }
        fillUnresolved(&resolved, count: out.count)
        return PageNumberHide(text: out.joined(separator: "\n"), oldToNew: resolved)
    }

    private static func pageCommentNumber(_ trimmed: String) -> Int? {
        guard trimmed.hasPrefix("<!-- page "), trimmed.hasSuffix("-->") else { return nil }
        let inner = trimmed
            .dropFirst("<!-- page ".count)
            .dropLast(3)
            .trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty, inner.allSatisfy(\.isNumber), let n = Int(inner), n > 0 else { return nil }
        return n
    }

    private static func rememberTitle(_ title: String, into seen: inout Set<String>) {
        let folded = PdfSidecar.folded(title)
        guard !folded.isEmpty else { return }
        seen.insert(folded)
        let core = headingCore(folded)
        guard core != folded, core.first?.isLetter == true else { return }
        seen.insert(core)
    }

    /// "1.3 Introduction" and "7 MetaNoia" share a core with the running header.
    private static func headingCore(_ folded: String) -> String {
        guard let range = folded.range(of: #"^\d+(?:\.\d+)*\s+"#, options: .regularExpression) else {
            return folded
        }
        return String(folded[range.upperBound...])
    }

    /// The first line of a page that repeats a heading already in the file.
    private static func isRepeatedRunningHeader(_ trimmed: String, seen: Set<String>) -> Bool {
        if trimmed.hasPrefix("![") || trimmed.hasPrefix("|") || trimmed.hasPrefix(">") { return false }
        if PdfSidecar.isContentsLine(trimmed) { return false }
        let title = PdfSidecar.headingText(trimmed) ?? trimmed
        guard title.count <= 80 else { return false }
        let folded = PdfSidecar.folded(title)
        return folded.count >= 2 && seen.contains(folded)
    }

    static func fillUnresolved(_ resolved: inout [Int], count: Int) {
        let fallback = count == 0 ? 0 : count - 1
        var next = fallback
        if !resolved.isEmpty {
            for i in stride(from: resolved.count - 1, through: 0, by: -1) {
                if resolved[i] >= 0 {
                    next = resolved[i]
                } else {
                    resolved[i] = next
                }
            }
        }
    }

    /// A whole line that repeats at least ten times, with more than one word,
    /// is a header or footer. `stripLines` is the header switch. An empty page
    /// marker is always dropped, so the sentence join can close the gap.
    /// Page numbers are not renumbered.
    static func dropRepeatingChrome(_ markdown: String, stripLines: Bool) -> PageNumberHide {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var counts: [String: Int] = [:]
        if stripLines {
            var fence = false
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if isFenceMarker(trimmed) {
                    fence.toggle()
                    continue
                }
                if fence { continue }
                if let key = chromeLineKey(trimmed) {
                    counts[key, default: 0] += 1
                }
            }
        }
        let repeated = Set(counts.filter { $0.value >= 10 }.map(\.key))
        let footerAddresses = repeated.filter(isFooterAddress)
        var keptHeading = Set<String>()
        var skipBlankAfterBanner = false
        var mid: [String] = []
        var toMid = Array(repeating: -1, count: lines.count)
        var fence = false
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) {
                fence.toggle()
                mid.append(line)
                toMid[i] = mid.count - 1
                continue
            }
            if fence {
                mid.append(line)
                toMid[i] = mid.count - 1
                continue
            }
            if isBookmarkBanner(trimmed) {
                skipBlankAfterBanner = true
                continue
            }
            if skipBlankAfterBanner, trimmed.isEmpty {
                skipBlankAfterBanner = false
                continue
            }
            skipBlankAfterBanner = false
            if stripLines, let key = chromeLineKey(trimmed), repeated.contains(key) {
                if PdfSidecar.headingText(line) != nil, !keptHeading.contains(key) {
                    keptHeading.insert(key)
                    mid.append(line)
                    toMid[i] = mid.count - 1
                }
                continue
            }
            let kept = stripLines ? stripGluedFooters(line, addresses: footerAddresses) : line
            mid.append(kept)
            toMid[i] = mid.count - 1
        }

        var drop = Set<Int>()
        var fence2 = false
        var i = 0
        while i < mid.count {
            let trimmed = mid[i].trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) {
                fence2.toggle()
                i += 1
                continue
            }
            if fence2 || pageCommentNumber(trimmed) == nil {
                i += 1
                continue
            }
            var j = i + 1
            var hasBody = false
            while j < mid.count {
                let next = mid[j].trimmingCharacters(in: .whitespaces)
                if isFenceMarker(next) { break }
                if pageCommentNumber(next) != nil { break }
                if !next.isEmpty {
                    hasBody = true
                    break
                }
                j += 1
            }
            if !hasBody {
                drop.insert(i)
                for k in (i + 1)..<j { drop.insert(k) }
                i = j
            } else {
                i += 1
            }
        }

        var out: [String] = []
        var midToOut = Array(repeating: -1, count: mid.count)
        for (index, line) in mid.enumerated() where !drop.contains(index) {
            out.append(line)
            midToOut[index] = out.count - 1
        }
        var resolved = toMid.map { slot in
            slot >= 0 && slot < midToOut.count ? midToOut[slot] : -1
        }
        fillUnresolved(&resolved, count: out.count)
        return PageNumberHide(text: out.joined(separator: "\n"), oldToNew: resolved)
    }

    /// A header-sized line: more than one word, not a picture, table, or page marker.
    private static func chromeLineKey(_ trimmed: String) -> String? {
        if trimmed.isEmpty || trimmed.hasPrefix("![") || trimmed.hasPrefix("|") { return nil }
        if pageCommentNumber(trimmed) != nil { return nil }
        if PdfSidecar.isContentsLine(trimmed) { return nil }
        let title = PdfSidecar.headingText(trimmed) ?? trimmed
        guard title.count <= 80 else { return nil }
        if isFooterAddress(title) {
            return PdfSidecar.folded(title)
        }
        let words = title.split { $0.isWhitespace }.filter { $0.contains(where: \.isLetter) }
        guard (2...14).contains(words.count) else { return nil }
        let folded = PdfSidecar.folded(title)
        guard folded.count >= 2 else { return nil }
        return folded
    }

    /// A line that is only a web address, such as a site name repeated in the footer.
    private static func isFooterAddress(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.contains(where: \.isWhitespace) { return false }
        guard (8...80).contains(trimmed.count), trimmed.contains(".") else { return false }
        var body = trimmed.lowercased()
        if body.hasPrefix("https://") { body.removeFirst(8) }
        else if body.hasPrefix("http://") { body.removeFirst(7) }
        if body.hasPrefix("www.") { body.removeFirst(4) }
        guard body.contains("."), !body.hasPrefix("."), !body.hasSuffix(".") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        return body.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// A footer address stuck to the end of a word, with no space, is peeled off.
    /// A sentence that names the site on purpose, with a space before it, stays.
    private static func stripGluedFooters(_ line: String, addresses: Set<String>) -> String {
        guard !addresses.isEmpty else { return line }
        var result = line
        var changed = true
        while changed {
            changed = false
            for address in addresses {
                guard let range = result.range(of: address, options: .caseInsensitive) else { continue }
                let before = result[..<range.lowerBound]
                guard let prev = before.last, prev.isLetter else { continue }
                result.removeSubrange(range)
                changed = true
                break
            }
        }
        return result
    }

    private static func isBookmarkBanner(_ trimmed: String) -> Bool {
        trimmed.hasPrefix(">") && trimmed.contains("bookmarks taken from the PDF")
    }

    /// Drop a line that only repeats the heading above it, and join a title
    /// that wrapped so the last words became their own heading.
    /// "Why Life Is Not Working—and Why Religion" / "Cannot Fix It"
    /// becomes one heading.
    static func repairHeadingLayout(_ markdown: String) -> PageNumberHide {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var resolved = Array(repeating: -1, count: lines.count)
        var fence = false
        var lastHeading = ""
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
            if fence {
                out.append(lines[i])
                resolved[i] = out.count - 1
                i += 1
                continue
            }
            if PdfSidecar.headingText(trimmed) == nil, isHeadingEcho(trimmed, near: lastHeading) {
                i += 1
                continue
            }
            if let title = PdfSidecar.headingText(lines[i]),
               let prev = lastContentIndex(out),
               isWrappedTitle(out[prev], heading: title),
               nextBodyContinues(lines, after: i) {
                let level = hashCount(lines[i])
                let lead = out[prev].trimmingCharacters(in: .whitespaces)
                out[prev] = String(repeating: "#", count: level) + " " + lead + " " + title
                lastHeading = lead + " " + title
                i += 1
                continue
            }
            if let title = PdfSidecar.headingText(lines[i]) {
                lastHeading = title
            }
            out.append(lines[i])
            resolved[i] = out.count - 1
            i += 1
        }
        fillUnresolved(&resolved, count: out.count)
        return PageNumberHide(text: out.joined(separator: "\n"), oldToNew: resolved)
    }

    private static func isHeadingEcho(_ trimmed: String, near heading: String) -> Bool {
        if heading.isEmpty || trimmed.isEmpty { return false }
        if trimmed.hasPrefix("![") || trimmed.hasPrefix("|") || trimmed.hasPrefix("<!--") { return false }
        if PdfSidecar.isContentsLine(trimmed) { return false }
        let line = PdfSidecar.folded(trimmed)
        let core = headingCore(PdfSidecar.folded(heading))
        return line == core || line == PdfSidecar.folded(heading)
    }

    /// A compound title wrapped before its last words. Two parallel lines that
    /// start with the same word stay apart.
    private static func isWrappedTitle(_ previous: String, heading: String) -> Bool {
        let prev = previous.trimmingCharacters(in: .whitespaces)
        if prev.isEmpty || PdfSidecar.headingText(prev) != nil { return false }
        if prev.hasPrefix("<!--") || prev.hasPrefix("![") || prev.hasPrefix("|") { return false }
        if endsSentence(prev) { return false }
        guard let first = prev.first, first.isUppercase else { return false }
        let prevWords = prev.split { $0.isWhitespace }
        let headWords = heading.split { $0.isWhitespace }
        guard (3...18).contains(prevWords.count), (1...6).contains(headWords.count) else { return false }
        let folded = prev.lowercased()
        let compound = folded.contains("—") || folded.contains("–")
            || folded.range(of: #"\b(and|or)\b"#, options: .regularExpression) != nil
        guard compound else { return false }
        let prevFirst = prevWords[0].trimmingCharacters(in: .punctuationCharacters).lowercased()
        let headFirst = headWords[0].trimmingCharacters(in: .punctuationCharacters).lowercased()
        return prevFirst != headFirst
    }

    private static func nextBodyContinues(_ lines: [String], after index: Int) -> Bool {
        var j = index + 1
        while j < lines.count {
            let trimmed = lines[j].trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) { return false }
            if trimmed.isEmpty {
                j += 1
                continue
            }
            if PdfSidecar.headingText(trimmed) != nil { return false }
            if trimmed.hasPrefix("<!--") || trimmed.hasPrefix("![") || trimmed.hasPrefix("|") { return false }
            guard let first = trimmed.first, first.isLetter, first.isUppercase else { return false }
            return trimmed.split { $0.isWhitespace }.count >= 4
        }
        return false
    }

    private static func markCount(_ line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var n = 0
        for ch in trimmed {
            if ch == "#" { n += 1 } else { break }
        }
        return n
    }

    private static func hashCount(_ line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var n = 0
        for ch in trimmed {
            if ch == "#" { n += 1 } else { break }
        }
        return min(6, max(2, n == 0 ? 2 : n))
    }

    private static func lastContentIndex(_ lines: [String]) -> Int? {
        var i = lines.count - 1
        while i >= 0 {
            if !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { return i }
            i -= 1
        }
        return nil
    }

    /// A Roman numeral under a chapter heading is the PDF’s chapter ornament.
    /// The title lines under it repeat the heading, so they are removed and the
    /// heading is what the reader shows. A heading that stopped mid-phrase
    /// (“…and”, “…of the”) takes the next short line. A long sentence that was
    /// marked as a heading goes back to body text.
    static func tidyDisplayedHeadings(_ markdown: String) -> PageNumberHide {
        let original = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let joined = joinSplitHeadings(original)
        let absorbed = absorbRomanTitles(joined.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        let demoted = demoteSentenceHeadings(absorbed.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        let map = original.indices.map { index in
            demoted.lineIndex(absorbed.lineIndex(joined.lineIndex(index)))
        }
        return PageNumberHide(text: demoted.text, oldToNew: map)
    }

    private static let danglingTitleWords: Set<String> = [
        "and", "or", "the", "of", "a", "an", "as", "to", "for", "which", "where", "through", "but", "not", "yet"
    ]

    /// "…Corrupted and" / "Why Sons of God…" becomes one heading.
    private static func joinSplitHeadings(_ lines: [String]) -> PageNumberHide {
        var out: [String] = []
        var resolved = Array(repeating: -1, count: lines.count)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if let title = PdfSidecar.headingText(line),
               danglingTitleWords.contains(titleWords(title).last ?? ""),
               let j = nextContentIndex(lines, after: i),
               isShortTitleLine(lines[j]) {
                let extra = PdfSidecar.headingText(lines[j]) ?? lines[j].trimmingCharacters(in: .whitespaces)
                let marks = String(repeating: "#", count: markCount(line))
                resolved[i] = out.count
                out.append(marks + " " + title + " " + extra)
                var k = i + 1
                while k <= j {
                    if k == j {
                        resolved[k] = out.count - 1
                    }
                    k += 1
                }
                i = j + 1
                continue
            }
            resolved[i] = out.count
            out.append(line)
            i += 1
        }
        fillUnresolved(&resolved, count: out.count)
        return PageNumberHide(text: out.joined(separator: "\n"), oldToNew: resolved)
    }

    /// Drop "IV" and "The Failure of" / "Sensory Living" when the heading already says that.
    private static func absorbRomanTitles(_ lines: [String]) -> PageNumberHide {
        var drop = Set<Int>()
        var i = 0
        while i < lines.count {
            guard isChapterRoman(lines[i]) else {
                i += 1
                continue
            }
            guard let heading = previousContentIndex(lines, before: i),
                  PdfSidecar.headingText(lines[heading]) != nil
            else {
                i += 1
                continue
            }
            drop.insert(i)
            let target = titleWords(PdfSidecar.headingText(lines[heading]) ?? "")
            var need = bag(target)
            var j = i + 1
            var taken: [Int] = []
            while j < lines.count, !need.isEmpty {
                if lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    j += 1
                    continue
                }
                guard isShortTitleLine(lines[j]) || PdfSidecar.headingText(lines[j]) != nil else { break }
                let piece = titleWords(PdfSidecar.headingText(lines[j]) ?? lines[j])
                guard !piece.isEmpty, canTake(piece, from: &need) else { break }
                taken.append(j)
                j += 1
            }
            if need.isEmpty {
                drop.formUnion(taken)
                i = (taken.last ?? i) + 1
            } else {
                i += 1
            }
        }
        return applyLineEdits(lines, drop: drop)
    }

    /// A heading that is really the start of a sentence goes back to the paragraph.
    private static func demoteSentenceHeadings(_ lines: [String]) -> PageNumberHide {
        var replace: [Int: String] = [:]
        for i in lines.indices {
            guard let title = PdfSidecar.headingText(lines[i]) else { continue }
            if isCitationLine(title) {
                replace[i] = title
                continue
            }
            guard isSentenceHeading(title) else { continue }
            guard let j = nextContentIndex(lines, after: i) else { continue }
            let next = lines[j].trimmingCharacters(in: .whitespaces)
            if PdfSidecar.headingText(next) != nil || next.hasPrefix("<!--") || next.hasPrefix("•") || next.hasPrefix("![") {
                continue
            }
            let continues = titleWords(next).count >= 4 || titleWords(title).count >= 12
            if continues {
                replace[i] = title
            }
        }
        return applyLineEdits(lines, replace: replace)
    }

    private static func isSentenceHeading(_ title: String) -> Bool {
        if title.range(of: #"[.?!]\s+\S"#, options: .regularExpression) != nil { return true }
        let count = titleWords(title).count
        if count >= 14 { return true }
        if count >= 10, title.contains(",") || title.contains("\"") || title.contains("“") { return true }
        if count >= 8, danglingTitleWords.contains(titleWords(title).last ?? "") { return true }
        return false
    }

    private static func isChapterRoman(_ line: String) -> Bool {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix(".") { text.removeLast() }
        guard (1...7).contains(text.count) else { return false }
        guard text.range(
            of: #"^(M{0,3})(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$"#,
            options: .regularExpression
        ) != nil else { return false }
        return true
    }

    private static func isShortTitleLine(_ line: String) -> Bool {
        if PdfSidecar.headingText(line) != nil { return true }
        let text = line.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || isChapterRoman(text) { return false }
        if text.hasPrefix("<!--") || text.hasPrefix("![") || text.hasPrefix("|") || text.hasPrefix("•") { return false }
        if text.hasPrefix("- ") || text.hasPrefix("* ") { return false }
        if text.count > 60 { return false }
        if let last = text.last, ".!?".contains(last) { return false }
        let count = titleWords(text).count
        return (1...10).contains(count)
    }

    private static func titleWords(_ text: String) -> [String] {
        var folded = PdfSidecar.folded(text)
        if let range = folded.range(of: #"^\d+(?:\.\d+)*\s+"#, options: .regularExpression) {
            folded = String(folded[range.upperBound...])
        }
        folded = folded.replacingOccurrences(of: "’", with: "'")
        return folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
    }

    private static func bag(_ words: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for word in words { counts[word, default: 0] += 1 }
        return counts
    }

    private static func canTake(_ words: [String], from need: inout [String: Int]) -> Bool {
        var next = need
        for word in words {
            guard let count = next[word], count > 0 else { return false }
            next[word] = count - 1
            if next[word] == 0 { next.removeValue(forKey: word) }
        }
        need = next
        return true
    }

    private static func nextContentIndex(_ lines: [String], after index: Int) -> Int? {
        var i = index + 1
        while i < lines.count {
            if !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { return i }
            i += 1
        }
        return nil
    }

    private static func previousContentIndex(_ lines: [String], before index: Int) -> Int? {
        var i = index - 1
        while i >= 0 {
            if !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { return i }
            i -= 1
        }
        return nil
    }

    private static func applyLineEdits(
        _ lines: [String],
        drop: Set<Int> = [],
        replace: [Int: String] = [:]
    ) -> PageNumberHide {
        var out: [String] = []
        var resolved = Array(repeating: -1, count: lines.count)
        for i in lines.indices {
            if drop.contains(i) { continue }
            resolved[i] = out.count
            out.append(replace[i] ?? lines[i])
        }
        // A dropped ornament belongs to the heading above it. Mapping it forward
        // lands the bookmark on the first body line, and the heading sits just
        // above the window.
        var previous = 0
        for i in lines.indices {
            if resolved[i] >= 0 {
                previous = resolved[i]
            } else if drop.contains(i) {
                resolved[i] = previous
            }
        }
        fillUnresolved(&resolved, count: out.count)
        return PageNumberHide(text: out.joined(separator: "\n"), oldToNew: resolved)
    }

    /// A heading parked on the previous chapter, with no words of its own before
    /// the next heading, moves to the later line where its title actually starts.
    /// Two outline entries often share one PDF page. The body that follows belongs
    /// to whichever title shows up first.
    static func relocateStolenHeadings(_ markdown: String) -> PageNumberHide {
        let original = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var text = markdown
        var combined = Array(original.indices)
        var guardCount = 0
        while guardCount < 8 {
            guardCount += 1
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let job = stolenHeading(in: lines) else { break }
            let pass = moveHeading(lines, from: job.source, to: job.dest)
            text = pass.text
            combined = combined.map { pass.lineIndex($0) }
        }
        return PageNumberHide(text: text, oldToNew: combined)
    }

    /// The later of two stacked headings, when the text underneath is the earlier title.
    private static func stolenHeading(in lines: [String]) -> (source: Int, dest: Int)? {
        var i = 0
        while i < lines.count {
            guard PdfSidecar.headingText(lines[i]) != nil else {
                i += 1
                continue
            }
            var j = i + 1
            while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                j += 1
            }
            guard j < lines.count,
                  PdfSidecar.headingText(lines[j]) != nil,
                  markCount(lines[j]) <= markCount(lines[i])
            else {
                i += 1
                continue
            }
            let earlier = PdfSidecar.headingText(lines[i]) ?? ""
            let later = PdfSidecar.headingText(lines[j]) ?? ""
            guard let firstHit = PdfSidecar.titleAnchor(earlier, in: lines, from: j + 1, until: lines.count),
                  let dest = PdfSidecar.titleAnchor(later, in: lines, from: firstHit, until: lines.count),
                  dest > j + 4
            else {
                i = j
                continue
            }
            return (j, dest)
        }
        return nil
    }

    /// Replace the real title line with the heading, and delete the heading from its old place.
    private static func moveHeading(_ lines: [String], from source: Int, to dest: Int) -> PageNumberHide {
        guard source != dest, source >= 0, dest > source, dest < lines.count else {
            return PageNumberHide(text: lines.joined(separator: "\n"), oldToNew: Array(lines.indices))
        }
        let heading = lines[source]
        var out: [String] = []
        var resolved = Array(repeating: -1, count: lines.count)
        var placed = dest
        let replacing = PdfSidecar.headingText(lines[dest]) != nil
        for i in lines.indices {
            if i == source { continue }
            if i == dest, replacing {
                placed = out.count
                out.append(heading)
                resolved[i] = placed
                continue
            }
            if i == dest, !replacing {
                placed = out.count
                out.append(heading)
            }
            resolved[i] = out.count
            out.append(lines[i])
        }
        resolved[source] = placed
        fillUnresolved(&resolved, count: out.count)
        return PageNumberHide(text: out.joined(separator: "\n"), oldToNew: resolved)
    }

    /// A title set with a space between every letter is written the way the PDF
    /// stores it. "Y O U R G I F T" becomes "YOUR GIFT", with the word spaces
    /// the PDF already has. The line count does not change.
    static func closeTrackedLetters(_ markdown: String, pdf: URL?) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fence = false
        var needs = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) {
                fence.toggle()
                continue
            }
            if fence { continue }
            if trackedBody(of: line) != nil {
                needs = true
                break
            }
        }
        guard needs, let pdf, let corpus = PdfWork.sync({ trackedCorpus(from: pdf) }) else { return markdown }
        fence = false
        var out: [String] = []
        var changed = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) {
                fence.toggle()
                out.append(line)
                continue
            }
            if !fence, let fixed = restoredTrackedLine(line, corpus: corpus) {
                out.append(fixed)
                changed = true
                continue
            }
            out.append(line)
        }
        return changed ? out.joined(separator: "\n") : markdown
    }

    private struct TrackedCorpus {
        let chars: [Character]
        let letterPos: [Int]
        let key: String
    }

    private static func trackedCorpus(from pdf: URL) -> TrackedCorpus? {
        guard pdf.pathExtension.lowercased() == "pdf",
              let doc = PDFDocument(url: pdf),
              doc.pageCount > 0 else { return nil }
        var text = ""
        for i in 0..<min(doc.pageCount, 800) {
            if let page = doc.page(at: i)?.string {
                text += page
                text += "\n"
            }
        }
        let chars = Array(text)
        var pos: [Int] = []
        var key = ""
        key.reserveCapacity(chars.count)
        for (i, ch) in chars.enumerated() {
            guard ch.isLetter || ch.isNumber else { continue }
            pos.append(i)
            key.append(contentsOf: String(ch).uppercased())
        }
        guard key.count >= 8 else { return nil }
        return TrackedCorpus(chars: chars, letterPos: pos, key: key)
    }

    /// Heading marks stay. The body is the spaced title, when this line is one.
    private static func trackedBody(of line: String) -> (prefix: String, body: String)? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmed = String(line.drop { $0 == " " || $0 == "\t" })
        if trimmed.hasPrefix("<!--") || trimmed.hasPrefix("![") || trimmed.hasPrefix("|") || trimmed.hasPrefix(">") {
            return nil
        }
        var marks = ""
        var body = trimmed
        var hashes = 0
        for ch in trimmed {
            if ch == "#" { hashes += 1 } else { break }
        }
        if (1...6).contains(hashes) {
            let after = trimmed.dropFirst(hashes)
            if after.first == " " {
                marks = String(repeating: "#", count: hashes) + " "
                body = String(after.drop { $0 == " " })
            }
        }
        guard isTrackedBody(body) else { return nil }
        return (indent + marks, body)
    }

    private static func isTrackedBody(_ body: String) -> Bool {
        let parts = body.split(separator: " ").map(String.init)
        guard parts.count >= 5, parts.allSatisfy(isThinToken) else { return false }
        let letters = parts.filter { $0.first?.isLetter == true }.count
        return letters >= 5
    }

    /// One letter, or a letter with a period stuck to it ("S.").
    private static func isThinToken(_ part: String) -> Bool {
        if part.count <= 1 { return true }
        guard let first = part.first, first.isLetter || first.isNumber else { return false }
        return part.dropFirst().allSatisfy { !$0.isLetter && !$0.isNumber }
    }

    private static func restoredTrackedLine(_ line: String, corpus: TrackedCorpus) -> String? {
        guard let tracked = trackedBody(of: line),
              let text = bestTrackedSlice(tracked.body, corpus: corpus),
              !isTrackedBody(text) else { return nil }
        return tracked.prefix + text
    }

    /// The PDF slice whose letters match, preferring the same capitals as the title.
    private static func bestTrackedSlice(_ body: String, corpus: TrackedCorpus) -> String? {
        let want = letterKey(body)
        guard want.count >= 5, corpus.key.contains(want) else { return nil }
        let sourceLetters = body.filter { $0.isLetter || $0.isNumber }
        var search = corpus.key.startIndex
        var best: (score: Int, span: Int, text: String)?
        while search < corpus.key.endIndex,
              let range = corpus.key.range(of: want, range: search..<corpus.key.endIndex) {
            let start = corpus.key.distance(from: corpus.key.startIndex, to: range.lowerBound)
            let end = corpus.key.distance(from: corpus.key.startIndex, to: range.upperBound) - 1
            if start >= 0, end < corpus.letterPos.count {
                var lo = corpus.letterPos[start]
                var hi = corpus.letterPos[end]
                while lo > 0, isTrackedGlue(corpus.chars[lo - 1]) { lo -= 1 }
                while hi + 1 < corpus.chars.count, isTrackedGlue(corpus.chars[hi + 1]) { hi += 1 }
                let collapsed = String(corpus.chars[lo...hi])
                    .split { $0.isWhitespace }
                    .joined(separator: " ")
                if letterKey(collapsed) == want {
                    let score = caseScore(sourceLetters, collapsed)
                    let span = hi - lo
                    if best == nil || score > best!.score || (score == best!.score && span < best!.span) {
                        best = (score, span, collapsed)
                    }
                }
            }
            search = range.upperBound
        }
        return best?.text
    }

    private static func isTrackedGlue(_ ch: Character) -> Bool {
        !ch.isWhitespace && !ch.isLetter && !ch.isNumber
    }

    private static func letterKey(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func caseScore(_ source: String, _ slice: String) -> Int {
        let found = slice.filter { $0.isLetter || $0.isNumber }
        var score = 0
        for (a, b) in zip(source, found) where a.isUppercase == b.isUppercase {
            score += 1
        }
        return score
    }

    /// A line much longer than the file’s usual line is wrapped at a period or a comma,
    /// so it no longer jumps past the lines around it.
    static func wrapLongLines(_ markdown: String) -> PageNumberHide {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let usual = usualLineLength(lines)
        let limit = max(usual + 28, Int((Double(usual) * 1.45).rounded()))
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
            if fence || !shouldWrap(trimmed, limit: limit) {
                out.append(line)
                resolved[i] = out.count - 1
                continue
            }
            let pieces = wrapPieces(trimmed, usual: usual, limit: limit)
            resolved[i] = out.count
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            for (n, piece) in pieces.enumerated() {
                out.append(n == 0 ? indent + piece : piece)
            }
        }
        return PageNumberHide(text: out.joined(separator: "\n"), oldToNew: resolved)
    }

    private static func usualLineLength(_ lines: [String]) -> Int {
        var lengths: [Int] = []
        var fence = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isFenceMarker(trimmed) {
                fence.toggle()
                continue
            }
            if fence || !isWrapProse(trimmed) { continue }
            let n = trimmed.count
            if (20...110).contains(n) { lengths.append(n) }
        }
        guard !lengths.isEmpty else { return 68 }
        lengths.sort()
        return lengths[lengths.count / 2]
    }

    private static func isWrapProse(_ trimmed: String) -> Bool {
        if trimmed.isEmpty { return false }
        if trimmed.hasPrefix("#") || trimmed.hasPrefix("<!--") || trimmed.hasPrefix("![") || trimmed.hasPrefix("|") { return false }
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return false }
        if PdfSidecar.isContentsLine(trimmed) { return false }
        return true
    }

    private static func shouldWrap(_ trimmed: String, limit: Int) -> Bool {
        isWrapProse(trimmed) && trimmed.count > limit
    }

    /// Break a long line into pieces near the usual length. A period wins, then a comma.
    private static func wrapPieces(_ line: String, usual: Int, limit: Int) -> [String] {
        var rest = line
        var parts: [String] = []
        while rest.count > limit {
            guard let cut = wrapCut(rest, usual: usual, limit: limit) else { break }
            let left = rest.prefix(cut).trimmingCharacters(in: .whitespaces)
            let right = rest.dropFirst(cut).trimmingCharacters(in: .whitespaces)
            if left.count < 12 || right.count < 12 { break }
            parts.append(String(left))
            rest = String(right)
        }
        if !rest.isEmpty { parts.append(rest) }
        return parts.isEmpty ? [line] : parts
    }

    /// Index just after the break, so the punctuation stays on the first piece.
    private static func wrapCut(_ line: String, usual: Int, limit: Int) -> Int? {
        let chars = Array(line)
        let minCut = max(16, usual / 2)
        let ceiling = min(chars.count - 12, limit + 8)
        var bestSentence: (at: Int, distance: Int)?
        var bestComma: (at: Int, distance: Int)?
        var bestSpace: (at: Int, distance: Int)?
        var i = 0
        while i < chars.count - 12 {
            let ch = chars[i]
            let boundary = ch == "." || ch == "!" || ch == "?" || ch == "," || ch == ";" || ch == ":"
            if boundary, i + 1 < chars.count, chars[i + 1] == " ", i + 1 >= minCut, goodBreakWord(chars, before: i) {
                let at = i + 2
                let distance = abs(at - usual)
                if ch == "." || ch == "!" || ch == "?" {
                    if at <= ceiling, bestSentence == nil || distance < bestSentence!.distance {
                        bestSentence = (at, distance)
                    }
                } else if at <= ceiling, bestComma == nil || distance < bestComma!.distance {
                    bestComma = (at, distance)
                }
            }
            if ch == " ", i + 1 >= minCut, i + 1 <= limit {
                let at = i + 1
                let distance = abs(at - usual)
                if bestSpace == nil || distance < bestSpace!.distance {
                    bestSpace = (at, distance)
                }
            }
            i += 1
        }
        if let sentence = bestSentence {
            return sentence.at
        }
        if let comma = bestComma {
            return comma.at
        }
        return bestSpace?.at
    }

    /// Skip “Mr.” and “3.” so a short token is not treated as the end of a sentence.
    private static func goodBreakWord(_ chars: [Character], before index: Int) -> Bool {
        var j = index - 1
        var count = 0
        while j >= 0, chars[j].isLetter {
            count += 1
            j -= 1
        }
        return count >= 3
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

    /// A line that is only a citation, such as a name with a chapter and verse.
    private static func isCitationLine(_ text: String) -> Bool {
        var title = text.trimmingCharacters(in: .whitespaces)
        if let heading = PdfSidecar.headingText(title) { title = heading }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "()[]“”\"'."))
        guard (3...80).contains(title.count) else { return false }
        let citation = #"(?:[1-3]\s+)?[A-Za-z][A-Za-z'’]*(?:\s+(?:of|the|and|[A-Za-z][A-Za-z'’]*)){0,3}\s+\d{1,3}\s*:\s*\d{1,3}(?:\s*[–—-]\s*\d{1,3})?"#
        let parts = title.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            part.range(of: "^\(citation)$", options: .regularExpression) != nil
        }
    }

    private static func isSubheading(_ line: String, prev: String, next: String) -> Bool {
        if line.isEmpty || headingLevel(line) > 0 { return false }
        if isCitationLine(line) { return false }
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

    /// `Wh en` becomes `When` when the two pieces are one real word.
    /// Two real words side by side, such as `in to`, stay apart.
    static func rejoinKnownWords(_ markdown: String) -> String {
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fence = false
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence.toggle()
                continue
            }
            if fence || trimmed.hasPrefix("<!--") { continue }
            lines[i] = rejoinLine(lines[i])
        }
        return lines.joined(separator: "\n")
    }

    private static func rejoinLine(_ line: String) -> String {
        let chars = Array(line)
        var out = ""
        var i = 0
        while i < chars.count {
            guard chars[i].isLetter else {
                out.append(chars[i])
                i += 1
                continue
            }
            let start = i
            while i < chars.count, chars[i].isLetter { i += 1 }
            let first = String(chars[start..<i])
            let canTry = (1...8).contains(first.count)
                && i < chars.count && chars[i] == " "
                && i + 1 < chars.count && chars[i + 1].isLetter && chars[i + 1].isLowercase
            if canTry {
                let secondStart = i + 1
                var j = secondStart
                while j < chars.count, chars[j].isLetter { j += 1 }
                let second = String(chars[secondStart..<j])
                let joined = (first + second).lowercased()
                let firstKnown = words.contains(first.lowercased())
                let secondKnown = words.contains(second.lowercased())
                if (1...6).contains(second.count), words.contains(joined), !(firstKnown && secondKnown) {
                    var word = joined
                    if first.first?.isUppercase == true {
                        word = word.prefix(1).uppercased() + word.dropFirst()
                    }
                    out += word
                    i = j
                    continue
                }
            }
            out += first
        }
        return out
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

/// Repeating margin lines, and a temporary PDF whose crop box hides them.
struct MarginRead: Sendable {
    var title = ""
    var author = ""
    var cropped: URL?

    var record: BookRecord {
        var next = BookRecord()
        next.title = title
        if !author.isEmpty { next.authors = [author] }
        return next
    }
}

extension PdfCleanup {
    /// Lines in the top or bottom band that repeat across the book. When `writeCrop`
    /// is set, a temporary PDF hides those lines. The original file is not changed.
    static func readMargin(_ pdf: URL, writeCrop: Bool) -> MarginRead {
        PdfWork.sync { readMarginLocked(pdf, writeCrop: writeCrop) }
    }

    private struct MarginHit {
        var key: String
        var text: String
        var top: Bool
        var minY: CGFloat
        var maxY: CGFloat
        var pageNumber: Bool
    }

    private static func readMarginLocked(_ pdf: URL, writeCrop: Bool) -> MarginRead {
        guard pdf.pathExtension.lowercased() == "pdf",
              let doc = PDFDocument(url: pdf),
              doc.pageCount >= 3 else { return MarginRead() }
        let pageCount = min(doc.pageCount, 800)
        let need = max(3, Int((Double(pageCount) * 0.34).rounded(.up)))
        var perPage: [[MarginHit]] = Array(repeating: [], count: pageCount)
        var tallies: [String: (text: String, pages: Int)] = [:]
        var numberedPages = 0

        for index in 0..<pageCount {
            guard let page = doc.page(at: index) else { continue }
            let box = page.bounds(for: .cropBox)
            guard box.height > 40, box.width > 40 else { continue }
            let hits = marginHits(on: page, box: box)
            if hits.contains(where: \.pageNumber) { numberedPages += 1 }
            var seen = Set<String>()
            for hit in hits where !hit.pageNumber && seen.insert(hit.key).inserted {
                var tally = tallies[hit.key] ?? (hit.text, 0)
                tally.pages += 1
                if tally.text.isEmpty { tally.text = hit.text }
                tallies[hit.key] = tally
            }
            perPage[index] = hits
        }

        let pageNumbersQualify = numberedPages >= need
        var furniture = Set<String>()
        for (key, tally) in tallies where tally.pages >= need {
            furniture.insert(key)
        }
        var read = catalogFromMargin(tallies: tallies, need: need)
        guard writeCrop, !furniture.isEmpty || pageNumbersQualify else { return read }
        var changed = false
        for index in 0..<pageCount {
            guard let page = doc.page(at: index) else { continue }
            let box = page.bounds(for: .cropBox)
            let hits = perPage[index].filter { hit in
                (pageNumbersQualify && hit.pageNumber) || furniture.contains(hit.key)
            }
            guard let crop = croppedBox(box, hits: hits), crop != box else { continue }
            page.setBounds(crop, for: .cropBox)
            changed = true
        }
        guard changed else { return read }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("yourmark-margin-\(UUID().uuidString).pdf")
        if doc.write(to: dest) {
            read.cropped = dest
        }
        return read
    }

    private static func marginHits(on page: PDFPage, box: CGRect) -> [MarginHit] {
        guard let selection = page.selection(for: box) else { return [] }
        let topCut = box.maxY - box.height * 0.18
        let bottomCut = box.minY + box.height * 0.18
        let maxHeight = box.height * 0.12
        var hits: [MarginHit] = []
        for line in selection.selectionsByLine() {
            let bounds = line.bounds(for: page)
            guard bounds.height > 0, bounds.height <= maxHeight, bounds.width > 0 else { continue }
            let text = (line.string ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let mid = bounds.midY
            let top = mid >= topCut
            let bottom = mid <= bottomCut
            guard top || bottom else { continue }
            hits.append(MarginHit(
                key: marginKey(text),
                text: text,
                top: top,
                minY: bounds.minY,
                maxY: bounds.maxY,
                pageNumber: isMarginPageNumber(text)
            ))
        }
        return hits
    }

    /// The line on the most pages is the title. A second, shorter line can be the author.
    private static func catalogFromMargin(
        tallies: [String: (text: String, pages: Int)],
        need: Int
    ) -> MarginRead {
        let ranked = tallies.values
            .filter { item in
                item.pages >= need
                    && !isMarginPageNumber(item.text)
                    && !isMarginDate(item.text)
                    && !isFooterAddress(item.text)
                    && item.text.contains(where: \.isLetter)
            }
            .sorted { lhs, rhs in
                if lhs.pages != rhs.pages { return lhs.pages > rhs.pages }
                return lhs.text.count > rhs.text.count
            }
        guard let title = ranked.first else { return MarginRead() }
        var read = MarginRead()
        read.title = title.text
        let titleKey = marginKey(title.text)
        if let author = ranked.dropFirst().first(where: { item in
            let words = item.text.split(whereSeparator: \.isWhitespace)
            guard (2...4).contains(words.count) else { return false }
            guard !item.text.contains(where: \.isNumber) else { return false }
            guard item.text.count < title.text.count else { return false }
            return marginKey(item.text) != titleKey
        }) {
            read.author = author.text
        }
        return read
    }

    private static func croppedBox(_ box: CGRect, hits: [MarginHit]) -> CGRect? {
        let limitTop = box.maxY - box.height * 0.15
        let limitBottom = box.minY + box.height * 0.15
        var maxY = box.maxY
        var minY = box.minY
        if let lowest = hits.filter(\.top).map(\.minY).min() {
            maxY = min(box.maxY, max(lowest - 6, limitTop))
        }
        if let highest = hits.filter({ !$0.top }).map(\.maxY).max() {
            minY = max(box.minY, min(highest + 6, limitBottom))
        }
        guard maxY - minY >= box.height * 0.5 else { return nil }
        guard maxY < box.maxY - 1 || minY > box.minY + 1 else { return nil }
        return CGRect(x: box.minX, y: minY, width: box.width, height: maxY - minY)
    }

    private static func marginKey(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func isMarginPageNumber(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, words.count <= 4, text.count <= 24 else { return false }
        let digits = text.contains(where: \.isNumber)
        guard digits else { return false }
        let letters = text.filter(\.isLetter)
        if letters.isEmpty { return true }
        if text.lowercased().hasPrefix("page"), letters.count <= 4 { return true }
        if words.count == 3, words[1].lowercased() == "of",
           words[0].allSatisfy(\.isNumber), words[2].allSatisfy(\.isNumber) {
            return true
        }
        return false
    }

    private static func isMarginDate(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count < 3 else { return false }
        return text.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
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

    static func sync<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: key) != nil { return body() }
        return queue.sync(execute: body)
    }

    static func runAsync<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            queue.async {
                cont.resume(returning: body())
            }
        }
    }
}
