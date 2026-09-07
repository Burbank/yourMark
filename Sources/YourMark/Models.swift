import Foundation

enum AppTool: String, CaseIterable, Identifiable {
    case convert = "Convert"
    case library = "Library"
    case engine = "Engine"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .convert: return "arrow.triangle.2.circlepath.doc.on.clipboard"
        case .library: return "books.vertical"
        case .engine: return "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .convert: return "Drop PDFs, Word, and slides — Microsoft MarkItDown writes Markdown"
        case .library: return "Converted files — Bookmarks jump like a PDF outline"
        case .engine: return "Discover, inspect, and upgrade the PyPI engine"
        }
    }
}

struct ConvertJob: Identifiable, Hashable {
    let id: UUID
    var sourceURL: URL
    var outputURL: URL?
    var status: Status
    var detail: String
    var startedAt: Date?

    enum Status: String {
        case queued, running, done, failed
    }
}

struct LibraryItem: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var sourceName: String
    var markdownPath: String
    var addedAt: Date
    var byteCount: Int64
    var bookmarks: [ManualBookmark] = []
    var sourcePath: String = ""

    enum CodingKeys: String, CodingKey {
        case id, title, sourceName, markdownPath, addedAt, byteCount, bookmarks, sourcePath
    }

    init(
        id: UUID,
        title: String,
        sourceName: String,
        markdownPath: String,
        addedAt: Date,
        byteCount: Int64,
        bookmarks: [ManualBookmark] = [],
        sourcePath: String = ""
    ) {
        self.id = id
        self.title = title
        self.sourceName = sourceName
        self.markdownPath = markdownPath
        self.addedAt = addedAt
        self.byteCount = byteCount
        self.bookmarks = bookmarks
        self.sourcePath = sourcePath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourceName = try c.decode(String.self, forKey: .sourceName)
        markdownPath = try c.decode(String.self, forKey: .markdownPath)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        byteCount = try c.decode(Int64.self, forKey: .byteCount)
        bookmarks = try c.decodeIfPresent([ManualBookmark].self, forKey: .bookmarks) ?? []
        sourcePath = try c.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
    }
}

enum YourMarkError: Error, LocalizedError {
    case engineNotFound
    case invalidInput(String)
    case processFailed(String)
    case cancelled
    case outputMissing(String)

    var errorDescription: String? {
        switch self {
        case .engineNotFound:
            return "markitdown was not found. Install with:\n\nuv tool install 'markitdown[all]'\n\nthen yourMark → Engine → Recheck."
        case .invalidInput(let message):
            return message
        case .processFailed(let message):
            return message
        case .cancelled:
            return "Cancelled"
        case .outputMissing(let path):
            return "No output at \(path)"
        }
    }
}
