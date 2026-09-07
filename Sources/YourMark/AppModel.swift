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
    var previewLines: [String] = []
    var previewHeadings: [ManualBookmark] = []
    var previewSections: [PreviewSection] = []
    var previewBaseURL: URL?
    var lastUpgradeLog: String = ""
    var scrollToLine: Int?
    var askProvider: String = UserDefaults.standard.string(forKey: "askProvider") ?? "xai"
    var askModel: String = UserDefaults.standard.string(forKey: "askModel") ?? AskModels.defaultID(for: UserDefaults.standard.string(forKey: "askProvider") ?? "xai")
    var askBaseURL: String = UserDefaults.standard.string(forKey: "askBaseURL") ?? "https://api.x.ai/v1"
    var askKeyDraft: String = ""
    var askHasKey = false
    var askKeyHint = ""
    var askCheckingKey = false
    var askKeyTail = ""
    var askKeyKind = ""
    var askKeyTestPassed = false
    var askKeyTestNote = ""
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
    var doclingPath: String? = OcrService.doclingPath()
    var ocrmypdfPath: String? = OcrService.ocrmypdfPath()
    private var convertWanted = false
    private var ignoreWatchUntil = Date.distantPast
    private var previewGen = 0
    private var previewNeedsLoad = false

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
        askKeyDraft = ""
        refreshKeyMeta(stored)
        askKeyTestPassed = askHasKey && UserDefaults.standard.bool(forKey: "askKeyTestPassed")
        askKeyTestNote = askHasKey ? (UserDefaults.standard.string(forKey: "askKeyTestNote") ?? "") : ""
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
        refreshOCRTools()
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
        refreshOCRTools()
    }

    func refreshOCRTools() {
        doclingPath = OcrService.doclingPath()
        ocrmypdfPath = OcrService.ocrmypdfPath()
    }

    func clearError() { errorMessage = nil }

    func selectTool(_ tool: AppTool) {
        selectedTool = tool
        showSettings = false
        showHelp = false
        if tool == .library, previewNeedsLoad,
           let item = library.first(where: { $0.id == selectedLibraryID }) {
            selectLibrary(item, show: false)
        }
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
                previewLines = []
                previewHeadings = []
                previewSections = []
                previewBaseURL = nil
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

    If the PDF is a **scan** (no text layer), yourMark uses IBM **Docling** for layout — tables, columns, figures. That takes a little longer than a normal convert. Microsoft MarkItDown still handles ordinary PDFs. Pictures in a digital PDF are pulled into a `*-figures` folder next to the Markdown (one extra pass, not a second convert). If Docling is missing, we fall back to OCRmyPDF / Apple Live Text.

    ## Bookmarks

    The Bookmarks pane is the PDF outline when the file has one, otherwise headings. Click to jump, like Preview.

    ## Tables and figures

    Real tables become Markdown tables. Pictures from the PDF sit in a figures folder, linked in page order. Scans get OCR first.

    ## Library cards

    Swipe a card left to delete, or right-click for Open, Show in Finder, and Delete. **Show in Finder** selects the file. If you change that file, the library updates. Drag to rearrange.

    ## Ask chapter

    Open a file, pick a heading, and ask. The answer comes only from that chapter. With your own key (Settings) you can also ask the entire file.

    If the chapter does not provide an answer, **Search the web** opens a browser tab with the question, the chapter, and that sentence.

    ## Settings

    Pick the model, paste your API key, then press **Enter** to lock it in, and choose where converted files go:

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
        persistAskPrefs()
        askHasKey = !AskSecrets.load().isEmpty
        statusText = askHasKey ? "Ask settings saved — key still locked in" : "Ask settings saved — no key yet"
    }

    func lockAskKey() {
        let draft = AskService.normalizeKey(askKeyDraft)
        let clip = AskService.normalizeKey(NSPasteboard.general.string(forType: .string) ?? "")
        var key = draft
        if Self.isPlausibleClipboardKey(clip) {
            if key.count < 24 || clip.count > key.count {
                key = clip
            }
        }
        guard key.count >= 8 else {
            askKeyHint = "Paste your API key in the box first, then press Enter. That locks it on this Mac."
            statusText = "Paste your API key, then press Enter to lock it in"
            return
        }
        applyProviderForKey(key)
        persistAskPrefs()
        askCheckingKey = true
        askKeyHint = "Testing this key — one short question to the model…"
        statusText = "Testing this key…"
        Task { await finishLockAskKey(key) }
    }

    private func finishLockAskKey(_ key: String) async {
        let settings = AskService.Settings(
            provider: askProvider,
            model: askModel,
            baseURL: askBaseURL,
            apiKey: key
        )
        let result = await askService.testKey(settings)
        askCheckingKey = false
        if !result.passed {
            askKeyTestPassed = false
            askKeyTestNote = result.message
            askKeyHint = askHasKey
                ? result.message + " The key already on this Mac was left unchanged."
                : result.message
            statusText = "Key test failed"
            return
        }
        AskSecrets.save(key)
        askKeyDraft = ""
        askHasKey = true
        refreshKeyMeta(key)
        askKeyTestPassed = true
        askKeyTestNote = result.message
        UserDefaults.standard.set(true, forKey: "askKeyTestPassed")
        UserDefaults.standard.set(result.message, forKey: "askKeyTestNote")
        askKeyHint = ""
        statusText = result.message
    }

    func testLockedKey() {
        let key = AskSecrets.load()
        guard !key.isEmpty else {
            askKeyHint = "Paste your API key in the box first, then press Enter."
            return
        }
        applyProviderForKey(key)
        persistAskPrefs()
        askCheckingKey = true
        askKeyHint = "Testing this key — one short question to the model…"
        statusText = "Testing this key…"
        Task { await finishLockAskKey(key) }
    }

    func applyProviderForKey(_ key: String) {
        switch AskService.keyKind(key) {
        case .xai:
            askProvider = "xai"
            askBaseURL = "https://api.x.ai/v1"
            if AskModels.list(for: "xai").allSatisfy({ $0.id != askModel }) {
                askModel = AskModels.defaultID(for: "xai")
            }
        case .openai:
            askProvider = "openai"
            askBaseURL = "https://api.openai.com/v1"
            if AskModels.list(for: "openai").allSatisfy({ $0.id != askModel }) {
                askModel = AskModels.defaultID(for: "openai")
            }
        default:
            break
        }
    }

    private func refreshKeyMeta(_ key: String) {
        askKeyKind = AskService.keyKind(key).rawValue
        askKeyTail = AskService.keyTail(key)
    }

    /// Clipboard fallback when SecureField paste has not yet reached the SwiftUI binding.
    private static func isPlausibleClipboardKey(_ value: String) -> Bool {
        let value = AskService.normalizeKey(value)
        guard value.count >= 8, value.count <= 512 else { return false }
        if value.contains(where: { $0.isNewline || $0.isWhitespace }) { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.+/=:"))
        if value.unicodeScalars.contains(where: { !allowed.contains($0) }) { return false }
        let kind = AskService.keyKind(value)
        if kind == .xai || kind == .openai { return true }
        return value.count >= 20
    }

    private func persistAskPrefs() {
        UserDefaults.standard.set(askProvider, forKey: "askProvider")
        UserDefaults.standard.set(askModel, forKey: "askModel")
        UserDefaults.standard.set(askBaseURL, forKey: "askBaseURL")
        UserDefaults.standard.set(askWebFallback, forKey: "askWebFallback")
        UserDefaults.standard.set(filePlace, forKey: "filePlace")
        UserDefaults.standard.set(customFolderPath, forKey: "customFolder")
        UserDefaults.standard.set(ocrEnabled, forKey: "ocrEnabled")
        UserDefaults.standard.set(aiChaptersEnabled, forKey: "aiChaptersEnabled")
    }

    func clearAskKey() {
        askKeyDraft = ""
        askKeyHint = ""
        AskSecrets.delete()
        askHasKey = false
        askKeyTail = ""
        askKeyKind = ""
        askKeyTestPassed = false
        askKeyTestNote = ""
        UserDefaults.standard.set(false, forKey: "askKeyTestPassed")
        UserDefaults.standard.set("", forKey: "askKeyTestNote")
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
            let markdown: String
            if let item = library.first(where: { $0.id == selectedLibraryID }) {
                markdown = (try? String(contentsOf: URL(fileURLWithPath: item.markdownPath), encoding: .utf8))
                    ?? previewMarkdown
            } else {
                markdown = previewMarkdown
            }
            let excerpt = AskService.excerpt(
                markdown: markdown,
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

        let graphic = allowed.filter { url in
            guard url.pathExtension.lowercased() == "pdf", ocrEnabled else { return false }
            let p = OcrService.profile(url)
            return p.needsOCR || p.looksGraphic
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
            var scan = false
            var graphic = false
            if ocrEnabled && url.pathExtension.lowercased() == "pdf" {
                let p = OcrService.profile(url)
                scan = p.needsOCR
                graphic = p.looksGraphic
                if scan { scanCount += 1 }
            }
            jobs.append(ConvertJob(
                id: UUID(),
                sourceURL: url,
                outputURL: nil,
                status: .queued,
                detail: scan
                    ? "Scan — layout OCR first, so this takes a little longer"
                    : url.path,
                startedAt: nil,
                needsOCR: scan,
                looksGraphic: graphic
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
        quietWatch()
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
        quietWatch(12)
        statusText = jobs.contains(where: { $0.status == .failed }) ? "Finished with errors" : "Done"
    }

    private func convertOnePass() async {
        for index in jobs.indices where jobs[index].status == .queued || jobs[index].status == .failed {
            let original = jobs[index].sourceURL
            let jobID = jobs[index].id
            let scan = jobs[index].needsOCR
            let graphic = jobs[index].looksGraphic
            jobs[index].status = .running
            jobs[index].startedAt = Date()
            statusText = "Converting \(original.lastPathComponent)…"
            let output = outputURL(for: original)
            do {
                quietWatch()
                var input = original
                var usedOCR = false
                let isPDF = original.pathExtension.lowercased() == "pdf"
                let layoutFirst = ocrEnabled && isPDF && (scan || graphic)
                if layoutFirst {
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
                    if await OcrService.layoutMarkdown(
                        from: original,
                        to: output,
                        ocr: scan,
                        onStatus: onOCR
                    ) {
                        UserDefaults.standard.set(true, forKey: "doclingReady")
                        let pictures = await PdfFigures.embed(
                            markdownURL: output,
                            sourcePDF: original,
                            onStatus: onOCR
                        )
                        let bookmarks = await loadBookmarks(original)
                        let url = await finalizeMarkdown(output, original: original, bookmarks: bookmarks)
                        await finishJob(jobID: jobID, markdown: url, original: original, usedOCR: true, pictures: pictures, bookmarks: bookmarks)
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
                var pictures = 0
                if isPDF {
                    let onFig: @Sendable (String) -> Void = { msg in
                        Task { @MainActor in
                            self.statusText = msg
                            if let i = self.jobs.firstIndex(where: { $0.id == jobID }) {
                                self.jobs[i].detail = msg
                            }
                        }
                    }
                    pictures = await PdfFigures.embed(markdownURL: url, sourcePDF: original, onStatus: onFig)
                    if pictures == 0, usedOCR, OcrService.markdownLooksEmpty(url) {
                        await OcrService.enrichMarkdown(markdownURL: url, sourcePDF: original, onStatus: onFig)
                    }
                }
                let bookmarks = await loadBookmarks(original)
                let final = await finalizeMarkdown(url, original: original, bookmarks: bookmarks)
                await finishJob(
                    jobID: jobID,
                    markdown: final,
                    original: original,
                    usedOCR: usedOCR,
                    pictures: pictures,
                    bookmarks: bookmarks
                )
            } catch {
                if let i = jobs.firstIndex(where: { $0.id == jobID }) {
                    jobs[i].status = .failed
                    jobs[i].detail = error.localizedDescription
                }
            }
        }
    }

    private func loadBookmarks(_ url: URL) async -> [ManualBookmark] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: PdfSidecar.bookmarks(from: url))
            }
        }
    }

    private func finalizeMarkdown(_ url: URL, original: URL, bookmarks: [ManualBookmark]) async -> URL {
        if !bookmarks.isEmpty {
            let outline = PdfSidecar.outlineMarkdown(bookmarks)
            await Task.detached {
                guard var text = try? String(contentsOf: url, encoding: .utf8) else { return }
                if !text.contains("## Outline") {
                    text = outline + text
                    try? text.write(to: url, atomically: true, encoding: .utf8)
                }
            }.value
        }
        return await maybeAddAIChapters(markdownURL: url, hasOutline: !bookmarks.isEmpty)
    }

    private func finishJob(
        jobID: UUID,
        markdown: URL,
        original: URL,
        usedOCR: Bool,
        pictures: Int,
        bookmarks: [ManualBookmark]
    ) async {
        quietWatch()
        if let i = jobs.firstIndex(where: { $0.id == jobID }) {
            jobs[i].status = .done
            jobs[i].outputURL = markdown
            jobs[i].pictureCount = pictures
            var bits: [String] = []
            if usedOCR { bits.append("Layout OCR") }
            if pictures > 0 { bits.append("\(pictures) pictures") }
            if !bookmarks.isEmpty { bits.append("\(bookmarks.count) bookmarks") }
            bits.append(markdown.lastPathComponent)
            jobs[i].detail = bits.joined(separator: " · ")
        }
        addToLibrary(source: original, markdown: markdown, bookmarks: bookmarks)
    }

    private func maybeAddAIChapters(markdownURL: URL, hasOutline: Bool) async -> URL {
        guard aiChaptersEnabled, askHasKey, !hasOutline else { return markdownURL }
        let size = (try? markdownURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0, size < 80_000 else { return markdownURL }
        guard let text = try? String(contentsOf: markdownURL, encoding: .utf8) else { return markdownURL }
        let headings = text.split(separator: "\n", omittingEmptySubsequences: false).compactMap {
            PdfSidecar.headingText(String($0))
        }.filter { $0.caseInsensitiveCompare("Outline") != .orderedSame }
        guard headings.count < 5 else { return markdownURL }
        statusText = "Adding chapters with AI…"
        do {
            let filled = try await askService.inferChapters(
                markdown: text,
                settings: AskService.Settings(
                    provider: askProvider,
                    model: askModel,
                    baseURL: askBaseURL,
                    apiKey: AskSecrets.load()
                )
            )
            if !filled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try filled.write(to: markdownURL, atomically: true, encoding: .utf8)
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
        defer {
            installingEngine = false
            refreshOCRTools()
        }
        do {
            lastUpgradeLog = try await OcrService.installViaHomebrew()
            refreshOCRTools()
            statusText = ocrmypdfPath == nil
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
        defer {
            installingEngine = false
            refreshOCRTools()
        }
        do {
            lastUpgradeLog = try await OcrService.installDocling()
            refreshOCRTools()
            statusText = doclingPath == nil ? "Docling install finished" : "Docling ready"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Docling install failed"
        }
    }

    func selectLibrary(_ item: LibraryItem, show: Bool = true) {
        selectedLibraryID = item.id
        previewNeedsLoad = false
        if show {
            selectedTool = .library
            showSettings = false
            showHelp = false
        }
        scrollToLine = nil
        previewGen += 1
        let gen = previewGen
        previewMarkdown = "Loading…"
        previewLines = ["Loading…"]
        previewHeadings = []
        previewSections = [PreviewSection(id: 0, lines: ["Loading…"])]
        previewBaseURL = URL(fileURLWithPath: item.markdownPath).deletingLastPathComponent()
        let path = item.markdownPath
        Task.detached {
            let pack = AppModel.buildPreview(path: path)
            await MainActor.run {
                guard gen == self.previewGen else { return }
                self.previewMarkdown = pack.text
                self.previewLines = pack.lines
                self.previewHeadings = pack.headings
                self.previewSections = pack.sections
                self.previewBaseURL = pack.base
            }
        }
    }

    nonisolated static func buildPreview(path: String) -> PreviewPack {
        let url = URL(fileURLWithPath: path)
        let base = url.deletingLastPathComponent()
        guard let data = try? Data(contentsOf: url),
              var text = String(data: data, encoding: .utf8) else {
            let missing = "_File missing on disk._"
            return PreviewPack(
                text: missing,
                lines: [missing],
                headings: [],
                sections: [PreviewSection(id: 0, lines: [missing])],
                base: base
            )
        }
        let cap = 120_000
        if text.count > cap {
            let idx = text.index(text.startIndex, offsetBy: cap)
            var cut = String(text[..<idx])
            if let nl = cut.lastIndex(of: "\n") { cut = String(cut[..<nl]) }
            text = cut + "\n\n_Preview shows the start of this large file. Open it in Finder for the rest._\n"
        }
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var imageCount = 0
        var droppedImages = false
        var lines: [String] = []
        lines.reserveCapacity(min(rawLines.count, 8_000))
        for line in rawLines {
            if isPreviewImageLine(line) {
                imageCount += 1
                if imageCount > 18 {
                    droppedImages = true
                    continue
                }
            }
            lines.append(line)
            if lines.count >= 4_500 { break }
        }
        if droppedImages {
            lines.append("_Further pictures are in the figures folder next to this file. Open it in Finder to see them all._")
        }
        var headings: [ManualBookmark] = []
        var used = Set<String>()
        for (i, line) in lines.enumerated() {
            guard let title = PdfSidecar.headingText(line) else { continue }
            guard title.caseInsensitiveCompare("Outline") != .orderedSame else { continue }
            var key = title.lowercased()
            if used.contains(key) { key += "-\(headings.count)" }
            used.insert(key)
            let n = line.prefix(while: { $0 == "#" }).count
            headings.append(ManualBookmark(title: title, level: max(1, min(Int(n), 3)), pageIndex: nil, lineIndex: i))
        }
        let chunk = 28
        var sections: [PreviewSection] = []
        var i = 0
        while i < lines.count {
            let end = min(i + chunk, lines.count)
            sections.append(PreviewSection(id: i, lines: Array(lines[i..<end])))
            i = end
        }
        if sections.isEmpty {
            sections = [PreviewSection(id: 0, lines: ["Select a converted file."])]
        }
        return PreviewPack(text: text, lines: lines, headings: headings, sections: sections, base: base)
    }

    nonisolated private static func isPreviewImageLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("![") && t.contains("](")
    }

    func jumpToBookmark(_ bookmark: ManualBookmark) {
        askChapter = bookmark.title
        let lines = previewLines.isEmpty
            ? previewMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            : previewLines
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

    private func quietWatch(_ seconds: TimeInterval = 4) {
        ignoreWatchUntil = Date().addingTimeInterval(seconds)
    }

    private func fileDidChange(_ path: String) {
        if isBusy { return }
        if Date() < ignoreWatchUntil { return }
        watchDebounce?.cancel()
        watchDebounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            if self.isBusy || Date() < self.ignoreWatchUntil { return }
            if self.library.contains(where: { $0.sourcePath == path }) {
                self.fileNotice = "Original file changed on disk"
                return
            }
            if let item = self.library.first(where: { $0.markdownPath == path }) {
                self.fileNotice = "Updated from Finder"
                if item.id == self.selectedLibraryID {
                    self.selectLibrary(item, show: false)
                }
            }
        }
    }

    private func addToLibrary(source: URL, markdown: URL, bookmarks: [ManualBookmark]) {
        quietWatch(12)
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
        selectedLibraryID = item.id
        // Do not parse a huge Markdown on the main thread the instant convert
        // finishes — that freeze looked like the app dying after "Done".
        if selectedTool == .library {
            selectLibrary(item, show: false)
        } else {
            previewNeedsLoad = true
        }
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
