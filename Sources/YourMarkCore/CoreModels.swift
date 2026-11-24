import Foundation

/// Models shared between CLI and GUI

/// Translation marker used in Markdown (from TranslateService)
public let translationMarker = "<!--ym-tr-->"

/// OCR quality thresholds
public enum OCRQuality {
    public static let weakConfidenceThreshold = 0.6
    public static let minCharsPerOCRPage = 200
}

public struct ConvertJob: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var sourceURL: URL
    public var outputURL: URL?
    public var status: Status
    public var detail: String
    public var needsOCR: Bool = false
    public var touchedAt: Date = Date()
    public var phase: String = ""
    public var startedAt: Date?
    public var progress: Double?
    public var page: Int = 0
    public var pageCount: Int = 0
    public var fileIndex: Int = 0
    public var fileCount: Int = 0
    public var etaSeconds: Int?
    public var firstTickAt: Date?
    public var firstTickPage: Int = 0

    public enum Status: String, Sendable {
        case queued, running, done, failed
    }
    
    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        outputURL: URL?,
        status: Status,
        detail: String,
        needsOCR: Bool = false
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.status = status
        self.detail = detail
        self.needsOCR = needsOCR
    }
}

public enum YourMarkError: Error, LocalizedError {
    case engineNotFound
    case invalidInput(String)
    case processFailed(String)
    case outputMissing(String)

    public var errorDescription: String? {
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

/// Conversion options for the pipeline
public struct ConvertOptions: Sendable {
    public var ocrEnabled: Bool
    public var ocrLanguage: String
    public var extractImages: Bool
    public var stripChrome: Bool
    public var keepOriginalPDF: KeepOriginal
    public var prefersDocling: Bool
    public var askReadPictures: Bool
    public var askHasKey: Bool
    public var askBaseURL: String
    public var askModel: String
    public var timeoutSeconds: Int?
    
    public enum KeepOriginal: String, Sendable {
        case auto, always, never
    }
    
    public init(
        ocrEnabled: Bool = true,
        ocrLanguage: String = "auto",
        extractImages: Bool = false,
        stripChrome: Bool = true,
        keepOriginalPDF: KeepOriginal = .auto,
        prefersDocling: Bool = false,
        askReadPictures: Bool = false,
        askHasKey: Bool = false,
        askBaseURL: String = "",
        askModel: String = "",
        timeoutSeconds: Int? = nil
    ) {
        self.ocrEnabled = ocrEnabled
        self.ocrLanguage = ocrLanguage
        self.extractImages = extractImages
        self.stripChrome = stripChrome
        self.keepOriginalPDF = keepOriginalPDF
        self.prefersDocling = prefersDocling
        self.askReadPictures = askReadPictures
        self.askHasKey = askHasKey
        self.askBaseURL = askBaseURL
        self.askModel = askModel
        self.timeoutSeconds = timeoutSeconds
    }
}

/// Result of a conversion
public struct ConvertResult: Sendable {
    public var markdownURL: URL
    public var originalKept: Bool
    public var usedOCR: Bool
    public var ocrEngine: String?
    public var pictures: Int
    public var warnings: [String]
    public var elapsedSeconds: Double
    public var weakOCR: Bool
    
    public init(
        markdownURL: URL,
        originalKept: Bool = false,
        usedOCR: Bool = false,
        ocrEngine: String? = nil,
        pictures: Int = 0,
        warnings: [String] = [],
        elapsedSeconds: Double = 0,
        weakOCR: Bool = false
    ) {
        self.markdownURL = markdownURL
        self.originalKept = originalKept
        self.usedOCR = usedOCR
        self.ocrEngine = ocrEngine
        self.pictures = pictures
        self.warnings = warnings
        self.elapsedSeconds = elapsedSeconds
        self.weakOCR = weakOCR
    }
}
