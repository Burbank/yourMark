import Foundation

enum LinkPane: String, Equatable, Hashable {
    case main, translate, harvest
}

enum AppTool: String, CaseIterable, Identifiable {
    case library = "Library"
    case convert = "Convert"

    var id: String { rawValue }
}

struct ConvertJob: Identifiable, Hashable {
    let id: UUID
    var sourceURL: URL
    var outputURL: URL?
    var status: Status
    var detail: String
    var needsOCR: Bool = false
    var touchedAt: Date = Date()
    var phase: String = ""
    var startedAt: Date?
    var progress: Double?
    var page: Int = 0
    var pageCount: Int = 0
    var fileIndex: Int = 0
    var fileCount: Int = 0
    var etaSeconds: Int?
    var firstTickAt: Date?
    var firstTickPage: Int = 0

    enum Status: String {
        case queued, running, done, failed
    }
}

struct ForageMarkSpan: Hashable, Codable {
    var sourcePath: String
    var location: Int
    var length: Int
}

struct LibraryItem: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var sourceName: String
    var markdownPath: String
    var addedAt: Date
    var openedAt: Date
    var byteCount: Int64
    var bookmarks: [ManualBookmark] = []
    var sourcePath: String = ""
    var forageMarks: [ForageMarkSpan] = []
    var tags: [String] = []

    enum CodingKeys: String, CodingKey {
        case id, title, sourceName, markdownPath, addedAt, openedAt, byteCount, bookmarks, sourcePath, forageMarks, tags
    }

    init(
        id: UUID,
        title: String,
        sourceName: String,
        markdownPath: String,
        addedAt: Date,
        byteCount: Int64,
        bookmarks: [ManualBookmark] = [],
        sourcePath: String = "",
        openedAt: Date? = nil,
        forageMarks: [ForageMarkSpan] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.sourceName = sourceName
        self.markdownPath = markdownPath
        self.addedAt = addedAt
        self.openedAt = openedAt ?? addedAt
        self.byteCount = byteCount
        self.bookmarks = bookmarks
        self.sourcePath = sourcePath
        self.forageMarks = forageMarks
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourceName = try c.decode(String.self, forKey: .sourceName)
        markdownPath = try c.decode(String.self, forKey: .markdownPath)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        openedAt = try c.decodeIfPresent(Date.self, forKey: .openedAt) ?? addedAt
        byteCount = try c.decode(Int64.self, forKey: .byteCount)
        bookmarks = try c.decodeIfPresent([ManualBookmark].self, forKey: .bookmarks) ?? []
        sourcePath = try c.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        forageMarks = try c.decodeIfPresent([ForageMarkSpan].self, forKey: .forageMarks) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(sourceName, forKey: .sourceName)
        try c.encode(markdownPath, forKey: .markdownPath)
        try c.encode(addedAt, forKey: .addedAt)
        try c.encode(openedAt, forKey: .openedAt)
        try c.encode(byteCount, forKey: .byteCount)
        try c.encode(bookmarks, forKey: .bookmarks)
        try c.encode(sourcePath, forKey: .sourcePath)
        try c.encode(forageMarks, forKey: .forageMarks)
        try c.encode(tags, forKey: .tags)
    }
}

enum LibrarySortKind: String, CaseIterable {
    case manual, nameAsc, nameDesc, dateNew, dateOld, tagAsc, tagDesc
}

struct AskRecord: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var question: String
    var answer: String
    var openAnswer: String
    var chapter: String
    var fileTitle: String
    var askedAt: Date
    var sourceLine: Int?

    init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        openAnswer: String = "",
        chapter: String,
        fileTitle: String,
        askedAt: Date = Date(),
        sourceLine: Int? = nil
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.openAnswer = openAnswer
        self.chapter = chapter
        self.fileTitle = fileTitle
        self.askedAt = askedAt
        self.sourceLine = sourceLine
    }
}

struct LibraryGroup: Identifiable {
    var id: String
    var master: LibraryItem
    var children: [LibraryItem]
    var items: [LibraryItem] { [master] + children }
}

enum YourMarkError: Error, LocalizedError {
    case engineNotFound
    case invalidInput(String)
    case processFailed(String)
    case outputMissing(String)

    var errorDescription: String? {
        switch self {
        case .engineNotFound:
            return Distribution.isAppStore
                ? "This App Store build converts with Apple PDFKit and Live Text."
                : "Microsoft MarkItDown is not installed yet. yourMark installs it from PyPI on first launch — use Install converter if it did not finish."
        case .invalidInput(let message):
            return message
        case .processFailed(let message):
            return message
        case .outputMissing(let path):
            return "No output at \(path)"
        }
    }
}

struct PreviewLine: Identifiable, Sendable, Hashable {
    let id: Int
    var text: String
}

struct PreviewPack: Sendable {
    var text: String
    var lines: [PreviewLine]
    var headings: [ManualBookmark]
    var base: URL
    var missing: Bool = false
    var truncated: Bool = false
}

/// Library file search: words, quoted phrases, AND / OR / NOT, and parentheses.
struct FileSearchQuery: Sendable {
    indirect enum Node: Sendable {
        case term(String)
        case and([Node])
        case or([Node])
        case not(Node)
    }

    private enum Token {
        case word(String)
        case and, or, not
        case lparen, rparen
    }

    let root: Node
    let highlightTerms: [String]
    let isSimpleTerm: Bool

    static func parse(_ raw: String) -> FileSearchQuery? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let tokens = tokenize(trimmed)
        var i = 0
        let node: Node
        if tokens.isEmpty {
            node = .term(trimmed)
        } else if let parsed = parseOr(tokens, &i), i >= tokens.count {
            node = parsed
        } else {
            node = .term(trimmed)
        }
        var terms: [String] = []
        collectHighlights(node, underNot: false, into: &terms)
        let simple: Bool
        if case .term = node { simple = true } else { simple = false }
        return FileSearchQuery(root: node, highlightTerms: terms, isSimpleTerm: simple)
    }

    func matches(_ text: String) -> Bool {
        if isSimpleTerm { return eval(root, in: text) }
        for paragraph in Self.paragraphs(in: text) {
            if eval(root, in: paragraph) { return true }
            if Self.sentences(in: paragraph).contains(where: { eval(root, in: $0) }) { return true }
        }
        return false
    }

    /// Lines that sit in a sentence or paragraph where AND / OR / NOT all hold.
    func hitLineIDs(in rows: [PreviewLine], span: ClosedRange<Int>? = nil) -> [Int] {
        var hits: [Int] = []
        var para: [PreviewLine] = []
        func flush() {
            guard !para.isEmpty else { return }
            let text = para.map(\.text).joined(separator: " ")
            let ok = eval(root, in: text)
                || Self.sentences(in: text).contains { eval(root, in: $0) }
            if ok {
                var added = false
                for row in para {
                    if highlightTerms.contains(where: { Self.contains(row.text, $0) }) {
                        hits.append(row.id)
                        added = true
                    }
                }
                if !added {
                    hits.append(contentsOf: para.map(\.id))
                }
            }
            para = []
        }
        for row in rows {
            if let span, !span.contains(row.id) {
                flush()
                continue
            }
            let t = row.text.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("<!--") {
                flush()
                continue
            }
            para.append(row)
            if hits.count >= 120 { break }
        }
        flush()
        if hits.count > 120 { return Array(hits.prefix(120)) }
        return hits
    }

    static func paragraphs(in text: String) -> [String] {
        var paras: [String] = []
        var buf: [String] = []
        func flush() {
            let t = buf.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { paras.append(t) }
            buf = []
        }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("<!--") {
                flush()
                continue
            }
            buf.append(t)
        }
        flush()
        return paras
    }

    static func sentences(in paragraph: String) -> [String] {
        var out: [String] = []
        var start = paragraph.startIndex
        var i = paragraph.startIndex
        while i < paragraph.endIndex {
            let ch = paragraph[i]
            if ch == "." || ch == "!" || ch == "?" {
                let next = paragraph.index(after: i)
                if next == paragraph.endIndex || paragraph[next].isWhitespace {
                    let s = String(paragraph[start..<next]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if s.count >= 3 { out.append(s) }
                    start = next
                }
            }
            i = paragraph.index(after: i)
        }
        let tail = String(paragraph[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.count >= 3 { out.append(tail) }
        return out
    }

    /// AND, OR, and NOT count only in capitals — same as Search in files.
    static func hasBooleanOperators(_ raw: String) -> Bool {
        tokenize(raw).contains {
            switch $0 {
            case .and, .or, .not: return true
            default: return false
            }
        }
    }

    static func contains(_ hay: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        return hay.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func eval(_ node: Node, in text: String) -> Bool {
        switch node {
        case .term(let needle):
            return Self.contains(text, needle)
        case .and(let nodes):
            return nodes.allSatisfy { eval($0, in: text) }
        case .or(let nodes):
            return nodes.contains { eval($0, in: text) }
        case .not(let inner):
            return !eval(inner, in: text)
        }
    }

    private static func collectHighlights(_ node: Node, underNot: Bool, into terms: inout [String]) {
        switch node {
        case .term(let s):
            if !underNot, !s.isEmpty { terms.append(s) }
        case .and(let nodes), .or(let nodes):
            for child in nodes {
                collectHighlights(child, underNot: underNot, into: &terms)
            }
        case .not(let inner):
            collectHighlights(inner, underNot: true, into: &terms)
        }
    }

    private static func tokenize(_ s: String) -> [Token] {
        var i = s.startIndex
        var out: [Token] = []
        while i < s.endIndex {
            if s[i].isWhitespace {
                i = s.index(after: i)
                continue
            }
            if s[i] == "(" {
                out.append(.lparen)
                i = s.index(after: i)
                continue
            }
            if s[i] == ")" {
                out.append(.rparen)
                i = s.index(after: i)
                continue
            }
            if s[i] == "\"" {
                i = s.index(after: i)
                let start = i
                while i < s.endIndex, s[i] != "\"" {
                    i = s.index(after: i)
                }
                let phrase = String(s[start..<i])
                if i < s.endIndex { i = s.index(after: i) }
                if !phrase.isEmpty { out.append(.word(phrase)) }
                continue
            }
            if s[i] == "-",
               let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex),
               next < s.endIndex,
               !s[next].isWhitespace,
               s[next] != "(" , s[next] != ")" {
                out.append(.not)
                i = next
                continue
            }
            let start = i
            while i < s.endIndex, !s[i].isWhitespace, s[i] != "(", s[i] != ")" {
                i = s.index(after: i)
            }
            let word = String(s[start..<i])
            switch word {
            case "AND": out.append(.and)
            case "OR": out.append(.or)
            case "NOT": out.append(.not)
            default: out.append(.word(word))
            }
        }
        return out
    }

    private static func parseOr(_ tokens: [Token], _ i: inout Int) -> Node? {
        guard let first = parseAnd(tokens, &i) else { return nil }
        var parts = [first]
        while i < tokens.count {
            guard case .or = tokens[i] else { break }
            i += 1
            guard let next = parseAnd(tokens, &i) else { break }
            parts.append(next)
        }
        return parts.count == 1 ? parts[0] : .or(parts)
    }

    private static func parseAnd(_ tokens: [Token], _ i: inout Int) -> Node? {
        guard let first = parseNot(tokens, &i) else { return nil }
        var parts = [first]
        while i < tokens.count {
            switch tokens[i] {
            case .or, .rparen:
                return parts.count == 1 ? parts[0] : .and(parts)
            case .and:
                i += 1
                guard let next = parseNot(tokens, &i) else {
                    return parts.count == 1 ? parts[0] : .and(parts)
                }
                parts.append(next)
            default:
                guard let next = parseNot(tokens, &i) else {
                    return parts.count == 1 ? parts[0] : .and(parts)
                }
                parts.append(next)
            }
        }
        return parts.count == 1 ? parts[0] : .and(parts)
    }

    private static func parseNot(_ tokens: [Token], _ i: inout Int) -> Node? {
        guard i < tokens.count else { return nil }
        if case .not = tokens[i] {
            i += 1
            guard let inner = parseNot(tokens, &i) else { return nil }
            return .not(inner)
        }
        return parsePrimary(tokens, &i)
    }

    private static func parsePrimary(_ tokens: [Token], _ i: inout Int) -> Node? {
        guard i < tokens.count else { return nil }
        switch tokens[i] {
        case .word(let word):
            i += 1
            return .term(word)
        case .lparen:
            i += 1
            guard let inner = parseOr(tokens, &i) else { return nil }
            if i < tokens.count, case .rparen = tokens[i] { i += 1 }
            return inner
        default:
            return nil
        }
    }
}
