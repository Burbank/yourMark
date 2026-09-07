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
        case .convert: return "Drop FCOM / QRH / AIP PDFs — Microsoft MarkItDown writes Markdown"
        case .library: return "Converted manuals on this Mac"
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
