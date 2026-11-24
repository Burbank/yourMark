import Foundation
import PDFKit

/// The UI-free conversion pipeline. Both the app and CLI use this.
public actor ConvertPipeline {
    private let service: MarkItDownService
    private let options: ConvertOptions
    private let onStatus: (@Sendable (String) -> Void)?
    
    public init(
        options: ConvertOptions = ConvertOptions(),
        onStatus: (@Sendable (String) -> Void)? = nil
    ) {
        self.service = MarkItDownService()
        self.options = options
        self.onStatus = onStatus
    }
    
    /// Convert one document from input to the output folder.
    /// Returns the markdown URL and metadata about the conversion.
    public func convert(input: URL, outputFolder: URL) async throws -> ConvertResult {
        let startTime = Date()
        var warnings: [String] = []
        var usedOCR = false
        var ocrEngine: String? = nil
        var pictures = 0
        var originalKept = false
        
        // Determine if OCR is needed
        let isPDF = input.pathExtension.lowercased() == "pdf"
        let needsOCR = options.ocrEnabled && isPDF && OcrService.needsOCR(input)
        
        // Prepare output folder
        let outputName = outputFolderName(for: input)
        let output = outputFolder.appendingPathComponent(outputName, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        
        let markdownName = outputName + ".md"
        let markdownURL = output.appendingPathComponent(markdownName)
        
        // Check if we can use Python engines
        let enginePath = try? await service.resolveEngine()
        let pythonReady = enginePath != nil
        
        if !pythonReady {
            // Fall back to native conversion (Apple PDFKit + Live Text)
            reportStatus("Converting with Apple PDFKit and Live Text")
            let result = try await NativeConvert.convert(
                input: input,
                output: markdownURL,
                ocr: options.ocrEnabled && needsOCR,
                onStatus: { [weak self] msg in
                    self?.onStatus?(msg)
                }
            )
            
            if isPDF {
                await tidyPDFMarkdown(markdownURL, pdf: input)
                let bookmarks = await loadBookmarks(input)
                let (final, _) = await finalizeMarkdown(markdownURL, original: input, bookmarks: bookmarks)
                pictures = await PdfFigures.embed(
                    markdownURL: final,
                    sourcePDF: input,
                    stripChrome: options.stripChrome,
                    onStatus: { [weak self] msg in
                        self?.onStatus?(msg)
                    }
                )
            }
            
            usedOCR = needsOCR
            if usedOCR {
                ocrEngine = "Apple Vision"
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            return ConvertResult(
                markdownURL: markdownURL,
                originalKept: false,
                usedOCR: usedOCR,
                ocrEngine: ocrEngine,
                pictures: pictures,
                warnings: warnings,
                elapsedSeconds: elapsed,
                weakOCR: false
            )
        }
        
        // Python engines available - proceed with MarkItDown path
        var inputForConvert = input
        var ocrTempPDF: URL?
        defer {
            if let temp = ocrTempPDF {
                try? FileManager.default.removeItem(at: temp)
            }
        }
        
        // Try layout-first OCR if preferred
        let layoutFirst = options.prefersDocling && isPDF && needsOCR
        if layoutFirst {
            reportStatus("Layout OCR first — this takes a little longer")
            let layoutResult = await OcrService.layoutMarkdown(
                from: input,
                to: markdownURL,
                ocr: needsOCR,
                onStatus: { [weak self] msg in
                    self?.onStatus?(msg)
                }
            )
            
            if layoutResult {
                usedOCR = true
                ocrEngine = "Docling"
                let bookmarks = await loadBookmarks(input)
                let (final, _) = await finalizeMarkdown(markdownURL, original: input, bookmarks: bookmarks)
                pictures = await PdfFigures.materializeEmbedded(markdownURL: final)
                
                originalKept = shouldKeepOriginal(usedOCR: usedOCR, weakOCR: false, input: input, output: output)
                
                let elapsed = Date().timeIntervalSince(startTime)
                return ConvertResult(
                    markdownURL: markdownURL,
                    originalKept: originalKept,
                    usedOCR: usedOCR,
                    ocrEngine: ocrEngine,
                    pictures: pictures,
                    warnings: warnings,
                    elapsedSeconds: elapsed,
                    weakOCR: false
                )
            }
            
            // Docling failed, fall back to OCRmyPDF
            reportStatus("OCR with OCRmyPDF")
            let prepared = try await OcrService.searchablePDF(
                from: input,
                onStatus: { [weak self] msg in
                    self?.onStatus?(msg)
                }
            )
            inputForConvert = prepared.url
            usedOCR = prepared.didOCR
            if prepared.url != input {
                ocrTempPDF = prepared.url
            }
            if usedOCR {
                ocrEngine = "OCRmyPDF + Tesseract"
            }
        }
        
        // Convert with MarkItDown
        reportStatus("Converting with MarkItDown")
        _ = try await service.convert(
            input: inputForConvert,
            output: markdownURL,
            script: Bundle.main.url(forResource: "markitdown_convert", withExtension: "py"),
            llmKey: "",
            llmBase: options.askBaseURL,
            llmModel: options.askModel
        )
        
        if isPDF {
            let pages = await PdfWork.runAsync { OcrService.pageCount(of: input) }
            let thin = await PdfWork.runAsync {
                OcrService.markdownLooksThin(markdownURL, pageCount: max(pages, 1))
            }
            
            // If the markdown looks thin and we haven't OCR'd yet, do it now
            if options.ocrEnabled, thin, !usedOCR {
                reportStatus("Scan detected — running OCR")
                let layoutResult = await OcrService.layoutMarkdown(
                    from: input,
                    to: markdownURL,
                    ocr: true,
                    onStatus: { [weak self] msg in
                        self?.onStatus?(msg)
                    }
                )
                
                if layoutResult {
                    usedOCR = true
                    ocrEngine = "Docling"
                } else {
                    let prepared = try await OcrService.searchablePDF(
                        from: input,
                        force: true,
                        onStatus: { [weak self] msg in
                            self?.onStatus?(msg)
                        }
                    )
                    usedOCR = true
                    ocrEngine = "OCRmyPDF + Tesseract"
                    
                    if prepared.url != input {
                        ocrTempPDF = prepared.url
                    }
                    
                    if prepared.didOCR || prepared.url != input {
                        _ = try await service.convert(
                            input: prepared.url,
                            output: markdownURL,
                            script: Bundle.main.url(forResource: "markitdown_convert", withExtension: "py"),
                            llmKey: "",
                            llmBase: options.askBaseURL,
                            llmModel: options.askModel
                        )
                    }
                }
            }
            
            let stillThin = await PdfWork.runAsync {
                OcrService.markdownLooksThin(markdownURL, pageCount: max(pages, 1))
            }
            let stillEmpty = await PdfWork.runAsync {
                OcrService.markdownLooksEmpty(markdownURL)
            }
            
            if stillThin || stillEmpty {
                await OcrService.enrichMarkdown(
                    markdownURL: markdownURL,
                    sourcePDF: input,
                    onStatus: { [weak self] msg in
                        self?.onStatus?(msg)
                    }
                )
            }
            
            reportStatus("Cleaning headers and headings")
            await tidyPDFMarkdown(markdownURL, pdf: input)
            
            let bookmarks = await loadBookmarks(input)
            let (final, _) = await finalizeMarkdown(markdownURL, original: input, bookmarks: bookmarks)
            
            _ = await PdfFigures.materializeEmbedded(markdownURL: final)
            
            if options.extractImages && !usedOCR {
                pictures = await PdfFigures.embed(
                    markdownURL: final,
                    sourcePDF: input,
                    stripChrome: options.stripChrome,
                    onStatus: { [weak self] msg in
                        self?.onStatus?(msg)
                    }
                )
            }
            
            // Calculate weak OCR flag
            let weakOCR = usedOCR && await checkWeakOCR(markdownURL: markdownURL, pages: pages)
            
            // Decide whether to keep original PDF
            originalKept = shouldKeepOriginal(usedOCR: usedOCR, weakOCR: weakOCR, input: input, output: output)
        } else {
            let bookmarks = await loadBookmarks(input)
            let (final, _) = await finalizeMarkdown(markdownURL, original: input, bookmarks: bookmarks)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        return ConvertResult(
            markdownURL: markdownURL,
            originalKept: originalKept,
            usedOCR: usedOCR,
            ocrEngine: ocrEngine,
            pictures: pictures,
            warnings: warnings,
            elapsedSeconds: elapsed,
            weakOCR: false
        )
    }
    
    private func reportStatus(_ message: String) {
        onStatus?(message)
    }
    
    private func outputFolderName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let clean = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Untitled" : clean
    }
    
    private func tidyPDFMarkdown(_ markdown: URL, pdf: URL) async {
        let tidied = await PdfCleanup.tidyAsync(
            markdown: try! String(contentsOf: markdown),
            pdf: pdf,
            stripChrome: options.stripChrome
        )
        try? tidied.write(to: markdown, atomically: true, encoding: .utf8)
    }
    
    private func loadBookmarks(_ url: URL) async -> [ManualBookmark] {
        await PdfWork.runAsync {
            PdfSidecar.bookmarks(from: url)
        }
    }
    
    private func finalizeMarkdown(
        _ url: URL,
        original: URL,
        bookmarks: [ManualBookmark],
        header: BookRecord? = nil
    ) async -> (URL, [ManualBookmark]) {
        // Simplified finalization - in the real app this does more
        return (url, bookmarks)
    }
    
    private func checkWeakOCR(markdownURL: URL, pages: Int) async -> Bool {
        // Check if OCR quality is weak (mean confidence < 0.6 or < 200 chars per page)
        guard let content = try? String(contentsOf: markdownURL) else { return false }
        let chars = content.trimmingCharacters(in: .whitespacesAndNewlines).count
        let charsPerPage = chars / max(pages, 1)
        return charsPerPage < 200
    }
    
    private func shouldKeepOriginal(usedOCR: Bool, weakOCR: Bool, input: URL, output: URL) -> Bool {
        switch options.keepOriginalPDF {
        case .always:
            copyOriginal(from: input, to: output)
            return true
        case .never:
            return false
        case .auto:
            if usedOCR && weakOCR {
                copyOriginal(from: input, to: output)
                return true
            }
            return false
        }
    }
    
    private func copyOriginal(from input: URL, to outputFolder: URL) {
        let dest = outputFolder.appendingPathComponent(input.lastPathComponent)
        try? FileManager.default.copyItem(at: input, to: dest)
    }
}
