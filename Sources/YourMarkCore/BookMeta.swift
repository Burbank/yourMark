import Foundation
import PDFKit

/// A book's catalog record. The Markdown copy is a Pandoc YAML block at the
/// top of the file. The EPUB copy is Dublin Core in the package document.
///
/// A later source fills only an empty field: a YAML edit, then the PDF, then
/// the copyright page, then a repeating page header, then Open Library. A title is always written. When those
/// sources leave it empty, the opening of the book is read for it, and the
/// file name is used if that reading does not yield one. The PDF's Creator and
/// Producer are the tool that wrote the file, never the author or the publisher.
struct BookRecord: Equatable, Sendable {
    var title = ""
    var authors: [String] = []
    var publisher = ""
    var date = ""
    var rights = ""
    var summary = ""
    var subjects: [String] = []
    var lang = ""
    var isbn = ""
    var sourceName = ""
    var created = ""
    var pdfCreator = ""
    var pdfProducer = ""

    var isEmpty: Bool {
        title.isEmpty && authors.isEmpty && publisher.isEmpty && date.isEmpty
            && rights.isEmpty && summary.isEmpty && subjects.isEmpty && lang.isEmpty
            && isbn.isEmpty && sourceName.isEmpty && created.isEmpty
            && pdfCreator.isEmpty && pdfProducer.isEmpty
    }

    /// Copy each field that this record does not already have.
    mutating func fillEmpty(from other: BookRecord) {
        if title.isEmpty { title = other.title }
        if authors.isEmpty { authors = other.authors }
        if publisher.isEmpty { publisher = other.publisher }
        if date.isEmpty { date = other.date }
        if rights.isEmpty { rights = other.rights }
        if summary.isEmpty { summary = other.summary }
        if subjects.isEmpty { subjects = other.subjects }
        if lang.isEmpty { lang = other.lang }
        if isbn.isEmpty { isbn = other.isbn }
        if sourceName.isEmpty { sourceName = other.sourceName }
        if created.isEmpty { created = other.created }
        if pdfCreator.isEmpty { pdfCreator = other.pdfCreator }
        if pdfProducer.isEmpty { pdfProducer = other.pdfProducer }
    }
}

enum BookMeta {
    private static let fenceLimit = 40

    /// The YAML block, including the blank line under it, or nil when nothing is known.
    static func yamlPrefix(_ record: BookRecord) -> String? {
        guard !record.isEmpty else { return nil }
        var lines = ["---"]
        func add(_ key: String, _ value: String) {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            lines.append("\(key): \(yamlQuote(text))")
        }
        add("title", record.title)
        if !record.authors.isEmpty {
            lines.append("author:")
            for name in record.authors where !name.isEmpty {
                lines.append("  - \(yamlQuote(name))")
            }
        }
        add("publisher", record.publisher)
        add("date", record.date)
        add("rights", record.rights)
        add("description", record.summary)
        if !record.subjects.isEmpty {
            lines.append("subject:")
            for item in record.subjects where !item.isEmpty {
                lines.append("  - \(yamlQuote(item))")
            }
        }
        add("lang", record.lang)
        if let isbn = validISBN(record.isbn) {
            let scheme = isbn.count == 10 ? "ISBN-10" : "ISBN-13"
            lines.append("identifier:")
            lines.append("  - scheme: \(scheme)")
            lines.append("    text: \(yamlQuote(isbn))")
        }
        add("source", record.sourceName)
        add("created", record.created)
        add("pdf-creator", record.pdfCreator)
        add("pdf-producer", record.pdfProducer)
        guard lines.count > 1 else { return nil }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n\n"
    }

    /// A block that starts the file and closes within 40 lines. Anything else stays in the text.
    static func peel(_ markdown: String) -> (raw: String?, body: String, record: BookRecord?) {
        let lines = splitLines(markdown)
        guard let end = closingFence(lines) else { return (nil, markdown, nil) }
        var prefixCount = end + 1
        if prefixCount < lines.count, lines[prefixCount].trimmingCharacters(in: .whitespaces).isEmpty {
            prefixCount += 1
        }
        let raw = lines.prefix(prefixCount).joined(separator: "\n") + "\n"
        let body = lines.dropFirst(prefixCount).joined(separator: "\n")
        let record = parse(Array(lines[1..<end]))
        return (raw, body, record)
    }

    /// Line indexes of a well-formed block, including its closing fence.
    static func span(_ lines: [String]) -> ClosedRange<Int>? {
        guard let end = closingFence(lines) else { return nil }
        return 0...end
    }

    static func newlineCount(_ text: String) -> Int {
        text.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
    }

    /// Put a title on a block that does not have one, leaving every other line as it was.
    static func prefixByAddingTitle(_ title: String, to raw: String) -> String {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return raw }
        var lines = splitLines(raw)
        let line = "title: \(yamlQuote(text))"
        if let index = lines.indices.first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("title:")
        }) {
            lines[index] = line
        } else if !lines.isEmpty {
            lines.insert(line, at: 1)
        } else {
            return raw
        }
        return lines.joined(separator: "\n")
    }

    /// Put an author on a block that does not have one, leaving every other line as it was.
    static func prefixByAddingAuthor(_ name: String, to raw: String) -> String {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return raw }
        var lines = splitLines(raw)
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("author:") }) {
            return raw
        }
        let block = ["author:", "  - \(yamlQuote(text))"]
        if let titleIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("title:")
        }) {
            lines.insert(contentsOf: block, at: titleIndex + 1)
        } else if !lines.isEmpty {
            lines.insert(contentsOf: block, at: 1)
        } else {
            return raw
        }
        return lines.joined(separator: "\n")
    }

    /// Opening pages, for a title reading. Capped so the rest of the book is not sent.
    static func titleSample(_ markdown: String) -> String {
        var text = openingLines(markdown).joined(separator: "\n")
        if text.count < 400 {
            let extra = String(markdown.prefix(4_000))
            if extra.count > text.count { text = extra }
        }
        if text.count > 6_000 { text = String(text.prefix(6_000)) }
        return text
    }

    /// A one-line title whose distinctive words actually appear in the opening.
    static func acceptedDocumentTitle(_ raw: String, in opening: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cut = text.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            text = String(text[..<cut]).trimmingCharacters(in: .whitespaces)
        }
        if text.count >= 2, let quote = text.first, (quote == "\"" || quote == "'"), text.last == quote {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.lowercased().hasPrefix("title:") {
            text = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "#*` "))
        let lower = text.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        let banned = ["unknown", "untitled", "n/a", "none", "title", "not found"]
        if text.count < 2 || text.count > 140 || banned.contains(lower) { return nil }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard (1...16).contains(words.count) else { return nil }
        if text.hasSuffix("."), words.count > 6 { return nil }
        let significant = words
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { $0.count >= 4 }
        if significant.isEmpty {
            guard opening.range(of: text, options: .caseInsensitive) != nil else { return nil }
            return text
        }
        let hits = significant.filter { opening.range(of: $0, options: .caseInsensitive) != nil }
        guard hits.count * 2 >= significant.count else { return nil }
        return text
    }

    /// A readable stand-in from a file name, when the book itself did not yield a title.
    static func titleFromFileName(_ name: String) -> String {
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let tokens = base.split { $0 == "_" || $0 == "-" || $0.isWhitespace }.map(String.init)
        var kept: [String] = []
        for (index, token) in tokens.enumerated() {
            let trailing = index >= tokens.count - 3
            let isYear = token.count == 4 && token.allSatisfy(\.isNumber)
                && (token.hasPrefix("19") || token.hasPrefix("20"))
            let isVersion = token.lowercased().range(of: #"^v\d+$"#, options: .regularExpression) != nil
            if trailing && (isYear || isVersion) { continue }
            kept.append(token)
        }
        let text = kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count >= 2 ? text : "Untitled"
    }

    // MARK: - Sources

    /// Information dictionary, then XMP for fields that dictionary left empty.
    static func fromPDF(_ url: URL) -> BookRecord {
        PdfWork.sync {
            guard url.pathExtension.lowercased() == "pdf" else { return BookRecord() }
            var record = BookRecord()
            record.sourceName = url.lastPathComponent
            if let doc = PDFDocument(url: url) {
                let attrs = doc.documentAttributes ?? [:]
                record.title = clean(attrs[PDFDocumentAttribute.titleAttribute] as? String)
                record.authors = splitNames(attrs[PDFDocumentAttribute.authorAttribute] as? String)
                record.summary = clean(attrs[PDFDocumentAttribute.subjectAttribute] as? String)
                record.subjects = keywords(attrs[PDFDocumentAttribute.keywordsAttribute])
                record.pdfCreator = clean(attrs[PDFDocumentAttribute.creatorAttribute] as? String)
                record.pdfProducer = clean(attrs[PDFDocumentAttribute.producerAttribute] as? String)
                if let date = attrs[PDFDocumentAttribute.creationDateAttribute] as? Date {
                    record.created = isoDay(date)
                }
            }
            if let packet = xmpPacket(at: url) {
                record.fillEmpty(from: fromXMP(packet))
            }
            record.isbn = validISBN(record.isbn) ?? ""
            record.date = publicationDate(record.date) ?? ""
            record.lang = languageTag(record.lang) ?? ""
            return record
        }
    }

    /// Short copyright-page lines in the first two pages of the conversion.
    static func fromCopyright(_ markdown: String) -> BookRecord {
        var record = BookRecord()
        let lines = openingLines(markdown)
        var index = 0
        while index < lines.count {
            let text = plain(lines[index])
            index += 1
            guard !text.isEmpty, text.count <= 140, text.split(whereSeparator: \.isWhitespace).count <= 18 else { continue }
            if record.rights.isEmpty || record.authors.isEmpty || record.date.isEmpty {
                if let hit = copyrightLine(text) {
                    if record.rights.isEmpty { record.rights = hit.rights }
                    if record.authors.isEmpty, let name = hit.author { record.authors = [name] }
                    if record.date.isEmpty, let year = hit.year { record.date = year }
                }
            }
            if record.publisher.isEmpty, let name = publishedBy(text) {
                record.publisher = imprint(after: name, lines: lines, index: index, author: record.authors.first)
            }
            if record.isbn.isEmpty, let code = isbnLine(text), let valid = validISBN(code) {
                record.isbn = valid
            }
        }
        return record
    }

    /// "Published by" the author, then the house name on the next line, keeps the house.
    private static func imprint(after name: String, lines: [String], index: Int, author: String?) -> String {
        guard let author, sameName(name, author), index < lines.count else { return name }
        let next = plain(lines[index])
        guard next.count >= 2, next.count <= 80 else { return name }
        let words = next.split(whereSeparator: \.isWhitespace)
        guard (1...6).contains(words.count) else { return name }
        let lower = next.lowercased()
        if lower.hasPrefix("copyright") || lower.hasPrefix("isbn") || lower.hasPrefix("published") { return name }
        if next.contains(". ") { return name }
        return next
    }

    private static func sameName(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Fill still-empty title, author, publisher, date, and subject from Open Library.
    static func catalogFill(_ record: BookRecord) -> BookRecord {
        let missing = record.title.isEmpty || record.authors.isEmpty || record.publisher.isEmpty
            || record.date.isEmpty || record.subjects.isEmpty
        guard missing else { return record }
        var next = record
        if let isbn = validISBN(record.isbn), let hit = fetchISBN(isbn) {
            next.fillEmpty(from: hit)
        }
        let still = next.title.isEmpty || next.authors.isEmpty || next.publisher.isEmpty
            || next.date.isEmpty || next.subjects.isEmpty
        if still, !next.title.isEmpty, let hit = fetchTitle(next.title) {
            next.fillEmpty(from: hit)
        }
        next.date = publicationDate(next.date) ?? ""
        next.isbn = validISBN(next.isbn) ?? (validISBN(record.isbn) ?? "")
        return next
    }

    /// Build a fresh record: PDF, then the copyright page, then a repeating header, then the catalog.
    static func gather(pdf: URL?, markdown: String, header: BookRecord = BookRecord()) -> BookRecord {
        var record = pdf.map { fromPDF($0) } ?? BookRecord()
        record.fillEmpty(from: fromCopyright(markdown))
        record.fillEmpty(from: header)
        return catalogFill(record)
    }

    /// YAML wins. The PDF fills whatever the block left empty. The catalog is not called.
    static func mergeForEPUB(markdown: String, pdf: URL?) -> BookRecord {
        let peeled = peel(markdown)
        var record = peeled.record ?? BookRecord()
        if let pdf {
            record.fillEmpty(from: fromPDF(pdf))
        }
        record.date = publicationDate(record.date) ?? ""
        record.lang = languageTag(record.lang) ?? ""
        record.isbn = validISBN(record.isbn) ?? ""
        return record
    }

    static func opfMetadata(_ record: BookRecord, uid: String, modified: String, hasCover: Bool) -> String {
        var lines: [String] = []
        lines.append("<dc:identifier id=\"uid\">\(xml(uid))</dc:identifier>")
        if let isbn = validISBN(record.isbn) {
            lines.append("<dc:identifier id=\"isbn\">urn:isbn:\(xml(isbn))</dc:identifier>")
        }
        let title = record.title.isEmpty ? "Untitled" : record.title
        lines.append("<dc:title>\(xml(title))</dc:title>")
        lines.append("<dc:language>\(xml(languageTag(record.lang) ?? "und"))</dc:language>")
        for (index, name) in record.authors.enumerated() where !name.isEmpty {
            lines.append("<dc:creator id=\"creator-\(index)\">\(xml(name))</dc:creator>")
        }
        if !record.publisher.isEmpty {
            lines.append("<dc:publisher>\(xml(record.publisher))</dc:publisher>")
        }
        if let date = publicationDate(record.date) {
            lines.append("<dc:date>\(xml(date))</dc:date>")
        }
        if !record.rights.isEmpty {
            lines.append("<dc:rights>\(xml(record.rights))</dc:rights>")
        }
        if !record.summary.isEmpty {
            lines.append("<dc:description>\(xml(record.summary))</dc:description>")
        }
        for subject in record.subjects where !subject.isEmpty {
            lines.append("<dc:subject>\(xml(subject))</dc:subject>")
        }
        lines.append("<meta property=\"dcterms:modified\">\(xml(modified))</meta>")
        for index in record.authors.indices where !record.authors[index].isEmpty {
            lines.append("<meta refines=\"#creator-\(index)\" property=\"role\" scheme=\"marc:relators\">aut</meta>")
        }
        if hasCover {
            lines.append("<meta name=\"cover\" content=\"cover-img\"/>")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Checks

    static func validISBN(_ raw: String) -> String? {
        var chars: [Character] = []
        for ch in raw.uppercased() {
            if ch.isNumber { chars.append(ch) }
            else if ch == "X" { chars.append(ch) }
        }
        let text = String(chars)
        if text.count == 13, text.allSatisfy(\.isNumber), isbn13(text) { return text }
        if text.count == 10, isbn10(text) { return text }
        return nil
    }

    /// A publication year, or a calendar day. A PDF file date is not accepted here.
    static func publicationDate(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.range(of: #"^\d{4}$"#, options: .regularExpression) != nil { return text }
        if text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
           calendarDay(text) { return text }
        if let range = text.range(of: #"\b(?:1[5-9]\d{2}|20\d{2})\b"#, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }

    /// A BCP 47 tag such as `en` or `en-US`. `und` and a guessed language stay out.
    static func languageTag(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text != "und", !text.isEmpty else { return nil }
        guard text.range(of: #"^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$"#, options: .regularExpression) != nil else {
            return nil
        }
        return text
    }

    // MARK: - Private

    private static func splitLines(_ markdown: String) -> [String] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func closingFence(_ lines: [String]) -> Int? {
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        let last = min(lines.count, fenceLimit + 1)
        for index in 1..<last {
            if lines[index].trimmingCharacters(in: .whitespaces) == "---" { return index }
        }
        return nil
    }

    private static func parse(_ lines: [String]) -> BookRecord {
        var record = BookRecord()
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("- ") {
                index += 1
                continue
            }
            guard let colon = trimmed.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let rest = unquote(String(trimmed[trimmed.index(after: colon)...]))
            if rest.isEmpty {
                index += 1
                if key == "identifier" {
                    index = parseIdentifier(lines, from: index, into: &record)
                } else {
                    let items = parseList(lines, from: &index)
                    switch key {
                    case "author":
                        if record.authors.isEmpty { record.authors = items }
                    case "subject":
                        if record.subjects.isEmpty { record.subjects = items }
                    default:
                        break
                    }
                }
                continue
            }
            assign(key, rest, to: &record)
            index += 1
        }
        record.date = publicationDate(record.date) ?? ""
        record.lang = languageTag(record.lang) ?? ""
        record.isbn = validISBN(record.isbn) ?? ""
        return record
    }

    private static func assign(_ key: String, _ value: String, to record: inout BookRecord) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch key {
        case "title": if record.title.isEmpty { record.title = text }
        case "author": if record.authors.isEmpty { record.authors = [text] }
        case "publisher": if record.publisher.isEmpty { record.publisher = text }
        case "date": if record.date.isEmpty { record.date = text }
        case "rights": if record.rights.isEmpty { record.rights = text }
        case "description": if record.summary.isEmpty { record.summary = text }
        case "subject": if record.subjects.isEmpty { record.subjects = [text] }
        case "lang", "language": if record.lang.isEmpty { record.lang = text }
        case "identifier": if record.isbn.isEmpty { record.isbn = text }
        case "source": if record.sourceName.isEmpty { record.sourceName = text }
        case "created": if record.created.isEmpty { record.created = text }
        case "pdf-creator": if record.pdfCreator.isEmpty { record.pdfCreator = text }
        case "pdf-producer": if record.pdfProducer.isEmpty { record.pdfProducer = text }
        default: break
        }
    }

    private static func parseList(_ lines: [String], from index: inout Int) -> [String] {
        var items: [String] = []
        while index < lines.count {
            let row = lines[index]
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            guard row.hasPrefix("  - ") || row.hasPrefix("\t- ") || trimmed.hasPrefix("- ") else { break }
            let item = unquote(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            if !item.isEmpty { items.append(item) }
            index += 1
        }
        return items
    }

    private static func parseIdentifier(_ lines: [String], from start: Int, into record: inout BookRecord) -> Int {
        var index = start
        var text = ""
        while index < lines.count {
            let row = lines[index]
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            if row.hasPrefix("    ") || row.hasPrefix("\t\t") {
                if trimmed.lowercased().hasPrefix("text:") {
                    text = unquote(String(trimmed.dropFirst(5)))
                }
                index += 1
                continue
            }
            if trimmed.hasPrefix("- ") {
                if record.isbn.isEmpty, let isbn = validISBN(text) { record.isbn = isbn }
                text = ""
                let item = unquote(String(trimmed.dropFirst(2)))
                if item.lowercased().hasPrefix("text:") {
                    text = unquote(String(item.dropFirst(5)))
                } else if item.lowercased().hasPrefix("scheme:") {
                    text = ""
                } else if record.isbn.isEmpty, let isbn = validISBN(item) {
                    record.isbn = isbn
                }
                index += 1
                continue
            }
            break
        }
        if record.isbn.isEmpty, let isbn = validISBN(text) { record.isbn = isbn }
        return index
    }

    private static func unquote(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { return text }
        let quote = text.first
        guard (quote == "\"" || quote == "'"), text.last == quote else { return text }
        text = String(text.dropFirst().dropLast())
        text = text.replacingOccurrences(of: "\\\"", with: "\"")
        text = text.replacingOccurrences(of: "\\'", with: "'")
        text = text.replacingOccurrences(of: "\\\\", with: "\\")
        return text
    }

    private static func yamlQuote(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let escaped = flat.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func clean(_ raw: String?) -> String {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func splitNames(_ raw: String?) -> [String] {
        let text = clean(raw)
        guard !text.isEmpty else { return [] }
        return text.split(separator: ";").map { clean(String($0)) }.filter { !$0.isEmpty }
    }

    private static func keywords(_ raw: Any?) -> [String] {
        let text: String
        if let value = raw as? String {
            text = value
        } else if let values = raw as? [String] {
            text = values.joined(separator: ", ")
        } else {
            return []
        }
        return text.split { $0 == "," || $0 == ";" }
            .map { clean(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func calendarDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return false }
        return (1...12).contains(month) && (1...31).contains(day)
    }

    private static func isbn13(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard digits.count == 13 else { return false }
        var sum = 0
        for (index, digit) in digits.dropLast().enumerated() {
            sum += digit * (index % 2 == 0 ? 1 : 3)
        }
        return (10 - (sum % 10)) % 10 == digits[12]
    }

    private static func isbn10(_ text: String) -> Bool {
        guard text.count == 10 else { return false }
        var sum = 0
        for (index, ch) in text.enumerated() {
            let digit: Int
            if ch == "X", index == 9 { digit = 10 }
            else if let value = ch.wholeNumberValue { digit = value }
            else { return false }
            sum += digit * (10 - index)
        }
        return sum % 11 == 0
    }

    private static func xmpPacket(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)
        var data = Data()
        if size <= 40_000_000 {
            data = handle.readDataToEndOfFile()
        } else {
            data = handle.readData(ofLength: 2_000_000)
            if size > 2_000_000 {
                try? handle.seek(toOffset: size - 2_000_000)
                data.append(handle.readData(ofLength: 2_000_000))
            }
        }
        guard let text = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) else {
            return nil
        }
        let start = text.range(of: "<x:xmpmeta") ?? text.range(of: "<?xpacket begin")
        guard let start else { return nil }
        let tail = text[start.lowerBound...]
        if let end = tail.range(of: "</x:xmpmeta>") {
            return String(tail[..<end.upperBound])
        }
        if let end = tail.range(of: "<?xpacket end") {
            return String(tail[..<end.upperBound])
        }
        return String(tail.prefix(200_000))
    }

    private static func fromXMP(_ packet: String) -> BookRecord {
        var record = BookRecord()
        record.title = xmpText(packet, "title").first ?? ""
        record.authors = xmpText(packet, "creator")
        record.publisher = xmpText(packet, "publisher").first ?? ""
        record.rights = xmpText(packet, "rights").first ?? ""
        record.summary = xmpText(packet, "description").first ?? ""
        record.subjects = xmpText(packet, "subject")
        record.lang = xmpText(packet, "language").first ?? ""
        for value in xmpText(packet, "identifier") {
            if let isbn = validISBN(value) {
                record.isbn = isbn
                break
            }
        }
        return record
    }

    /// Text inside one Dublin Core element, including each `rdf:li`.
    private static func xmpText(_ packet: String, _ local: String) -> [String] {
        let pattern = "<(?:[A-Za-z0-9]+:)?\(local)\\b[^>]*>(.*?)</(?:[A-Za-z0-9]+:)?\(local)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = packet as NSString
        var values: [String] = []
        for match in regex.matches(in: packet, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 1 else { continue }
            let inner = ns.substring(with: match.range(at: 1))
            let items = listItems(inner)
            if items.isEmpty {
                let plain = stripTags(inner)
                if !plain.isEmpty { values.append(plain) }
            } else {
                values.append(contentsOf: items)
            }
        }
        return values
    }

    private static func listItems(_ xml: String) -> [String] {
        let pattern = "<(?:[A-Za-z0-9]+:)?li\\b[^>]*>(.*?)</(?:[A-Za-z0-9]+:)?li>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = xml as NSString
        return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let text = stripTags(ns.substring(with: match.range(at: 1)))
            return text.isEmpty ? nil : text
        }
    }

    private static func stripTags(_ xml: String) -> String {
        var text = xml.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func openingLines(_ markdown: String) -> [String] {
        let lines = splitLines(markdown)
        var sections = 0
        var kept: [String] = []
        var sawPage = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<!-- page "), trimmed.hasSuffix("-->") {
                sawPage = true
                sections += 1
                if sections > 2 { break }
                continue
            }
            if !sawPage || sections <= 2 {
                if !trimmed.isEmpty { kept.append(line) }
            }
            if !sawPage, kept.count >= 80 { break }
            if kept.count >= 160 { break }
        }
        return kept
    }

    private static func plain(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        var hashes = 0
        for ch in text {
            if ch == "#" { hashes += 1 } else { break }
        }
        if (1...6).contains(hashes) {
            let rest = text.dropFirst(hashes)
            if rest.first == " " { text = rest.trimmingCharacters(in: .whitespaces) }
        }
        if text.hasPrefix("**"), text.hasSuffix("**"), text.count > 4 {
            text = String(text.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private static func copyrightLine(_ text: String) -> (rights: String, year: String?, author: String?)? {
        let pattern = #"(?i)^copyright\b(?:\s*(?:©|\(c\)))?\s*[, ]*\s*(\d{4})?(?:\s+by\s+(.+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var year: String?
        if match.range(at: 1).location != NSNotFound {
            year = ns.substring(with: match.range(at: 1))
        }
        var author: String?
        if match.range(at: 2).location != NSNotFound {
            let name = ns.substring(with: match.range(at: 2))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            if name.count >= 2 { author = name }
        }
        var rights = "Copyright"
        if let year { rights += " © \(year)" }
        if let author { rights += " by \(author)" }
        return (rights, year, author)
    }

    private static func publishedBy(_ text: String) -> String? {
        let pattern = #"(?i)^published by\s+(.{2,80})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        let name = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return name.count >= 2 ? name : nil
    }

    private static func isbnLine(_ text: String) -> String? {
        let pattern = #"(?i)^isbn(?:-1[03])?\s*[:#]?\s*([0-9Xx][0-9Xx \-]{8,22})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func fetchISBN(_ isbn: String) -> BookRecord? {
        var parts = URLComponents(string: "https://openlibrary.org/api/books")
        parts?.queryItems = [
            URLQueryItem(name: "bibkeys", value: "ISBN:\(isbn)"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "jscmd", value: "data"),
        ]
        guard let url = parts?.url, let root = fetchJSON(url) as? [String: Any] else { return nil }
        guard let book = root.values.first as? [String: Any] else { return nil }
        return record(fromCatalog: book, yearKey: "publish_date")
    }

    private static func fetchTitle(_ title: String) -> BookRecord? {
        var parts = URLComponents(string: "https://openlibrary.org/search.json")
        parts?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = parts?.url, let root = fetchJSON(url) as? [String: Any] else { return nil }
        let docs = root["docs"] as? [[String: Any]] ?? []
        let want = normalizedTitle(title)
        guard !want.isEmpty else { return nil }
        let hits = docs.filter { normalizedTitle($0["title"] as? String ?? "") == want }
        guard hits.count == 1, let book = hits.first else { return nil }
        var record = BookRecord()
        record.title = clean(book["title"] as? String)
        record.authors = stringList(book["author_name"])
        record.publisher = stringList(book["publisher"]).first ?? ""
        if let year = book["first_publish_year"] as? Int {
            record.date = String(year)
        } else if let year = book["first_publish_year"] as? String {
            record.date = year
        }
        record.subjects = Array(stringList(book["subject"]).prefix(12))
        return record
    }

    private static func record(fromCatalog book: [String: Any], yearKey: String) -> BookRecord {
        var record = BookRecord()
        record.title = clean(book["title"] as? String)
        record.authors = nameList(book["authors"])
        record.publisher = nameList(book["publishers"]).first ?? ""
        record.date = clean(book[yearKey] as? String)
        record.subjects = Array(nameList(book["subjects"]).prefix(12))
        return record
    }

    private static func nameList(_ raw: Any?) -> [String] {
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            let name = clean(item["name"] as? String)
            return name.isEmpty ? nil : name
        }
    }

    private static func stringList(_ raw: Any?) -> [String] {
        guard let items = raw as? [String] else { return [] }
        return items.map { clean($0) }.filter { !$0.isEmpty }
    }

    private static func normalizedTitle(_ text: String) -> String {
        text.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func fetchJSON(_ url: URL) -> Any? {
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("yourMark", forHTTPHeaderField: "User-Agent")
        let gate = DispatchSemaphore(value: 0)
        var payload: Any?
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data {
                payload = try? JSONSerialization.jsonObject(with: data)
            }
            gate.signal()
        }
        task.resume()
        if gate.wait(timeout: .now() + 8) == .timedOut {
            task.cancel()
            return nil
        }
        return payload
    }

    private static func xml(_ raw: String) -> String {
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
}
