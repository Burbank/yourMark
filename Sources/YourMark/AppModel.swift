import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class AppModel {
    var selectedTool: AppTool = .library
    var enginePath: String?
    var engineVersion: String = "checking…"
    var isBusy = false
    var installingEngine = false
    var installLog = ""
    var statusText = "Ready"
    var appearance: String = UserDefaults.standard.string(forKey: "appearance") ?? "system"
    var errorMessage: String?
    var showHelp = false
    var showSettings = false
    var jobs: [ConvertJob] = []
    var library: [LibraryItem] = []
    var selectedLibraryID: UUID?
    var previewMarkdown: String = ""
    var lastUpgradeLog: String = ""
    var scrollToLine: Int?
    var askProvider: String = UserDefaults.standard.string(forKey: "askProvider") ?? "xai"
    var askModel: String = UserDefaults.standard.string(forKey: "askModel") ?? AskModels.defaultID(for: UserDefaults.standard.string(forKey: "askProvider") ?? "xai")
    var askBaseURL: String = UserDefaults.standard.string(forKey: "askBaseURL") ?? "https://api.x.ai/v1"
    var askKeyDraft: String = ""
    var askHasKey = false
    var askQuestion = ""
    var askChapter = "Entire file"
    var askAnswer = ""
    var askOpenAnswer = ""
    var askBusy = false
    var askError = ""
    var askWebFallback = UserDefaults.standard.bool(forKey: "askWebFallback")
    var filePlace: String = UserDefaults.standard.string(forKey: "filePlace") ?? "beside"
    var customFolderPath: String = UserDefaults.standard.string(forKey: "customFolder") ?? ""
    var fileNotice: String = ""
    var appUpdateTag: String?
    var appUpdateURL: URL?
    var draggingFiles = false
    var ocrEnabled = UserDefaults.standard.object(forKey: "ocrEnabled") as? Bool ?? true
    var showInstallSheet = false
    var showOCRSheet = false
    var settingsFocus: String = ""
    var showDoclingPrompt = false
    var pendingGraphics: [URL] = []
    var aiChaptersEnabled = UserDefaults.standard.object(forKey: "aiChaptersEnabled") as? Bool ?? false
    private var convertWanted = false

    let service = MarkItDownService()
    private let askService = AskService()
    private let libraryURL: URL
    private let convertedDir: URL
    private let watcher = FileWatcher()
    private var watchDebounce: Task<Void, Never>?
    private var watchedPaths: Set<String> = []

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = appSupport.appendingPathComponent("yourMark", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        libraryURL = dir.appendingPathComponent("library.json")
        convertedDir = dir.appendingPathComponent("Converted", isDirectory: true)
        try? FileManager.default.createDirectory(at: convertedDir, withIntermediateDirectories: true)
        loadLibrary()
        seedGuideIfNeeded()
        let stored = AskSecrets.load()
        askHasKey = !stored.isEmpty
        askKeyDraft = stored
        watcher.onChange = { [weak self] path in
            Task { @MainActor in self?.fileDidChange(path) }
        }
        startWatching()
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case "bright": return .light
        case "dim": return .dark
        default: return nil
        }
    }

    func setAppearance(_ value: String) {
        appearance = value
        UserDefaults.standard.set(value, forKey: "appearance")
    }

    func bootstrap() async {
        let status = await service.refreshStatus()
        enginePath = status.path
        engineVersion = status.version
        if !UserDefaults.standard.bool(forKey: "sawInstallSheet") {
            showInstallSheet = true
            if status.path != nil {
                statusText = "MarkItDown \(status.version)"
            }
            return
        }
        if !UserDefaults.standard.bool(forKey: "sawOCRSheet") {
            showOCRSheet = true
        }
        if status.path == nil, !installingEngine {
            statusText = "Installing Microsoft MarkItDown…"
            await installEngine()
        } else if status.path != nil {
            statusText = "MarkItDown \(status.version)"
            Task { await checkUpdates(force: false) }
        }
    }

    func acceptFirstRunInstall() async {
        UserDefaults.standard.set(true, forKey: "sawInstallSheet")
        showInstallSheet = false
        await installEngine()
        if !UserDefaults.standard.bool(forKey: "sawOCRSheet") {
            showOCRSheet = true
        }
        Task { await checkUpdates(force: false) }
    }

    func skipFirstRunInstall() async {
        showInstallSheet = false
        let first = !UserDefaults.standard.bool(forKey: "sawInstallSheet")
        UserDefaults.standard.set(true, forKey: "sawInstallSheet")
        if first, enginePath == nil {
            await installEngine()
        }
        if !UserDefaults.standard.bool(forKey: "sawOCRSheet") {
            showOCRSheet = true
        }
        Task { await checkUpdates(force: false) }
    }

    func openScanSettings() {
        UserDefaults.standard.set(true, forKey: "sawOCRSheet")
        showOCRSheet = false
        showHelp = false
        showSettings = true
        settingsFocus = "ocr"
    }

    func skipOCRSheet() {
        UserDefaults.standard.set(true, forKey: "sawOCRSheet")
        showOCRSheet = false
    }

    func acceptOCRInstall() async {
        UserDefaults.standard.set(true, forKey: "sawOCRSheet")
        showOCRSheet = false
        await installDocling()
        UserDefaults.standard.set(true, forKey: "doclingReady")
        showSettings = true
        settingsFocus = "ocr"
    }

    func installEngine() async {
        installingEngine = true
        installLog = "Getting Microsoft MarkItDown…"
        statusText = "Installing converter…"
        defer { installingEngine = false }
        do {
            installLog = try await service.installEngine()
            await bootstrapQuiet()
            statusText = "MarkItDown \(engineVersion)"
        } catch {
            installLog = error.localizedDescription
            statusText = "Converter not installed"
        }
    }

    private func bootstrapQuiet() async {
        let status = await service.refreshStatus()
        enginePath = status.path
        engineVersion = status.version
    }

    func clearError() { errorMessage = nil }

    func selectTool(_ tool: AppTool) {
        selectedTool = tool
        showSettings = false
        showHelp = false
    }

    func toggleSettings() {
        showHelp = false
        showSettings.toggle()
    }

    func toggleHelp() {
        showSettings = false
        showHelp.toggle()
    }

    static let guideID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    var showInfoButton: Bool { true }

    func removeLibrary(_ item: LibraryItem) {
        if item.id == Self.guideID {
            UserDefaults.standard.set(true, forKey: "dismissedGuide")
            try? FileManager.default.removeItem(atPath: item.markdownPath)
        }
        library.removeAll { $0.id == item.id }
        if selectedLibraryID == item.id {
            if let next = library.first {
                selectLibrary(next)
            } else {
                selectedLibraryID = nil
                previewMarkdown = ""
            }
        }
        saveLibrary()
        startWatching()
    }

    func moveLibrary(from: IndexSet, to: Int) {
        library.move(fromOffsets: from, toOffset: to)
        saveLibrary()
    }

    private func seedGuideIfNeeded() {
        if UserDefaults.standard.bool(forKey: "dismissedGuide") { return }
        if library.contains(where: { $0.id == Self.guideID }) { return }
        let url = convertedDir.appendingPathComponent("Getting started with yourMark.md")
        try? Self.guideMarkdown.write(to: url, atomically: true, encoding: .utf8)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let item = LibraryItem(
            id: Self.guideID,
            title: "Getting started with yourMark",
            sourceName: "Guide",
            markdownPath: url.path,
            addedAt: Date.distantPast,
            byteCount: Int64(values?.fileSize ?? 0),
            bookmarks: [],
            sourcePath: ""
        )
        library.insert(item, at: 0)
        saveLibrary()
        if selectedLibraryID == nil {
            selectLibrary(item)
        }
    }

    static let guideMarkdown = """
    # Getting started with yourMark

    Turn PDFs, Word, and slides into Markdown you can search, bookmark, and ask.

    Swipe this card **to the left** when you are done — the **i** in the header always opens this same guide. Right-click a card for Open, Show in Finder, and Delete.

    ## Why Markdown

    A PDF is a picture of a page. Markdown is the words, in order, as plain text you can search and edit.

    That is why it works so well with AI. A model can read a chapter, quote it, and tell you when the file is silent — instead of guessing at columns or a scan. You can paste one heading into Grok or ChatGPT, keep notes in Obsidian, or search a whole course. Tables stay tables. Headings stay an outline.

    Keep the original PDF. Markdown is the working copy.

    ## Convert

    Drop a PDF **anywhere** on yourMark — Library, Bookmarks, Convert, the header. Conversion starts at once if nothing else is running. Graphic PDFs ask to install Docling first.

    Settings → **Automatically add chapters with AI** (off unless you tick it) uses your Ask key to insert headings when the file has no outline.

    If the PDF is a **scan** (no text layer), yourMark uses IBM **Docling** for layout — tables, columns, figures. That takes a little longer than a normal convert. Microsoft MarkItDown still handles ordinary PDFs. If Docling is missing, we fall back to OCRmyPDF / Apple Live Text and keep page pictures.

    ## Bookmarks

    The Bookmarks pane is the PDF outline when the file has one, otherwise headings. Click to jump, like Preview.

    ## Tables and figures

    Real tables become Markdown tables. Pictures sit in reading order. Scans get OCR first; page pictures are kept so arrows and diagrams still show.

    ## Library cards

    Swipe a card left to delete, or right-click for Open, Show in Finder, and Delete. **Show in Finder** selects the file. If you change that file, the library updates. Drag to rearrange.

    ## Ask chapter

    Open a file, pick a heading, and ask. The answer comes only from that chapter. With your own key (Settings) you can also ask the entire file.

    If the chapter does not provide an answer, **Search the web** opens a browser tab with the question, the chapter, and that sentence.

    ## Settings

    Pick the model, paste your API key, and choose where converted files go:

    - **Next to the original PDF**
    - **yourMark library folder**
    - **Choose a folder** — opens Finder

    The key stays on this Mac, in the Keychain.

    Optionally (off by default): if the chapter does not provide an answer, also show a **model summary** below, labelled as not from the file.

    ## Themes

    **SYSTEM** follows the computer. **BRIGHT** is indoor paper. **DIM** is the dark deck.

    ## After this file

    Swipe this card left to delete it. The **i** in the header shows this guide whenever you need it — even after this card is gone.
    """

    func persistAskSettings() {
        UserDefaults.standard.set(askProvider, forKey: "askProvider")
        UserDefaults.standard.set(askModel, forKey: "askModel")
        UserDefaults.standard.set(askBaseURL, forKey: "askBaseURL")
        UserDefaults.standard.set(askWebFallback, forKey: "askWebFallback")
        UserDefaults.standard.set(filePlace, forKey: "filePlace")
        UserDefaults.standard.set(customFolderPath, forKey: "customFolder")
        UserDefaults.standard.set(ocrEnabled, forKey: "ocrEnabled")
        UserDefaults.standard.set(aiChaptersEnabled, forKey: "aiChaptersEnabled")
        AskSecrets.save(askKeyDraft)
        askHasKey = !AskSecrets.load().isEmpty
        statusText = askHasKey ? "Ask key saved in Keychain" : "Ask key cleared"
    }

    func clearAskKey() {
        askKeyDraft = ""
        AskSecrets.delete()
        askHasKey = false
        statusText = "Ask key cleared"
    }

    func runAsk() async {
        let q = askQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        askBusy = true
        askError = ""
        askAnswer = ""
        askOpenAnswer = ""
        defer { askBusy = false }
        do {
            let excerpt = AskService.excerpt(
                markdown: previewMarkdown,
                heading: askChapter
            )
            let title = library.first(where: { $0.id == selectedLibraryID })?.title ?? "Document"
            let settings = AskService.Settings(
                provider: askProvider,
                model: askModel,
                baseURL: askBaseURL,
                apiKey: AskSecrets.load()
            )
            askAnswer = try await askService.ask(
                question: q,
                title: title,
                excerpt: excerpt,
                settings: settings
            )
            if askWebFallback, AskService.chapterWasSilent(askAnswer) {
                askOpenAnswer = try await askService.ask(
                    question: q,
                    title: title,
                    excerpt: excerpt,
                    settings: settings,
                    openKnowledge: true
                )
            }
        } catch {
            askError = error.localizedDescription
        }
    }

    func clearAsk() {
        askAnswer = ""
        askOpenAnswer = ""
        askError = ""
        askQuestion = ""
    }

    func searchAskOnWeb() {
        let note = askAnswer.split(separator: "\n").first.map(String.init) ?? ""
        let q = AskService.searchQuery(
            question: askQuestion,
            title: library.first(where: { $0.id == selectedLibraryID })?.title ?? "",
            chapter: askChapter,
            note: note
        )
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openIncoming(_ urls: [URL]) {
        let allowed = urls.filter { ConvertibleKind.allows($0) }
        guard !allowed.isEmpty else { return }
        for url in allowed { _ = url.startAccessingSecurityScopedResource() }
        showSettings = false
        showHelp = false
        selectedTool = .convert
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)

        let graphic = allowed.filter {
            $0.pathExtension.lowercased() == "pdf" && ocrEnabled && OcrService.looksGraphic($0)
        }
        let rest = allowed.filter { url in !graphic.contains(where: { $0.path == url.path }) }
        if !rest.isEmpty { enqueue(rest) }

        let doclingReady = OcrService.doclingPath() != nil
            || UserDefaults.standard.bool(forKey: "doclingReady")
        if !graphic.isEmpty, !doclingReady {
            pendingGraphics.append(contentsOf: graphic.filter { g in
                !pendingGraphics.contains(where: { $0.path == g.path })
            })
            showDoclingPrompt = true
        } else if !graphic.isEmpty {
            enqueue(graphic)
        }

        Task { await convertQueued() }
    }

    func acceptDoclingInstall() async {
        let waiting = pendingGraphics
        pendingGraphics = []
        showDoclingPrompt = false
        enqueue(waiting)
        await installDocling()
        UserDefaults.standard.set(true, forKey: "doclingReady")
        await convertQueued()
    }

    func skipDoclingInstall() {
        showDoclingPrompt = false
        let waiting = pendingGraphics
        pendingGraphics = []
        guard !waiting.isEmpty else { return }
        enqueue(waiting)
        Task { await convertQueued() }
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .pdf, .plainText,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data,
            UTType(filenameExtension: "html") ?? .html,
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        openIncoming(panel.urls)
    }

    func enqueue(_ urls: [URL]) {
        var scanCount = 0
        for url in urls where ConvertibleKind.allows(url) {
            if jobs.contains(where: { $0.sourceURL == url }) { continue }
            let scan = ocrEnabled
                && url.pathExtension.lowercased() == "pdf"
                && OcrService.needsOCR(url)
            if scan { scanCount += 1 }
            jobs.append(ConvertJob(
                id: UUID(),
                sourceURL: url,
                outputURL: nil,
                status: .queued,
                detail: scan
                    ? "Scan — layout OCR first, so this takes a little longer"
                    : url.path,
                startedAt: nil,
                needsOCR: scan
            ))
        }
        if scanCount > 0 {
            statusText = scanCount == 1
                ? "Scan detected — layout OCR first, so this takes a little longer"
                : "\(scanCount) scans — layout OCR first, so this takes a little longer"
        } else {
            statusText = jobs.count == 1
                ? "Queued \(urls.first?.lastPathComponent ?? "file")"
                : "Queued \(jobs.filter { $0.status == .queued }.count) files"
        }
    }

    func convertQueued() async {
        convertWanted = true
        if isBusy { return }
        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await service.resolveEngine()
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Engine missing"
            return
        }

        while convertWanted {
            convertWanted = false
            await convertOnePass()
            if jobs.contains(where: { $0.status == .queued }) {
                convertWanted = true
            }
        }
        statusText = jobs.contains(where: { $0.status == .failed }) ? "Finished with errors" : "Done"
    }

    private func convertOnePass() async {
        for index in jobs.indices where jobs[index].status == .queued || jobs[index].status == .failed {
            let original = jobs[index].sourceURL
            let jobID = jobs[index].id
            jobs[index].status = .running
            jobs[index].startedAt = Date()
            statusText = "Converting \(original.lastPathComponent)…"
            let output = outputURL(for: original)
            do {
                var input = original
                var usedOCR = false
                let graphic = ocrEnabled
                    && original.pathExtension.lowercased() == "pdf"
                    && (OcrService.needsOCR(original) || OcrService.looksGraphic(original))
                if graphic {
                    jobs[index].needsOCR = true
                    jobs[index].detail = "Layout OCR first — this takes a little longer"
                    statusText = "Layout OCR first — this takes a little longer · \(original.lastPathComponent)"
                    let onOCR: @Sendable (String) -> Void = { msg in
                        Task { @MainActor in
                            self.statusText = "Layout OCR first — this takes a little longer. \(msg)"
                            if let i = self.jobs.firstIndex(where: { $0.id == jobID }) {
                                self.jobs[i].detail = "Layout OCR first — this takes a little longer. \(msg)"
                            }
                        }
                    }
                    if await OcrService.layoutMarkdown(from: original, to: output, onStatus: onOCR) {
                        UserDefaults.standard.set(true, forKey: "doclingReady")
                        usedOCR = true
                        let url = await finalizeMarkdown(output, original: original)
                        if OcrService.markdownLooksEmpty(url) {
                            await OcrService.enrichMarkdown(markdownURL: url, sourcePDF: original, onStatus: onOCR)
                        }
                        await finishJob(jobID: jobID, markdown: url, original: original, usedOCR: true)
                        continue
                    }
                    let prepared = try await OcrService.searchablePDF(from: original, onStatus: onOCR)
                    input = prepared.url
                    usedOCR = prepared.didOCR
                    if let i = jobs.firstIndex(where: { $0.id == jobID }) {
                        jobs[i].detail = "OCR done — converting with MarkItDown…"
                    }
                    statusText = "OCR done — converting \(original.lastPathComponent)…"
                }
                let url = try await service.convert(input: input, output: output)
                if usedOCR {
                    await OcrService.enrichMarkdown(markdownURL: url, sourcePDF: original) { msg in
                        Task { @MainActor in
                            self.statusText = "OCR first — this takes a little longer. \(msg)"
                        }
                    }
                }
                let final = await finalizeMarkdown(url, original: original)
                await finishJob(jobID: jobID, markdown: final, original: original, usedOCR: usedOCR)
            } catch {
                if let i = jobs.firstIndex(where: { $0.id == jobID }) {
                    jobs[i].status = .failed
                    jobs[i].detail = error.localizedDescription
                }
            }
        }
    }

    private func finalizeMarkdown(_ url: URL, original: URL) async -> URL {
        var out = url
        let bookmarks = PdfSidecar.bookmarks(from: original)
        if !bookmarks.isEmpty, var text = try? String(contentsOf: out, encoding: .utf8) {
            if !text.contains("## Outline") {
                text = PdfSidecar.outlineMarkdown(bookmarks) + text
                try? text.write(to: out, atomically: true, encoding: .utf8)
            }
        }
        out = await maybeAddAIChapters(markdownURL: out)
        return out
    }

    private func finishJob(jobID: UUID, markdown: URL, original: URL, usedOCR: Bool) async {
        let bookmarks = PdfSidecar.bookmarks(from: original)
        if let i = jobs.firstIndex(where: { $0.id == jobID }) {
            jobs[i].status = .done
            jobs[i].outputURL = markdown
            jobs[i].detail = usedOCR
                ? "Layout OCR · \(markdown.lastPathComponent)"
                : (bookmarks.isEmpty ? markdown.path : "\(bookmarks.count) bookmarks · \(markdown.lastPathComponent)")
        }
        addToLibrary(source: original, markdown: markdown, bookmarks: bookmarks)
    }

    private func maybeAddAIChapters(markdownURL: URL) async -> URL {
        guard aiChaptersEnabled, askHasKey else { return markdownURL }
        guard var text = try? String(contentsOf: markdownURL, encoding: .utf8) else { return markdownURL }
        let headings = text.split(separator: "\n", omittingEmptySubsequences: false).compactMap {
            PdfSidecar.headingText(String($0))
        }.filter { $0.caseInsensitiveCompare("Outline") != .orderedSame }
        guard headings.count < 5 else { return markdownURL }
        statusText = "Adding chapters with AI…"
        do {
            let next = try await askService.inferChapters(
                markdown: text,
                settings: AskService.Settings(
                    provider: askProvider,
                    model: askModel,
                    baseURL: askBaseURL,
                    apiKey: AskSecrets.load()
                )
            )
            if !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try next.write(to: markdownURL, atomically: true, encoding: .utf8)
            }
        } catch {
            statusText = "Chapters skipped: \(error.localizedDescription)"
        }
        return markdownURL
    }

    func upgradeEngine() async {
        isBusy = true
        statusText = "Upgrading MarkItDown from PyPI…"
        defer { isBusy = false }
        do {
            lastUpgradeLog = try await service.upgradeEngine()
            await bootstrapQuiet()
            statusText = "Engine \(engineVersion)"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Upgrade failed"
        }
    }

    func installOcrmypdf() async {
        installingEngine = true
        statusText = "Installing OCRmyPDF (Tesseract)…"
        defer { installingEngine = false }
        do {
            lastUpgradeLog = try await OcrService.installViaHomebrew()
            statusText = OcrService.ocrmypdfPath() == nil
                ? "OCRmyPDF install finished"
                : "OCRmyPDF ready"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Apple Live Text will OCR scans"
        }
    }

    func installDocling() async {
        installingEngine = true
        statusText = "Installing Docling (layout models)… first run downloads extra files"
        defer { installingEngine = false }
        do {
            lastUpgradeLog = try await OcrService.installDocling()
            statusText = "Docling ready"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Docling install failed"
        }
    }

    func selectLibrary(_ item: LibraryItem, show: Bool = true) {
        selectedLibraryID = item.id
        if show {
            selectedTool = .library
            showSettings = false
            showHelp = false
        }
        scrollToLine = nil
        if let data = try? Data(contentsOf: URL(fileURLWithPath: item.markdownPath)),
           let text = String(data: data, encoding: .utf8) {
            previewMarkdown = text
        } else {
            previewMarkdown = "_File missing on disk._"
        }
    }

    func jumpToBookmark(_ bookmark: ManualBookmark) {
        askChapter = bookmark.title
        let lines = previewMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let pdf = selectedLibraryID.flatMap { id in
            library.first(where: { $0.id == id }).flatMap { item -> URL? in
                item.sourcePath.isEmpty ? nil : URL(fileURLWithPath: item.sourcePath)
            }
        }
        guard let idx = PdfSidecar.line(for: bookmark, in: lines, pdf: pdf) else { return }
        if scrollToLine == idx {
            scrollToLine = nil
        }
        Task { @MainActor in
            self.scrollToLine = idx
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealLibrary(_ item: LibraryItem) {
        var urls: [URL] = []
        if !item.sourcePath.isEmpty {
            urls.append(URL(fileURLWithPath: item.sourcePath))
        }
        urls.append(URL(fileURLWithPath: item.markdownPath))
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Converted Markdown will be saved here."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customFolderPath = url.path
        filePlace = "custom"
        persistAskSettings()
        statusText = "Saving Markdown in \(url.lastPathComponent)"
    }

    func outputURL(for input: URL) -> URL {
        let name = input.deletingPathExtension().lastPathComponent + ".md"
        switch filePlace {
        case "library":
            return convertedDir.appendingPathComponent(name)
        case "custom":
            if !customFolderPath.isEmpty {
                return URL(fileURLWithPath: customFolderPath).appendingPathComponent(name)
            }
            fallthrough
        default:
            return input.deletingLastPathComponent().appendingPathComponent(name)
        }
    }

    private func startWatching() {
        let paths = Set(library.flatMap { [$0.markdownPath, $0.sourcePath] }.filter { !$0.isEmpty })
        guard paths != watchedPaths else { return }
        watchedPaths = paths
        watcher.replace(paths: Array(paths))
    }

    private func fileDidChange(_ path: String) {
        watchDebounce?.cancel()
        watchDebounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            if let item = library.first(where: { $0.sourcePath == path }) {
                await reconvert(item)
            } else if let item = library.first(where: { $0.markdownPath == path }) {
                fileNotice = "Updated from Finder"
                if item.id == selectedLibraryID {
                    selectLibrary(item)
                }
            }
        }
    }

    private func reconvert(_ item: LibraryItem) async {
        guard !item.sourcePath.isEmpty else { return }
        let input = URL(fileURLWithPath: item.sourcePath)
        let output = URL(fileURLWithPath: item.markdownPath)
        statusText = "Updating \(item.title)…"
        do {
            _ = try await service.convert(input: input, output: output)
            let bookmarks = PdfSidecar.bookmarks(from: input)
            if let idx = library.firstIndex(where: { $0.id == item.id }) {
                library[idx].bookmarks = bookmarks
                if let values = try? output.resourceValues(forKeys: [.fileSizeKey]) {
                    library[idx].byteCount = Int64(values.fileSize ?? 0)
                }
                saveLibrary()
            }
            if item.id == selectedLibraryID {
                selectLibrary(library.first(where: { $0.id == item.id }) ?? item)
            }
            fileNotice = "Updated from Finder"
            statusText = "Updated \(item.title)"
        } catch {
            statusText = "Could not update \(item.title)"
        }
    }

    private func addToLibrary(source: URL, markdown: URL, bookmarks: [ManualBookmark]) {
        let values = try? markdown.resourceValues(forKeys: [.fileSizeKey])
        let item = LibraryItem(
            id: UUID(),
            title: markdown.deletingPathExtension().lastPathComponent,
            sourceName: source.lastPathComponent,
            markdownPath: markdown.path,
            addedAt: Date(),
            byteCount: Int64(values?.fileSize ?? 0),
            bookmarks: bookmarks,
            sourcePath: source.path
        )
        library.removeAll { $0.markdownPath == item.markdownPath }
        library.insert(item, at: 0)
        saveLibrary()
        startWatching()
        selectLibrary(item, show: false)
    }

    private func loadLibrary() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        library = (try? JSONDecoder().decode([LibraryItem].self, from: data)) ?? []
    }

    private func saveLibrary() {
        if let data = try? JSONEncoder().encode(library) {
            try? data.write(to: libraryURL)
        }
    }

    func checkUpdates(force: Bool) async {
        let now = Date().timeIntervalSince1970
        let lastEngine = UserDefaults.standard.double(forKey: "lastEngineCheck")
        let lastApp = UserDefaults.standard.double(forKey: "lastAppCheck")

        if force || now - lastEngine > 86_400 {
            UserDefaults.standard.set(now, forKey: "lastEngineCheck")
            if let pypi = await AppUpdates.fetchPyPIVersion() {
                let local = AppUpdates.engineVersionToken(engineVersion)
                if AppUpdates.isNewer(pypi, than: local), !isBusy, !installingEngine {
                    statusText = "Updating MarkItDown \(local) → \(pypi)…"
                    await upgradeEngine()
                }
            }
        }

        if force || now - lastApp > 43_200 {
            UserDefaults.standard.set(now, forKey: "lastAppCheck")
            if let latest = await AppUpdates.fetchLatestApp() {
                appUpdateTag = latest.tag
                appUpdateURL = latest.url
                statusText = "yourMark \(latest.tag) is available"
            } else if force {
                statusText = "yourMark \(AppUpdates.currentVersion) is current"
            }
        }
    }

    func dismissAppUpdate() {
        appUpdateTag = nil
        appUpdateURL = nil
    }

    func openAppUpdate() {
        if let appUpdateURL {
            NSWorkspace.shared.open(appUpdateURL)
        } else {
            NSWorkspace.shared.open(AppUpdates.releasesPage)
        }
    }

    static func isConvertible(_ url: URL) -> Bool {
        ConvertibleKind.allows(url)
    }
}
