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
    public func convert(input: URL, outputFolder: URL) async throws -> ConvertResult {
        if let seconds = options.timeoutSeconds {
            return try await Self.withTimeout(seconds: seconds) {
                try await self.convertWork(input: input, outputFolder: outputFolder)
            }
        }
        return try await convertWork(input: input, outputFolder: outputFolder)
    }

    /// First of `operation` or a timeout. Used by `convert` and by tests.
    public static func withTimeout<T: Sendable>(
        seconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        if seconds <= 0 { throw YourMarkError.timedOut }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                throw YourMarkError.timedOut
            }
            guard let first = try await group.next() else {
                throw YourMarkError.processFailed("Conversion ended without a result")
            }
            group.cancelAll()
            return first
        }
    }
    
    private func convertWork(input: URL, outputFolder: URL) async throws -> ConvertResult {
        let startTime = Date()
        var warnings: [String] = []
        var usedOCR = false
        var ocrEngine: String? = nil
        var pictures = 0
        var originalKept = false
        let lang = options.ocrLanguage
        let script = ConversionSupport.markitdownConvertScriptURL()
        
        let isPDF = input.pathExtension.lowercased() == "pdf"
        let needsOCR = options.ocrEnabled && isPDF && OcrService.needsOCR(input)
        
        let outputName = outputFolderName(for: input)
        let output = outputFolder.appendingPathComponent(outputName, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        
        let markdownName = outputName + ".md"
        let markdownURL = output.appendingPathComponent(markdownName)
        
        let enginePath = try? await service.resolveEngine()
        let pythonReady = enginePath != nil
        
        if !pythonReady {
            reportStatus("Converting with Apple PDFKit and Live Text")
            _ = try await NativeConvert.convert(
                input: input,
                output: markdownURL,
                ocr: options.ocrEnabled && needsOCR,
                ocrLanguage: lang,
                onStatus: { [weak self] msg in self?.onStatus?(msg) }
            )
            
            if isPDF {
                await tidyPDFMarkdown(markdownURL, pdf: input)
                let bookmarks = await loadBookmarks(input)
                let (final, _) = await finalizeMarkdown(markdownURL, original: input, bookmarks: bookmarks)
                pictures = await PdfFigures.embed(
                    markdownURL: final,
                    sourcePDF: input,
                    stripChrome: options.stripChrome,
                    onStatus: { [weak self] msg in self?.onStatus?(msg) }
                )
            }
            
            usedOCR = needsOCR && options.ocrEnabled
            if usedOCR { ocrEngine = "Apple Vision" }
            let pages = isPDF ? await PdfWork.runAsync { OcrService.pageCount(of: input) } : 1
            let weakFlag = await checkWeakOCR(markdownURL: markdownURL, pages: pages, usedOCR: usedOCR)
            let weakOCR = usedOCR && weakFlag
            noteWeakOCR(&warnings, weakOCR: weakOCR)
            originalKept = shouldKeepOriginal(usedOCR: usedOCR, weakOCR: weakOCR, input: input, outputFolder: output)
            
            let elapsed = Date().timeIntervalSince(startTime)
            return ConvertResult(
                markdownURL: markdownURL,
                originalKept: originalKept,
                usedOCR: usedOCR,
                ocrEngine: ocrEngine,
                pictures: pictures,
                warnings: warnings,
                elapsedSeconds: elapsed,
                weakOCR: weakOCR
            )
        }
        
        var inputForConvert = input
        var ocrTempPDF: URL?
        defer {
            if let temp = ocrTempPDF { try? FileManager.default.removeItem(at: temp) }
        }
        
        let layoutFirst = options.prefersDocling && isPDF && needsOCR
        if layoutFirst {
            reportStatus("Layout OCR first — this takes a little longer")
            let layoutResult = await OcrService.layoutMarkdown(
                from: input,
                to: markdownURL,
                ocr: needsOCR,
                ocrLanguage: lang,
                onStatus: { [weak self] msg in self?.onStatus?(msg) }
            )
            
            if layoutResult {
                usedOCR = true
                ocrEngine = "Docling"
                let bookmarks = await loadBookmarks(input)
                let (final, _) = await finalizeMarkdown(markdownURL, original: input, bookmarks: bookmarks)
                pictures = await PdfFigures.materializeEmbedded(markdownURL: final)
                let pages = await PdfWork.runAsync { OcrService.pageCount(of: input) }
                let weakFlag = await checkWeakOCR(markdownURL: markdownURL, pages: pages, usedOCR: usedOCR)
                let weakOCR = usedOCR && weakFlag
                noteWeakOCR(&warnings, weakOCR: weakOCR)
                originalKept = shouldKeepOriginal(usedOCR: usedOCR, weakOCR: weakOCR, input: input, outputFolder: output)
                let elapsed = Date().timeIntervalSince(startTime)
                return ConvertResult(
                    markdownURL: markdownURL,
                    originalKept: originalKept,
                    usedOCR: usedOCR,
                    ocrEngine: ocrEngine,
                    pictures: pictures,
                    warnings: warnings,
                    elapsedSeconds: elapsed,
                    weakOCR: weakOCR
                )
            }
            
            reportStatus("OCR with OCRmyPDF")
            let prepared = try await OcrService.searchablePDF(
                from: input,
                ocrLanguage: lang,
                onStatus: { [weak self] msg in self?.onStatus?(msg) }
            )
            inputForConvert = prepared.url
            usedOCR = prepared.didOCR
            if prepared.url != input { ocrTempPDF = prepared.url }
            if usedOCR { ocrEngine = "OCRmyPDF + Tesseract" }
        }
        
        reportStatus("Converting with MarkItDown")
        try await convertWithMarkItDownOrNative(input: inputForConvert, markdownURL: markdownURL, script: script)
        
        if isPDF {
            let pages = await PdfWork.runAsync { OcrService.pageCount(of: input) }
            let thin = await PdfWork.runAsync {
                OcrService.markdownLooksThin(markdownURL, pageCount: max(pages, 1))
            }
            
            if options.ocrEnabled, thin, !usedOCR {
                reportStatus("Scan detected — running OCR")
                let layoutResult = await OcrService.layoutMarkdown(
                    from: input,
                    to: markdownURL,
                    ocr: true,
                    ocrLanguage: lang,
                    onStatus: { [weak self] msg in self?.onStatus?(msg) }
                )
                
                if layoutResult {
                    usedOCR = true
                    ocrEngine = "Docling"
                } else {
                    let prepared = try await OcrService.searchablePDF(
                        from: input,
                        force: true,
                        ocrLanguage: lang,
                        onStatus: { [weak self] msg in self?.onStatus?(msg) }
                    )
                    usedOCR = true
                    ocrEngine = "OCRmyPDF + Tesseract"
                    if prepared.url != input { ocrTempPDF = prepared.url }
                    if prepared.didOCR || prepared.url != input {
                        try await convertWithMarkItDownOrNative(input: prepared.url, markdownURL: markdownURL, script: script)
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
                    ocrLanguage: lang,
                    onStatus: { [weak self] msg in self?.onStatus?(msg) }
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
                    onStatus: { [weak self] msg in self?.onStatus?(msg) }
                )
            }
            
            let weakFlag = await checkWeakOCR(markdownURL: markdownURL, pages: pages, usedOCR: usedOCR)
            let weakOCR = usedOCR && weakFlag
            noteWeakOCR(&warnings, weakOCR: weakOCR)
            originalKept = shouldKeepOriginal(usedOCR: usedOCR, weakOCR: weakOCR, input: input, outputFolder: output)
            
            let elapsed = Date().timeIntervalSince(startTime)
            return ConvertResult(
                markdownURL: markdownURL,
                originalKept: originalKept,
                usedOCR: usedOCR,
                ocrEngine: ocrEngine,
                pictures: pictures,
                warnings: warnings,
                elapsedSeconds: elapsed,
                weakOCR: weakOCR
            )
        }
        
        let bookmarks = await loadBookmarks(input)
        _ = await finalizeMarkdown(markdownURL, original: input, bookmarks: bookmarks)
        let weakFlag = await checkWeakOCR(markdownURL: markdownURL, pages: 1, usedOCR: usedOCR)
        let weakOCR = usedOCR && weakFlag
        noteWeakOCR(&warnings, weakOCR: weakOCR)
        
        let elapsed = Date().timeIntervalSince(startTime)
        return ConvertResult(
            markdownURL: markdownURL,
            originalKept: originalKept,
            usedOCR: usedOCR,
            ocrEngine: ocrEngine,
            pictures: pictures,
            warnings: warnings,
            elapsedSeconds: elapsed,
            weakOCR: weakOCR
        )
    }

    private func convertWithMarkItDownOrNative(input: URL, markdownURL: URL, script: URL?) async throws {
        do {
            _ = try await service.convert(
                input: input,
                output: markdownURL,
                script: script,
                llmKey: "",
                llmBase: options.askBaseURL,
                llmModel: options.askModel
            )
        } catch is ProcessRun.ConvertCancel {
            throw ProcessRun.ConvertCancel.stopped
        } catch {
            reportStatus("MarkItDown failed — using Apple PDFKit and Live Text")
            _ = try await NativeConvert.convert(
                input: input,
                output: markdownURL,
                ocr: options.ocrEnabled,
                ocrLanguage: options.ocrLanguage,
                onStatus: { [weak self] msg in self?.onStatus?(msg) }
            )
        }
    }

    private func noteWeakOCR(_ warnings: inout [String], weakOCR: Bool) {
        if weakOCR {
            warnings.append("OCR quality is below the threshold")
        }
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
        await PdfWork.runAsync { PdfSidecar.bookmarks(from: url) }
    }
    
    private func finalizeMarkdown(
        _ url: URL,
        original: URL,
        bookmarks: [ManualBookmark],
        header: BookRecord? = nil
    ) async -> (URL, [ManualBookmark]) {
        _ = header
        return (url, bookmarks)
    }
    
    private func checkWeakOCR(markdownURL: URL, pages: Int, usedOCR: Bool) async -> Bool {
        guard usedOCR else { return false }
        guard let content = try? String(contentsOf: markdownURL) else { return false }
        let chars = content.trimmingCharacters(in: .whitespacesAndNewlines).count
        let charsPerPage = chars / max(pages, 1)
        if charsPerPage < OCRQuality.minCharsPerOCRPage { return true }
        if let mean = OCRVisionMetrics.meanConfidence, mean < OCRQuality.weakConfidenceThreshold {
            return true
        }
        return false
    }
    
    private func shouldKeepOriginal(usedOCR: Bool, weakOCR: Bool, input: URL, outputFolder: URL) -> Bool {
        switch options.keepOriginalPDF {
        case .always:
            copyOriginal(from: input, to: outputFolder)
            return true
        case .never:
            return false
        case .auto:
            if usedOCR && weakOCR {
                copyOriginal(from: input, to: outputFolder)
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