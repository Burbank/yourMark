import Foundation

/// EPUB 3 written in Swift. No Pandoc and no extra package — the App Store
/// copy cannot download a converter after install.
///
/// Chapters are every ATX heading in the file on disk (`#` through `######`),
/// not the reader preview. The reader stops at 180 headings and about 40,000
/// lines. Spine files are one per heading at the shallowest level in that file.
/// Deeper headings stay in that chapter and in the contents, with fragment ids.
enum EpubExport {
    struct Job: Sendable {
        var title: String
        var path: String
        var align: String = "left"
        var sourcePath: String = ""
    }

    struct Batch: Sendable {
        var written: [String]
        var failed: [String]
    }

    static func exportAll(_ jobs: [Job]) -> Batch {
        var written: [String] = []
        var failed: [String] = []
        for job in jobs {
            let url = URL(fileURLWithPath: job.path)
            do {
                let out = try write(markdownURL: url, title: job.title, align: job.align, sourcePath: job.sourcePath)
                written.append(out.lastPathComponent)
            } catch {
                let why = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failed.append("\(job.title): \(why)")
            }
        }
        return Batch(written: written, failed: failed)
    }

    /// Writes `Name.epub` beside the Markdown. Does not replace the Markdown or a PDF.
    @discardableResult
    static func write(markdownURL: URL, title: String, align: String = "left", sourcePath: String = "") throws -> URL {
        let md = markdownURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: md.path) else {
            throw ExportError.missingFile
        }
        guard let text = try? String(contentsOf: md, encoding: .utf8) else {
            throw ExportError.notUTF8
        }
        let stem = md.deletingPathExtension().lastPathComponent
        let safeStem = stem.isEmpty ? "Chapter" : stem
        let folder = md.deletingLastPathComponent()
        let dest = folder.appendingPathComponent(safeStem + ".epub")
        guard dest.path != md.path else {
            throw ExportError.cannotWrite("Refused to replace the Markdown.")
        }
        let data = try package(
            markdown: text,
            baseURL: folder,
            title: title.isEmpty ? safeStem : title,
            align: align,
            sourcePDF: sourcePath.isEmpty ? nil : URL(fileURLWithPath: sourcePath)
        )
        let partial = folder.appendingPathComponent(".\(safeStem).epub.partial")
        do {
            try data.write(to: partial, options: .atomic)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: partial, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw ExportError.cannotWrite(error.localizedDescription)
        }
        return dest
    }

    static func package(markdown: String, baseURL: URL, title: String, align: String = "left", sourcePDF: URL? = nil) throws -> Data {
        let lines = PdfCleanup.dropRepeatedPageMarks(PdfCleanup.joinLineEndHyphens(markdown)).text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let bookTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title
        var headings = scanHeadings(lines)
        let chapters = makeChapters(lines: lines, headings: &headings, bookTitle: bookTitle)
        var images = ImageStore()
        let pages = pageFiles(lines: lines, chapters: chapters)
        var docs: [(file: String, title: String, xhtml: String)] = []
        for chapter in chapters {
            let body = render(
                lines: lines,
                range: chapter.range,
                headings: headings,
                file: chapter.file,
                pages: pages,
                base: baseURL,
                images: &images
            )
            docs.append((
                chapter.file,
                chapter.title,
                chapterDocument(title: chapter.title, body: body)
            ))
        }
        let cover = sourcePDF.flatMap { PdfFigures.coverJPEG(at: $0) }
        let navNodes = navTree(headings: headings, chapters: chapters)
        let nav = navDocument(title: bookTitle, nodes: navNodes)
        var entries: [ZipEntry] = [
            ZipEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
            ZipEntry(name: "META-INF/container.xml", data: Data(containerXML.utf8)),
            ZipEntry(name: "OEBPS/style.css", data: Data(styleCSS(align: align).utf8)),
            ZipEntry(name: "OEBPS/nav.xhtml", data: Data(nav.utf8)),
        ]
        for doc in docs {
            entries.append(ZipEntry(name: "OEBPS/" + doc.file, data: Data(doc.xhtml.utf8)))
        }
        for image in images.ordered {
            entries.append(ZipEntry(name: "OEBPS/" + image.href, data: image.data))
        }
        if let cover {
            entries.append(ZipEntry(name: "OEBPS/images/cover.jpg", data: cover))
            entries.append(ZipEntry(name: "OEBPS/cover.xhtml", data: Data(coverDocument(title: bookTitle).utf8)))
        }
        let opf = packageDocument(
            title: bookTitle,
            chapters: chapters,
            images: images.ordered,
            hasCover: cover != nil
        )
        entries.insert(ZipEntry(name: "OEBPS/content.opf", data: Data(opf.utf8)), at: 3)
        return try Zip.write(entries)
    }

    private struct Heading {
        var line: Int
        var level: Int
        var title: String
        var anchor: String
        var file: String
    }

    private struct Chapter {
        var title: String
        var file: String
        var manifestID: String
        var range: Range<Int>
        var anchor: String?
    }

    private struct NavNode {
        var title: String
        var href: String
        var children: [NavNode]
    }

    private struct StoredImage {
        var href: String
        var data: Data
        var mediaType: String
        var manifestID: String
    }

    private struct ImageStore {
        var ordered: [StoredImage] = []
        var hrefByPath: [String: String] = [:]
        var usedNames: Set<String> = []

        mutating func include(url: URL) -> String? {
            let key = url.standardizedFileURL.resolvingSymlinksInPath().path
            if let href = hrefByPath[key] { return href }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
            let ext = url.pathExtension.lowercased()
            let safeExt = ext.unicodeScalars.allSatisfy { $0.value < 128 } && ext.allSatisfy({ $0.isLetter || $0.isNumber }) && !ext.isEmpty
                ? ext
                : "bin"
            var base = url.deletingPathExtension().lastPathComponent
            let ascii = !base.isEmpty && base.unicodeScalars.allSatisfy { scalar in
                let v = scalar.value
                return v > 32 && v < 127 && scalar != "/" && scalar != "\\" && scalar != ":"
            }
            if !ascii { base = String(format: "figure-%03d", ordered.count + 1) }
            var name = "\(base).\(safeExt)"
            var n = 2
            while usedNames.contains(name.lowercased()) {
                name = "\(base)-\(n).\(safeExt)"
                n += 1
            }
            usedNames.insert(name.lowercased())
            let href = "images/" + name
            hrefByPath[key] = href
            ordered.append(StoredImage(
                href: href,
                data: data,
                mediaType: mediaType(for: safeExt),
                manifestID: "img-\(ordered.count + 1)"
            ))
            return href
        }
    }

    private static func scanHeadings(_ lines: [String]) -> [Heading] {
        var found: [Heading] = []
        var used: Set<String> = []
        var inFence = false
        var fence: Character = "`"
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let mark: Character = trimmed.hasPrefix("~") ? "~" : "`"
                if !inFence {
                    inFence = true
                    fence = mark
                } else if mark == fence {
                    inFence = false
                }
                continue
            }
            if inFence { continue }
            guard let parsed = atx(line) else { continue }
            found.append(Heading(
                line: index,
                level: parsed.level,
                title: parsed.title,
                anchor: slug(parsed.title, used: &used),
                file: ""
            ))
        }
        return found
    }

    /// `# Title` through `######`, including `#Title` with no space — same as the bookmark rail.
    private static func atx(_ line: String) -> (level: Int, title: String)? {
        var t = line.trimmingCharacters(in: .whitespaces)
        let marker = "<!--ym-tr-->"
        if t.hasPrefix(marker) {
            t = String(t.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        guard t.hasPrefix("#") else { return nil }
        var level = 0
        for ch in t {
            if ch == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        var title = String(t.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        if let closing = title.range(of: #"\s+#+\s*$"#, options: .regularExpression) {
            title.removeSubrange(closing)
            title = title.trimmingCharacters(in: .whitespaces)
        }
        let text = title
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func makeChapters(lines: [String], headings: inout [Heading], bookTitle: String) -> [Chapter] {
        guard !headings.isEmpty else {
            return [Chapter(
                title: bookTitle,
                file: "text/c001.xhtml",
                manifestID: "c1",
                range: 0..<lines.count,
                anchor: nil
            )]
        }
        let spineLevel = headings.map(\.level).min() ?? 1
        let spine = headings.indices.filter { headings[$0].level == spineLevel }
        var chapters: [Chapter] = []
        var next = 1

        func add(_ title: String, range: Range<Int>, anchor: String?) {
            let file = String(format: "text/c%03d.xhtml", next)
            let chapter = Chapter(
                title: title,
                file: file,
                manifestID: "c\(next)",
                range: range,
                anchor: anchor
            )
            chapters.append(chapter)
            for i in headings.indices where chapter.range.contains(headings[i].line) {
                headings[i].file = file
            }
            next += 1
        }

        var cursor = 0
        for (ordinal, headingIndex) in spine.enumerated() {
            let line = headings[headingIndex].line
            if line > cursor, !isBlank(lines, cursor..<line) {
                add(bookTitle, range: cursor..<line, anchor: nil)
            }
            let end = ordinal + 1 < spine.count ? headings[spine[ordinal + 1]].line : lines.count
            add(headings[headingIndex].title, range: line..<end, anchor: headings[headingIndex].anchor)
            cursor = end
        }
        if chapters.isEmpty {
            add(bookTitle, range: 0..<lines.count, anchor: nil)
        }
        return chapters
    }

    private static func isBlank(_ lines: [String], _ range: Range<Int>) -> Bool {
        for i in range {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix("<!--"), t.hasSuffix("-->") { continue }
            return false
        }
        return true
    }

    private static func navTree(headings: [Heading], chapters: [Chapter]) -> [NavNode] {
        struct Frame {
            var level: Int
            var node: NavNode
        }
        var roots: [NavNode] = []
        var stack: [Frame] = []
        for heading in headings where !heading.file.isEmpty {
            let node = NavNode(
                title: heading.title,
                href: "\(heading.file)#\(heading.anchor)",
                children: []
            )
            while let top = stack.last, top.level >= heading.level {
                let done = stack.removeLast().node
                if stack.isEmpty {
                    roots.append(done)
                } else {
                    stack[stack.count - 1].node.children.append(done)
                }
            }
            stack.append(Frame(level: heading.level, node: node))
        }
        while let done = stack.popLast()?.node {
            if stack.isEmpty {
                roots.append(done)
            } else {
                stack[stack.count - 1].node.children.append(done)
            }
        }
        if let front = chapters.first, front.anchor == nil,
           !headings.contains(where: { front.range.contains($0.line) }) {
            roots.insert(NavNode(title: front.title, href: front.file, children: []), at: 0)
        }
        return roots
    }

    /// Printed page `N` lives in this spine file. The contents line links there.
    private static func pageFiles(lines: [String], chapters: [Chapter]) -> [Int: String] {
        var map: [Int: String] = [:]
        for chapter in chapters {
            let name = (chapter.file as NSString).lastPathComponent
            for i in chapter.range {
                guard let page = pageCommentNumber(lines[i]), map[page] == nil else { continue }
                map[page] = name
            }
        }
        return map
    }

    private static func pageCommentNumber(_ line: String) -> Int? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("<!-- page "), t.hasSuffix("-->") else { return nil }
        let inner = t.dropFirst(10).dropLast(3).trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty, inner.allSatisfy(\.isNumber) else { return nil }
        return Int(inner)
    }

    /// `Chapter 1: Title ........ 13` is a contents row, not a sentence.
    private static func contentsEntry(_ line: String) -> (title: String, page: Int)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: #"^(.*?)\.{2,}\s*(\d{1,4})\s*$"#) else { return nil }
        let ns = t as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: t, range: full), match.numberOfRanges == 3 else { return nil }
        let title = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        guard title.count > 1, let page = Int(ns.substring(with: match.range(at: 2))) else { return nil }
        return (title, page)
    }

    private static func render(
        lines: [String],
        range: Range<Int>,
        headings: [Heading],
        file: String,
        pages: [Int: String],
        base: URL,
        images: inout ImageStore
    ) -> String {
        let byLine = Dictionary(uniqueKeysWithValues: headings.map { ($0.line, $0) })
        var html = ""
        var para: [String] = []
        var listStack: [(indent: Int, ordered: Bool)] = []
        var inFence = false
        var fence: Character = "`"
        var code: [String] = []
        var index = range.lowerBound

        func flushPara() {
            let text = para.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            para.removeAll(keepingCapacity: true)
            let body = inline(text, base: base, images: &images)
            if !body.isEmpty { html += "<p>\(body)</p>\n" }
        }

        func closeLists() {
            while !listStack.isEmpty {
                html += "</li>"
                html += listStack.removeLast().ordered ? "</ol>\n" : "</ul>\n"
            }
        }

        func flushCode() {
            html += "<pre><code>" + xmlEscape(code.joined(separator: "\n")) + "</code></pre>\n"
            code.removeAll(keepingCapacity: true)
        }

        while index < range.upperBound {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inFence {
                let mark: Character = trimmed.hasPrefix("~") ? "~" : "`"
                if (trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")), mark == fence {
                    inFence = false
                    flushCode()
                } else {
                    code.append(line)
                }
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushPara()
                closeLists()
                inFence = true
                fence = trimmed.hasPrefix("~") ? "~" : "`"
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushPara()
                closeLists()
                index += 1
                continue
            }

            if trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") {
                if let page = pageCommentNumber(trimmed) {
                    html += "<a id=\"page-\(page)\"></a>\n"
                }
                index += 1
                continue
            }

            if let entry = contentsEntry(trimmed) {
                flushPara()
                closeLists()
                let label = xmlEscape(entry.title) + " · " + String(entry.page)
                if let target = pages[entry.page] {
                    let here = (file as NSString).lastPathComponent
                    let href = target == here ? "#page-\(entry.page)" : "\(target)#page-\(entry.page)"
                    html += "<p class=\"tocline\"><a href=\"\(xmlEscape(href))\">\(label)</a></p>\n"
                } else {
                    html += "<p class=\"tocline\">\(label)</p>\n"
                }
                index += 1
                continue
            }

            if let heading = byLine[index] {
                flushPara()
                closeLists()
                let tag = "h\(heading.level)"
                html += "<\(tag) id=\"\(heading.anchor)\">\(xmlEscape(heading.title))</\(tag)>\n"
                index += 1
                continue
            }

            if isRule(trimmed) {
                flushPara()
                closeLists()
                html += "<hr/>\n"
                index += 1
                continue
            }

            if index + 1 < range.upperBound,
               PdfCleanup.isTableRowLine(line),
               PdfCleanup.isTableSeparatorLine(lines[index + 1]) {
                flushPara()
                closeLists()
                let header = PdfCleanup.tableCells(line)
                index += 2
                var rows: [[String]] = []
                while index < range.upperBound,
                      PdfCleanup.isTableRowLine(lines[index]),
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(PdfCleanup.tableCells(lines[index]))
                    index += 1
                }
                html += tableHTML(header: header, rows: rows, base: base, images: &images)
                continue
            }

            if let item = listItem(line) {
                flushPara()
                while let top = listStack.last, item.indent < top.indent {
                    html += "</li>"
                    html += listStack.removeLast().ordered ? "</ol>\n" : "</ul>\n"
                }
                if let top = listStack.last, item.indent == top.indent, top.ordered != item.ordered {
                    html += "</li>"
                    html += listStack.removeLast().ordered ? "</ol>\n" : "</ul>\n"
                }
                if listStack.isEmpty || item.indent > listStack[listStack.count - 1].indent {
                    html += item.ordered ? "<ol>\n" : "<ul>\n"
                    listStack.append((item.indent, item.ordered))
                } else {
                    html += "</li>\n"
                }
                html += "<li>" + inline(item.text, base: base, images: &images)
                index += 1
                continue
            }

            if !listStack.isEmpty {
                closeLists()
            }
            para.append(trimmed)
            index += 1
        }
        if inFence { flushCode() }
        flushPara()
        closeLists()
        return html
    }

    private struct ListHit {
        var indent: Int
        var ordered: Bool
        var text: String
    }

    private static func listItem(_ line: String) -> ListHit? {
        let raw = line.replacingOccurrences(of: "\t", with: "    ")
        var indent = 0
        for ch in raw {
            if ch == " " { indent += 1 } else { break }
        }
        let rest = raw.dropFirst(indent)
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
            return ListHit(indent: indent, ordered: false, text: String(rest.dropFirst(2)))
        }
        var digits = 0
        for ch in rest {
            if ch.isNumber { digits += 1 } else { break }
        }
        guard digits > 0, digits < 8 else { return nil }
        let after = rest.dropFirst(digits)
        guard after.hasPrefix(". ") else { return nil }
        return ListHit(indent: indent, ordered: true, text: String(after.dropFirst(2)))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let chars = Set(trimmed)
        return chars == ["-"] || chars == ["*"] || chars == ["_"]
    }

    private static func tableHTML(
        header: [String],
        rows: [[String]],
        base: URL,
        images: inout ImageStore
    ) -> String {
        let grid = PdfCleanup.compactTable(header: header, rows: rows)
        var html = "<table>\n<thead><tr>"
        for cell in grid.header {
            html += "<th>" + inline(cell, base: base, images: &images) + "</th>"
        }
        html += "</tr></thead>\n<tbody>\n"
        for row in grid.rows {
            html += "<tr>"
            for cell in row {
                html += "<td>" + inline(cell, base: base, images: &images) + "</td>"
            }
            html += "</tr>\n"
        }
        html += "</tbody></table>\n"
        return html
    }

    private static func inline(_ raw: String, base: URL, images: inout ImageStore) -> String {
        let source = stripComments(raw)
        var out = ""
        var i = source.startIndex
        while i < source.endIndex {
            let ch = source[i]
            if ch == "`" {
                let start = source.index(after: i)
                if start < source.endIndex, let end = source[start...].firstIndex(of: "`") {
                    out += "<code>" + xmlEscape(String(source[start..<end])) + "</code>"
                    i = source.index(after: end)
                    continue
                }
            }
            if ch == "!", let next = source.index(i, offsetBy: 1, limitedBy: source.endIndex), next < source.endIndex, source[next] == "[" {
                if let link = bracketLink(source, open: next) {
                    out += imageTag(alt: link.text, dest: link.dest, base: base, images: &images)
                    i = link.end
                    continue
                }
            }
            if ch == "[" {
                if let link = bracketLink(source, open: i) {
                    out += anchorTag(text: link.text, dest: link.dest)
                    i = link.end
                    continue
                }
            }
            if ch == "*", let next = source.index(i, offsetBy: 1, limitedBy: source.endIndex), next < source.endIndex, source[next] == "*" {
                if let end = closePair(source, from: source.index(after: next), mark: "**"), boundary(source, at: i) {
                    let inner = inline(String(source[source.index(after: next)..<end]), base: base, images: &images)
                    out += "<strong>" + inner + "</strong>"
                    i = source.index(end, offsetBy: 2)
                    continue
                }
            }
            if ch == "_" , source.index(i, offsetBy: 1, limitedBy: source.endIndex).map({ $0 < source.endIndex && source[$0] == "_" }) == true {
                let next = source.index(after: i)
                if let end = closePair(source, from: source.index(after: next), mark: "__"), boundary(source, at: i) {
                    let inner = inline(String(source[source.index(after: next)..<end]), base: base, images: &images)
                    out += "<strong>" + inner + "</strong>"
                    i = source.index(end, offsetBy: 2)
                    continue
                }
            }
            if (ch == "*" || ch == "_"), boundary(source, at: i) {
                let mark = String(ch)
                if let end = closePair(source, from: source.index(after: i), mark: mark) {
                    let after = source.index(after: end)
                    let stop = after < source.endIndex && source[after] == ch
                    if !stop {
                        let inner = inline(String(source[source.index(after: i)..<end]), base: base, images: &images)
                        out += "<em>" + inner + "</em>"
                        i = source.index(after: end)
                        continue
                    }
                }
            }
            out.append(xmlEscape(String(ch)))
            i = source.index(after: i)
        }
        return out
    }

    private struct Bracket {
        var text: String
        var dest: String
        var end: String.Index
    }

    private static func bracketLink(_ source: String, open: String.Index) -> Bracket? {
        guard open < source.endIndex, source[open] == "[" else { return nil }
        var i = source.index(after: open)
        while i < source.endIndex, source[i] != "]" {
            i = source.index(after: i)
        }
        guard i < source.endIndex else { return nil }
        let text = String(source[source.index(after: open)..<i])
        let close = i
        guard let paren = source.index(close, offsetBy: 1, limitedBy: source.endIndex),
              paren < source.endIndex, source[paren] == "(" else { return nil }
        var j = source.index(after: paren)
        while j < source.endIndex, source[j] != ")" {
            j = source.index(after: j)
        }
        guard j < source.endIndex else { return nil }
        let dest = String(source[source.index(after: paren)..<j])
        return Bracket(text: text, dest: dest, end: source.index(after: j))
    }

    private static func closePair(_ source: String, from: String.Index, mark: String) -> String.Index? {
        var i = from
        let n = mark.count
        while i < source.endIndex {
            if source[i...].hasPrefix(mark) {
                return i
            }
            i = source.index(after: i)
            if n == 0 { break }
        }
        return nil
    }

    private static func boundary(_ source: String, at index: String.Index) -> Bool {
        guard index > source.startIndex else { return true }
        let prev = source[source.index(before: index)]
        return !prev.isLetter && !prev.isNumber
    }

    private static func imageTag(alt: String, dest: String, base: URL, images: inout ImageStore) -> String {
        let path = destinationPath(dest)
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return "<img src=\"\(xmlEscape(path))\" alt=\"\(xmlEscape(alt))\"/>"
        }
        if path.hasPrefix("data:") { return "" }
        guard let file = localFile(path, base: base), let href = images.include(url: file) else {
            return ""
        }
        return "<img src=\"../\(xmlEscape(href))\" alt=\"\(xmlEscape(alt))\"/>"
    }

    private static func anchorTag(text: String, dest: String) -> String {
        let path = destinationPath(dest)
        let label = xmlEscape(text)
        guard path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("mailto:") else {
            return label
        }
        return "<a href=\"\(xmlEscape(path))\">\(label)</a>"
    }

    private static func destinationPath(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("<"), let end = s.firstIndex(of: ">") {
            s = String(s[s.index(after: s.startIndex)..<end])
        }
        if let quote = s.range(of: " \"") ?? s.range(of: " '") {
            s = String(s[..<quote.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func localFile(_ path: String, base: URL) -> URL? {
        if path.isEmpty || path.hasPrefix("/") || path.hasPrefix("data:") { return nil }
        let decoded = path.removingPercentEncoding ?? path
        if decoded.contains("..") { return nil }
        let file = base.appendingPathComponent(decoded).standardizedFileURL.resolvingSymlinksInPath()
        let root = base.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path
        let filePath = file.path
        guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }
        return file
    }

    private static func stripComments(_ raw: String) -> String {
        guard raw.contains("<!--") else { return raw }
        var out = ""
        var rest = Substring(raw)
        while let open = rest.range(of: "<!--") {
            out += rest[..<open.lowerBound]
            if let close = rest[open.upperBound...].range(of: "-->") {
                rest = rest[close.upperBound...]
            } else {
                rest = ""
            }
        }
        out += rest
        return out
    }

    private static func slug(_ title: String, used: inout Set<String>) -> String {
        var s = ""
        var dash = false
        for ch in title.lowercased() {
            if ch.isLetter || ch.isNumber {
                s.append(ch)
                dash = false
            } else if !dash, !s.isEmpty {
                s.append("-")
                dash = true
            }
        }
        while s.hasSuffix("-") { s.removeLast() }
        if s.isEmpty || s.hasPrefix("xml") || s.first?.isNumber == true {
            s = "h-" + (s.isEmpty ? "section" : s)
        }
        var candidate = s
        var n = 2
        while used.contains(candidate) {
            candidate = "\(s)-\(n)"
            n += 1
        }
        used.insert(candidate)
        return candidate
    }

    private static func mediaType(for ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "tif", "tiff": return "image/tiff"
        default: return "application/octet-stream"
        }
    }

    private static func chapterDocument(title: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
        <head>
        <title>\(xmlEscape(title))</title>
        <link rel="stylesheet" type="text/css" href="../style.css"/>
        </head>
        <body>
        \(body)</body>
        </html>
        """
    }

    private static func navDocument(title: String, nodes: [NavNode]) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en">
        <head>
        <title>\(xmlEscape(title))</title>
        </head>
        <body>
        <nav epub:type="toc" id="toc">
        <h1>\(xmlEscape(title))</h1>
        \(renderNav(nodes))
        </nav>
        </body>
        </html>
        """
    }

    private static func renderNav(_ nodes: [NavNode]) -> String {
        guard !nodes.isEmpty else { return "<ol></ol>" }
        var html = "<ol>"
        for node in nodes {
            html += "<li><a href=\"\(xmlEscape(node.href))\">\(xmlEscape(node.title))</a>"
            if !node.children.isEmpty {
                html += renderNav(node.children)
            }
            html += "</li>"
        }
        html += "</ol>"
        return html
    }

    private static func coverDocument(title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
        <head>
        <title>\(xmlEscape(title))</title>
        <link rel="stylesheet" type="text/css" href="style.css"/>
        </head>
        <body class="coverpage">
        <img src="images/cover.jpg" alt="\(xmlEscape(title))"/>
        </body>
        </html>
        """
    }

    private static func packageDocument(title: String, chapters: [Chapter], images: [StoredImage], hasCover: Bool) -> String {
        let stamp = isoStamp(Date())
        let uid = "urn:uuid:\(UUID().uuidString.lowercased())"
        var manifest = """
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="css" href="style.css" media-type="text/css"/>
        """
        var spine = ""
        if hasCover {
            manifest += "\n<item id=\"cover\" href=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>"
            manifest += "\n<item id=\"cover-img\" href=\"images/cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>"
            spine += "<itemref idref=\"cover\"/>"
        }
        for chapter in chapters {
            manifest += "\n<item id=\"\(chapter.manifestID)\" href=\"\(chapter.file)\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"\(chapter.manifestID)\"/>"
        }
        for image in images {
            manifest += "\n<item id=\"\(image.manifestID)\" href=\"\(image.href)\" media-type=\"\(image.mediaType)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="uid">\(xmlEscape(uid))</dc:identifier>
        <dc:title>\(xmlEscape(title))</dc:title>
        <dc:language>und</dc:language>
        <meta property="dcterms:modified">\(stamp)</meta>
        \(hasCover ? "<meta name=\"cover\" content=\"cover-img\"/>" : "")
        </metadata>
        <manifest>
        \(manifest)
        </manifest>
        <spine>
        \(spine)
        </spine>
        </package>
        """
    }

    private static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
    </container>
    """

    /// Left keeps the ragged right edge of the Markdown. Justified is the other choice.
    private static func styleCSS(align: String) -> String {
        let mode = align == "justify" ? "justify" : "left"
        let hyphens = align == "justify" ? "auto" : "manual"
        return """
        body { font-family: serif; line-height: 1.45; margin: 1em; }
        body.coverpage { margin: 0; padding: 0; text-align: center !important; }
        body.coverpage img { width: 100%; height: auto; }
        body, p, li, blockquote { text-align: \(mode) !important; hyphens: \(hyphens); -webkit-hyphens: \(hyphens); }
        img { max-width: 100%; height: auto; }
        table { border-collapse: collapse; margin: 1em 0; width: auto; max-width: 100%; table-layout: auto; }
        th { font-weight: bold; }
        td, th { border: 1px solid #888; padding: 0.3em 0.5em; vertical-align: top; text-align: left !important; overflow-wrap: break-word; }
        pre { white-space: pre-wrap; font-family: monospace; text-align: left !important; }
        code { font-family: monospace; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.2; text-align: left !important; }
        p.tocline { margin: 0.35em 0; text-align: left !important; hyphens: manual; -webkit-hyphens: manual; }
        p.tocline a { color: inherit; text-decoration: underline; }
        """
    }

    private static func isoStamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date).replacingOccurrences(of: "+00:00", with: "Z")
    }

    private static func xmlEscape(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        for ch in raw {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }

    private struct ZipEntry {
        var name: String
        var data: Data
    }

    private enum Zip {
        static func write(_ entries: [ZipEntry]) throws -> Data {
            guard entries.count < 65_535 else {
                throw ExportError.cannotWrite("Too many files for one EPUB.")
            }
            var out = Data()
            var central = Data()
            let (dtime, ddate) = dosStamp(Date())
            for entry in entries {
                guard out.count < Int(UInt32.max) - entry.data.count - 64 else {
                    throw ExportError.cannotWrite("That EPUB would be larger than 4 GB.")
                }
                let name = Data(entry.name.utf8)
                let crc = CRC32.hash(entry.data)
                let size = UInt32(entry.data.count)
                let offset = UInt32(out.count)
                appendU32(0x04034b50, to: &out)
                appendU16(20, to: &out)
                appendU16(0, to: &out)
                appendU16(0, to: &out)
                appendU16(dtime, to: &out)
                appendU16(ddate, to: &out)
                appendU32(crc, to: &out)
                appendU32(size, to: &out)
                appendU32(size, to: &out)
                appendU16(UInt16(name.count), to: &out)
                appendU16(0, to: &out)
                out.append(name)
                out.append(entry.data)

                appendU32(0x02014b50, to: &central)
                appendU16(20, to: &central)
                appendU16(20, to: &central)
                appendU16(0, to: &central)
                appendU16(0, to: &central)
                appendU16(dtime, to: &central)
                appendU16(ddate, to: &central)
                appendU32(crc, to: &central)
                appendU32(size, to: &central)
                appendU32(size, to: &central)
                appendU16(UInt16(name.count), to: &central)
                appendU16(0, to: &central)
                appendU16(0, to: &central)
                appendU16(0, to: &central)
                appendU16(0, to: &central)
                appendU32(0, to: &central)
                appendU32(offset, to: &central)
                central.append(name)
            }
            let cdOffset = UInt32(out.count)
            out.append(central)
            appendU32(0x06054b50, to: &out)
            appendU16(0, to: &out)
            appendU16(0, to: &out)
            appendU16(UInt16(entries.count), to: &out)
            appendU16(UInt16(entries.count), to: &out)
            appendU32(UInt32(central.count), to: &out)
            appendU32(cdOffset, to: &out)
            appendU16(0, to: &out)
            return out
        }

        private static func dosStamp(_ date: Date) -> (UInt16, UInt16) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let year = UInt16(max(0, min(127, (parts.year ?? 1980) - 1980)))
            let time = (UInt16(parts.hour ?? 0) << 11)
                | (UInt16(parts.minute ?? 0) << 5)
                | UInt16((parts.second ?? 0) / 2)
            let day = (year << 9) | (UInt16(parts.month ?? 1) << 5) | UInt16(parts.day ?? 1)
            return (time, day)
        }
    }

    private enum CRC32 {
        static let table: [UInt32] = (0..<256).map { index in
            var c = UInt32(index)
            for _ in 0..<8 {
                c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }

        static func hash(_ data: Data) -> UInt32 {
            var crc: UInt32 = 0xFFFF_FFFF
            for byte in data {
                let index = Int((crc ^ UInt32(byte)) & 0xFF)
                crc = table[index] ^ (crc >> 8)
            }
            return crc ^ 0xFFFF_FFFF
        }
    }

    private static func appendU16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendU32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private enum ExportError: LocalizedError {
        case missingFile
        case notUTF8
        case cannotWrite(String)

        var errorDescription: String? {
            switch self {
            case .missingFile:
                return "That Markdown file is not on disk anymore."
            case .notUTF8:
                return "The Markdown is not UTF-8."
            case .cannotWrite(let why):
                return why
            }
        }
    }
}
