import AppKit
import Foundation
import PDFKit
import Vision

/// Pre-step before Microsoft MarkItDown.
/// MarkItDown (pdfminer) only reads a text layer. Scans have none, so tables,
/// arrows, and pictures vanish. This:
///   1. Detects a scan (almost no text on the first pages).
///   2. Prefers OCRmyPDF (Tesseract) → searchable PDF, original pixels kept.
///   3. Falls back to Apple Live Text (Vision) — already on the Mac.
///   4. Writes page pictures next to the Markdown so diagrams still show.
enum OcrService {
    static let figureFolderSuffix = "-figures"

    static func needsOCR(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "pdf" else { return false }
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return false }
        let sample = min(doc.pageCount, 6)
        var chars = 0
        for i in 0..<sample {
            chars += (doc.page(at: i)?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .count
        }
        return chars < sample * 48
    }

    static func ocrmypdfPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/ocrmypdf",
            "/usr/local/bin/ocrmypdf",
            "\(home)/.local/bin/ocrmypdf",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Returns a PDF MarkItDown can read. Original file is never overwritten.
    static func searchablePDF(
        from url: URL,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws -> (url: URL, didOCR: Bool) {
        guard needsOCR(url) else { return (url, false) }
        if let exe = ocrmypdfPath() {
            onStatus("OCR with OCRmyPDF (Tesseract)…")
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("yourMark-ocr-\(UUID().uuidString).pdf")
            let args = [
                "--skip-text",
                "--optimize", "0",
                "--output-type", "pdf",
                "-l", "eng",
                url.path,
                out.path,
            ]
            do {
                _ = try await run(exe, args)
                if FileManager.default.fileExists(atPath: out.path) {
                    return (out, true)
                }
            } catch {
                onStatus("OCRmyPDF failed — using Apple Live Text…")
            }
        } else {
            onStatus("OCR with Apple Live Text…")
        }
        return (url, true)
    }

    /// After MarkItDown: if this was a scan, add page pictures + Live Text
    /// so arrows, diagrams, and tables still appear as images, with words under them.
    static func enrichMarkdown(
        markdownURL: URL,
        sourcePDF: URL,
        onStatus: @escaping @Sendable (String) -> Void
    ) async {
        guard needsOCR(sourcePDF) || markdownLooksEmpty(markdownURL) else { return }
        guard let doc = PDFDocument(url: sourcePDF), doc.pageCount > 0 else { return }
        onStatus("Keeping page pictures so diagrams stay visible…")

        let stem = markdownURL.deletingPathExtension().lastPathComponent
        let figDir = markdownURL.deletingLastPathComponent()
            .appendingPathComponent(stem + figureFolderSuffix, isDirectory: true)
        try? FileManager.default.createDirectory(at: figDir, withIntermediateDirectories: true)

        let existing = (try? String(contentsOf: markdownURL, encoding: .utf8)) ?? ""
        let empty = markdownLooksEmpty(markdownURL)
        let alreadyHasPictures = existing.contains(figureFolderSuffix) || existing.contains("data:image/")

        try? FileManager.default.createDirectory(at: figDir, withIntermediateDirectories: true)

        if !empty, alreadyHasPictures { return }

        var parts: [String] = []
        if !empty {
            parts.append(existing.trimmingCharacters(in: .whitespacesAndNewlines))
            parts.append("")
            parts.append("> Page pictures from the scan — tables, arrows, and diagrams as they appear.")
            parts.append("")
            let count = doc.pageCount
            for i in 0..<count {
                onStatus("Saving page picture \(i + 1) of \(count)…")
                guard let page = doc.page(at: i),
                      let file = savePageImage(page, index: i, into: figDir) else { continue }
                parts.append("### Page \(i + 1)")
                parts.append("")
                parts.append("![Page \(i + 1)](\(stem + figureFolderSuffix)/\(file))")
                parts.append("")
            }
            try? parts.joined(separator: "\n").write(to: markdownURL, atomically: true, encoding: .utf8)
            return
        }

        parts = [
            "> This PDF was a scan (no text layer). yourMark ran OCR, then Microsoft MarkItDown.",
            "> Page pictures are kept so tables, arrows, and diagrams still show.",
            "",
        ]

        let count = doc.pageCount
        for i in 0..<count {
            onStatus("OCR page \(i + 1) of \(count)…")
            guard let page = doc.page(at: i) else { continue }
            let heading = pageHeading(page, index: i)
            parts.append("## \(heading)")
            parts.append("")
            if let file = savePageImage(page, index: i, into: figDir) {
                parts.append("![\(heading)](\(stem + figureFolderSuffix)/\(file))")
                parts.append("")
            }
            let text = await liveText(page)
            if !text.isEmpty {
                parts.append(text)
                parts.append("")
            }
        }

        try? parts.joined(separator: "\n").write(to: markdownURL, atomically: true, encoding: .utf8)
    }

    static func markdownLooksEmpty(_ url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return true }
        let body = text
            .replacingOccurrences(of: #"[>#*\-\[\]\(\)`]"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.count < 80
    }

    private static func pageHeading(_ page: PDFPage, index: Int) -> String {
        let raw = (page.string ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count > 3 && $0.count < 80 }
        return raw.map(String.init) ?? "Page \(index + 1)"
    }

    private static func savePageImage(_ page: PDFPage, index: Int, into dir: URL) -> String? {
        let box = page.bounds(for: .mediaBox)
        let long = max(box.width, box.height)
        let scale = min(2.0, 1800 / max(long, 1))
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.62])
        else { return nil }
        let name = String(format: "page-%03d.jpg", index + 1)
        try? jpeg.write(to: dir.appendingPathComponent(name))
        return name
    }

    private static func liveText(_ page: PDFPage) async -> String {
        let img = page.thumbnail(of: CGSize(width: 2000, height: 2000), for: .mediaBox)
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US"]
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                let text: String
                do {
                    try handler.perform([request])
                    text = (request.results as? [VNRecognizedTextObservation] ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                } catch {
                    text = page.string ?? ""
                }
                cont.resume(returning: text)
            }
        }
    }

    static func installViaHomebrew() async throws -> String {
        let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let brew else {
            throw NSError(
                domain: "OcrService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Homebrew is not installed. Apple Live Text still OCRs scans on this Mac. To install OCRmyPDF: https://brew.sh then brew install ocrmypdf"]
            )
        }
        return try await run(brew, ["install", "ocrmypdf"])
    }

    @discardableResult
    private static func run(_ exe: String, _ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                let out = Pipe()
                let err = Pipe()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                p.standardOutput = out
                p.standardError = err
                var env = ProcessInfo.processInfo.environment
                let extra = ["/opt/homebrew/bin", "/usr/local/bin",
                             FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin"]
                env["PATH"] = extra.joined(separator: ":") + ":" + (env["PATH"] ?? "")
                p.environment = env
                do {
                    try p.run()
                    p.waitUntilExit()
                    let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                        ?? ""
                    if p.terminationStatus == 0 {
                        cont.resume(returning: msg)
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "OcrService",
                            code: Int(p.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "OCRmyPDF failed" : msg]
                        ))
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
