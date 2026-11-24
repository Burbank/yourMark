import Foundation
import PDFKit
import CryptoKit

/// `clamp(120 + 3·pages + 20·ocrPages, 120, 3600)`
public func calculateTimeout(pages: Int, ocrPages: Int) -> Int {
    let base = 120 + (3 * pages) + (20 * ocrPages)
    return min(max(base, 120), 3600)
}

/// Map CLI / options language codes onto Vision `recognitionLanguages`.
public func visionRecognitionLanguages(for code: String) -> [String] {
    switch code.lowercased() {
    case "nld", "nl":
        return ["nl-NL", "nl-BE"]
    case "spa", "es":
        return ["es-ES", "es-MX"]
    case "hun", "hu":
        return ["hu-HU"]
    case "eng", "en":
        return ["en-US", "en-GB"]
    case "auto":
        return ["en-US", "nl-NL", "es-ES", "hu-HU", "de-DE", "fr-FR"]
    default:
        return ["en-US"]
    }
}

/// Tesseract `-l` argument for OCRmyPDF (`eng+script` style where needed).
public func tesseractLanguageCode(for code: String) -> String {
    switch code.lowercased() {
    case "nld", "nl": return "nld"
    case "spa", "es": return "spa"
    case "hun", "hu": return "hun"
    case "eng", "en": return "eng"
    case "auto": return "eng"
    default: return "eng"
    }
}

public func stripQuery(_ urlString: String) -> String {
    guard let url = URL(string: urlString) else { return urlString }
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.query = nil
    components?.fragment = nil
    return components?.url?.absoluteString ?? urlString
}

public func formatBytes(_ bytes: Int64) -> String {
    let kb = Double(bytes) / 1024.0
    let mb = kb / 1024.0
    if mb >= 1.0 {
        return String(format: "%.1f MB", mb)
    }
    if kb >= 1.0 {
        return String(format: "%.1f KB", kb)
    }
    return "\(bytes) bytes"
}

public enum ConversionSupport {
    /// MarkItDown helper script for the GUI (.app bundle) or SPM `yourmark` binary.
    public static func markitdownConvertScriptURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "markitdown_convert", withExtension: "py") {
            return bundled
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        var dir = executable.deletingLastPathComponent()
        let fm = FileManager.default
        for _ in 0..<10 {
            let candidate = dir.appendingPathComponent("Resources/markitdown_convert.py")
            if fm.isReadableFile(atPath: candidate.path) {
                return candidate
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }
}

public struct ProbeInfo: Sendable {
    public var pages: Int
    public var hasTextLayer: Bool
    public var scannedPages: Int
    public var encrypted: Bool
    public var sha256: String
    public var bytes: Int64

    public init(
        pages: Int,
        hasTextLayer: Bool,
        scannedPages: Int,
        encrypted: Bool,
        sha256: String,
        bytes: Int64
    ) {
        self.pages = pages
        self.hasTextLayer = hasTextLayer
        self.scannedPages = scannedPages
        self.encrypted = encrypted
        self.sha256 = sha256
        self.bytes = bytes
    }
}

public func probeFile(_ url: URL) async throws -> ProbeInfo {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0

    let data = try Data(contentsOf: url)
    let sha256 = SHA256.hash(data: data)
    let sha256String = sha256.map { String(format: "%02x", $0) }.joined()

    if url.pathExtension.lowercased() == "pdf" {
        return await PdfWork.runAsync {
            let profile = OcrService.profile(url)
            let pageCount = OcrService.pageCount(of: url)

            var encrypted = false
            if let doc = PDFDocument(url: url) {
                encrypted = doc.isEncrypted
            } else {
                encrypted = true
            }

            return ProbeInfo(
                pages: pageCount,
                hasTextLayer: !profile.needsOCR,
                scannedPages: profile.needsOCR ? pageCount : 0,
                encrypted: encrypted,
                sha256: sha256String,
                bytes: bytes
            )
        }
    }

    return ProbeInfo(
        pages: 1,
        hasTextLayer: true,
        scannedPages: 0,
        encrypted: false,
        sha256: sha256String,
        bytes: bytes
    )
}

/// Vision OCR confidence samples recorded during the latest conversion (pipeline reads mean).
public enum OCRVisionMetrics {
    private static let lock = NSLock()
    private static var samples: [Double] = []

    public static func reset() {
        lock.lock()
        samples = []
        languages = []
        lock.unlock()
    }

    private static var languages: [String] = []

    public static func recordLanguages(_ value: [String]) {
        lock.lock()
        languages = value
        lock.unlock()
    }

    public static var lastLanguages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return languages
    }

    public static func record(confidence: Double) {
        lock.lock()
        samples.append(confidence)
        lock.unlock()
    }

    public static var meanConfidence: Double? {
        lock.lock()
        defer { lock.unlock() }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }
}