import AppKit
import CoreGraphics
import Foundation
import PDFKit
import Vision

/// Scans have no text layer, so Microsoft MarkItDown (pdfminer) cannot see
/// tables, columns, or figures.
///   1. Detect a scan (almost no text on the first pages) — one PDF open.
///   2. Prefer IBM Docling: layout, TableFormer tables, pictures.
///   3. Fall back to OCRmyPDF (words only) then MarkItDown.
///   4. Last resort: Apple Live Text + page pictures (empty markdown only).
/// Digital PDFs with figures go through MarkItDown once, then PdfFigures.
enum OcrService {
    struct PdfProfile: Equatable, Sendable {
        var needsOCR: Bool
        var looksGraphic: Bool
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var profileCache: [String: (mtime: TimeInterval, value: PdfProfile)] = [:]

    static func profile(_ url: URL) -> PdfProfile {
        guard url.pathExtension.lowercased() == "pdf" else {
            return PdfProfile(needsOCR: false, looksGraphic: false)
        }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap(\.contentModificationDate)?.timeIntervalSince1970 ?? 0
        cacheLock.lock()
        let hit = profileCache[url.path]
        cacheLock.unlock()
        if let hit, hit.mtime == mtime {
            return hit.value
        }
        let value = profileUncached(url)
        cacheLock.lock()
        profileCache[url.path] = (mtime, value)
        cacheLock.unlock()
        return value
    }

    static func needsOCR(_ url: URL) -> Bool { profile(url).needsOCR }

    static func looksGraphic(_ url: URL) -> Bool { profile(url).looksGraphic }

    private static func profileUncached(_ url: URL) -> PdfProfile {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
            return PdfProfile(needsOCR: false, looksGraphic: false)
        }
        // Sample cover, a middle page, and the end — a text-rich cover
        // must not hide 20 scanned pages behind it.
        let last = doc.pageCount - 1
        var idxs = [0, min(1, last), last / 2, (last * 3) / 4, last]
        if doc.pageCount > 8 { idxs.append(2) }
        let sample = Array(Set(idxs)).sorted().filter { $0 >= 0 && $0 < doc.pageCount }

        var chars = 0
        var scanPages = 0
        for i in sample {
            guard let page = doc.page(at: i) else { continue }
            let kit = (page.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .count
            chars += kit
            // PDFKit on recent macOS can "see" words on a photograph of a page.
            // MarkItDown/pdfminer cannot — it only reads a real text layer.
            // Count Tj/TJ operators so a scan is not mistaken for a digital PDF.
            if textOperatorCount(page) < 2 {
                scanPages += 1
            }
        }
        let avg = chars / max(sample.count, 1)
        let mostlyPictures = scanPages * 2 >= sample.count
        let fewLetters = chars < sample.count * 48
        return PdfProfile(needsOCR: mostlyPictures || fewLetters, looksGraphic: mostlyPictures || avg < 320)
    }

    /// How many actual PDF text-drawing operators this page has (not Live Text).
    private static func textOperatorCount(_ page: PDFPage) -> Int {
        guard let cgPage = page.pageRef else { return 0 }
        let stream = CGPDFContentStreamCreateWithPage(cgPage)
        guard let table = CGPDFOperatorTableCreate() else {
            CGPDFContentStreamRelease(stream)
            return 0
        }
        var count = 0
        let bump: CGPDFOperatorCallback = { _, info in
            guard let info else { return }
            info.assumingMemoryBound(to: Int.self).pointee += 1
        }
        for name in ["Tj", "TJ", "'", "\""] {
            CGPDFOperatorTableSetCallback(table, name, bump)
        }
        withUnsafeMutablePointer(to: &count) { ptr in
            let scanner = CGPDFScannerCreate(stream, table, UnsafeMutableRawPointer(ptr))
            CGPDFScannerScan(scanner)
            CGPDFScannerRelease(scanner)
        }
        CGPDFOperatorTableRelease(table)
        CGPDFContentStreamRelease(stream)
        return count
    }

    /// After MarkItDown: almost no real words for the number of pages.
    static func markdownLooksThin(_ url: URL, pageCount: Int) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return true }
        var body = text
        body = body.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: " ", options: .regularExpression)
        body = body.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: " ", options: .regularExpression)
        body = body.replacingOccurrences(of: #"(?m)^#+\s*Page\s+\d+\s*$"#, with: " ", options: .regularExpression)
        let letters = body.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letters < max(60, pageCount * 25)
    }

    static func pageCount(of url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
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

    static func doclingPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/docling",
            "/opt/homebrew/bin/docling",
            "/usr/local/bin/docling",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func uvPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/uv",
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Layout-aware convert for scans. Docling (IBM, MIT) does tables, columns,
    /// reading order, and figures. MarkItDown cannot — it only reads a text layer.
    /// `ocr: false` when the PDF already has a text layer (faster, no double OCR).
    static func layoutMarkdown(
        from pdf: URL,
        to markdown: URL,
        ocr: Bool = true,
        onStatus: @escaping @Sendable (String) -> Void
    ) async -> Bool {
        onStatus("Layout OCR with Docling — tables and columns. This takes a little longer.")
        let script = writeScanScript()
        guard let pythonCmd = layoutPython() else {
            onStatus("Docling is not installed yet")
            return false
        }
        do {
            _ = try await run(
                pythonCmd.exe,
                pythonCmd.args + [script.path, pdf.path, markdown.path, ocr ? "ocr" : "text"]
            )
            return FileManager.default.fileExists(atPath: markdown.path)
                && !markdownLooksEmpty(markdown)
        } catch {
            onStatus("Docling failed — falling back. \(error.localizedDescription)")
            return false
        }
    }

    static func installDocling() async throws -> String {
        guard let uv = uvPath() else {
            throw NSError(
                domain: "OcrService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "uv is not installed. Convert a normal PDF first so yourMark can install it, then try again."]
            )
        }
        return try await run(uv, ["tool", "install", "--force", "docling"])
    }

    private static func layoutPython() -> (exe: String, args: [String])? {
        if let uv = uvPath() {
            return (uv, ["run", "--with", "docling", "python3"])
        }
        return nil
    }

    private static func writeScanScript() -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("yourMark/scan_layout.py")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? scanLayoutPy.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static let scanLayoutPy = #"""
import sys
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
want_ocr = len(sys.argv) < 4 or sys.argv[3] != "text"

from docling.document_converter import DocumentConverter, PdfFormatOption
from docling.datamodel.base_models import InputFormat
from docling.datamodel.pipeline_options import PdfPipelineOptions

opts = PdfPipelineOptions()
opts.do_ocr = want_ocr
opts.do_table_structure = True
try:
    opts.table_structure_options.do_cell_matching = True
except Exception:
    pass
opts.generate_picture_images = True
try:
    opts.images_scale = 1.4
except Exception:
    pass

if want_ocr:
    try:
        from docling.datamodel.pipeline_options import OcrMacOptions
        opts.ocr_options = OcrMacOptions()
    except Exception:
        pass

conv = DocumentConverter(
    format_options={InputFormat.PDF: PdfFormatOption(pipeline_options=opts)}
)
result = conv.convert(str(src))
dst.parent.mkdir(parents=True, exist_ok=True)
try:
    from docling_core.types.doc import ImageRefMode
    md = result.document.export_to_markdown(image_mode=ImageRefMode.EMBEDDED)
except Exception:
    md = result.document.export_to_markdown()
dst.write_text(md, encoding="utf-8")
"""#

    /// Returns a PDF MarkItDown can read. Original file is never overwritten.
    static func searchablePDF(
        from url: URL,
        force: Bool = false,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws -> (url: URL, didOCR: Bool) {
        guard force || needsOCR(url) else { return (url, false) }
        if let exe = ocrmypdfPath() {
            onStatus("OCR with OCRmyPDF (Tesseract)…")
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("yourMark-ocr-\(UUID().uuidString).pdf")
            let args = [
                force ? "--force-ocr" : "--skip-text",
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

    /// Last resort when the Markdown is still empty after convert.
    /// Does not append full-page pictures onto a file that already has text
    /// (that doubled huge manuals and froze the preview).
    static func enrichMarkdown(
        markdownURL: URL,
        sourcePDF: URL,
        onStatus: @escaping @Sendable (String) -> Void
    ) async {
        guard markdownLooksEmpty(markdownURL) else { return }
        guard let doc = PDFDocument(url: sourcePDF), doc.pageCount > 0 else { return }
        onStatus("Keeping page pictures so diagrams stay visible…")

        let figDir = markdownURL.deletingLastPathComponent()
            .appendingPathComponent(PdfFigures.folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: figDir, withIntermediateDirectories: true)

        var parts: [String] = [
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
                parts.append("![\(heading)](\(PdfFigures.folderName)/\(file))")
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
        return raw ?? "Page \(index + 1)"
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
                do {
                    let result = try ProcessRun.run(
                        executable: exe,
                        arguments: args,
                        captureStdout: true
                    )
                    let msg = result.stderr.isEmpty ? result.stdout : result.stderr
                    if result.status == 0 {
                        cont.resume(returning: msg)
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "OcrService",
                            code: Int(result.status),
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
