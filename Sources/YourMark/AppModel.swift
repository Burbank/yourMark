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
    var statusText = "Ready" {
        didSet { considerToast(statusText) }
    }
    var toastText = ""
    var toastVisible = false
    private var toastGen = 0
    var appearance: String = UserDefaults.standard.string(forKey: "appearance") ?? "system"
    var errorMessage: String?
    var showHelp = false
    var showSettings = false
    var jobs: [ConvertJob] = []
    var library: [LibraryItem] = []
    var selectedLibraryID: UUID?
    var previewMarkdown: String = ""
    var previewLines: [PreviewLine] = []
    var previewHeadings: [ManualBookmark] = []
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

    /// Same tree as the Bookmarks column: PDF outline when present, else Markdown headings.
    var documentOutline: [ManualBookmark] {
        if let item = library.first(where: { $0.id == selectedLibraryID }), !item.bookmarks.isEmpty {
            return item.bookmarks
        }
        return previewHeadings
    }

    var askChapterChoices: [(title: String, level: Int)] {
        var seen = Set<String>()
        var out: [(String, Int)] = []
        for mark in documentOutline {
            let title = mark.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let key = title.lowercased()
            if key == "outline" || key == "entire file" { continue }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append((title, max(1, min(mark.level, 3))))
        }
        return out
    }
    var askAnswer = ""
    var askOpenAnswer = ""
    var askBusy = false
    var askError = ""
    var askWebFallback = UserDefaults.standard.bool(forKey: "askWebFallback")
    var filePlace: String = UserDefaults.standard.string(forKey: "filePlace") ?? "beside"
    var customFolderPath: String = UserDefaults.standard.string(forKey: "customFolder") ?? ""
    var appUpdateTag: String?
    var appUpdateURL: URL?
    var draggingFiles = false
    var ocrEnabled = UserDefaults.standard.object(forKey: "ocrEnabled") as? Bool ?? true
    var ocrScanner: String = UserDefaults.standard.string(forKey: "ocrScanner")
        ?? (Distribution.isAppStore ? "livetext" : "docling")
    var ocrScannerHint = ""
    var showInstallSheet = false
    var showOCRSheet = false
    var showMarkEditSheet = false
    var showCrashSheet = false
    var pendingCrash: CrashReport?
    var offerCrashReports = UserDefaults.standard.object(forKey: "offerCrashReports") as? Bool ?? true
    var settingsFocus: String = ""
    var showDoclingPrompt = false
    var pendingGraphics: [URL] = []
    var aiChaptersEnabled = UserDefaults.standard.object(forKey: "aiChaptersEnabled") as? Bool ?? false
    var askReadPictures = UserDefaults.standard.object(forKey: "askReadPictures") as? Bool ?? false
    var stripChrome = UserDefaults.standard.object(forKey: "stripChrome") as? Bool ?? true
    var previewFontName = UserDefaults.standard.string(forKey: "previewFontName") ?? "rounded"
    var translateFrom = UserDefaults.standard.string(forKey: "translateFrom") ?? "auto"
    var translateTo = UserDefaults.standard.string(forKey: "translateTo") ?? TranslateLang.deviceTo
    var translateEngine = UserDefaults.standard.string(forKey: "translateEngine") ?? "ask"
    var translateLayout = UserDefaults.standard.string(forKey: "translateLayout") ?? "below"
    var translateSaveMode = UserDefaults.standard.string(forKey: "translateSaveMode") ?? "keep"
    var translateMarkdown: String?
    var translateBusy = false
    var translateError = ""
    var googleKeyDraft = ""
    var googleHasKey = false
    var googleKeyHint = ""
    var googleCheckingKey = false
    var googleKeyTestPassed = false
    var googleKeyTestNote = ""
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
    private var lastStatusAt = Date.distantPast
    private var previewBackup: (lines: [PreviewLine], headings: [ManualBookmark])?

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
        // Do not decrypt the Keychain item at launch — that dialog fired on
        // every new unsigned build. Presence is remembered in UserDefaults.
        askHasKey = UserDefaults.standard.bool(forKey: "askHasKey")
            || UserDefaults.standard.bool(forKey: "askKeyTestPassed")
        askKeyDraft = ""
        askKeyKind = UserDefaults.standard.string(forKey: "askKeyKind") ?? ""
        askKeyTail = UserDefaults.standard.string(forKey: "askKeyTail") ?? ""
        askKeyTestPassed = askHasKey && UserDefaults.standard.bool(forKey: "askKeyTestPassed")
        askKeyTestNote = askHasKey ? (UserDefaults.standard.string(forKey: "askKeyTestNote") ?? "") : ""
        googleHasKey = UserDefaults.standard.bool(forKey: "googleHasKey")
            || !TranslateSecrets.load().isEmpty
        googleKeyTestPassed = googleHasKey && UserDefaults.standard.bool(forKey: "googleKeyTestPassed")
        googleKeyTestNote = googleHasKey ? (UserDefaults.standard.string(forKey: "googleKeyTestNote") ?? "") : ""
        if UserDefaults.standard.string(forKey: "translateEngine") == nil {
            translateEngine = askHasKey ? "ask" : "google"
        }
        watcher.onChange = { path in
            DispatchQueue.main.async { [weak self] in
                self?.fileDidChange(path)
            }
        }
        if Distribution.isAppStore {
            if UserDefaults.standard.object(forKey: "masFilePlaceSet") == nil {
                filePlace = "library"
                UserDefaults.standard.set("library", forKey: "filePlace")
                UserDefaults.standard.set(true, forKey: "masFilePlaceSet")
            }
            if let restored = FolderAccess.restoreCustomFolder() {
                customFolderPath = restored.path
            }
        }
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
        if Distribution.isAppStore {
            UserDefaults.standard.set(true, forKey: "sawInstallSheet")
            UserDefaults.standard.set(true, forKey: "sawOCRSheet")
            let status = await service.refreshStatus()
            enginePath = status.path
            engineVersion = status.path == nil ? "missing from this copy" : status.version
            statusText = status.path == nil ? "Converter missing from this copy" : "Ready"
            maybeOfferMarkEdit()
            Task { await fillMissingBookmarks() }
            maybeOfferCrashReport()
            startWatching()
            return
        }
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
        } else {
            maybeOfferMarkEdit()
        }
        if status.path == nil, !installingEngine {
            statusText = "Installing Microsoft MarkItDown…"
            await installEngine()
        } else if status.path != nil {
            statusText = "MarkItDown \(status.version)"
            Task { await checkUpdates(force: false) }
        }
        refreshOCRTools()
        Task { await fillMissingBookmarks() }
        maybeOfferCrashReport()
        startWatching()
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
        maybeOfferMarkEdit()
    }

    func acceptOCRInstall() async {
        UserDefaults.standard.set(true, forKey: "sawOCRSheet")
        showOCRSheet = false
        await installDocling()
        UserDefaults.standard.set(true, forKey: "doclingReady")
        showSettings = true
        settingsFocus = "ocr"
        maybeOfferMarkEdit()
    }

    func maybeOfferMarkEdit() {
        if UserDefaults.standard.bool(forKey: "sawMarkEditSheet") {
            maybeOfferCrashReport()
            return
        }
        if Self.markEditAppURL() != nil {
            UserDefaults.standard.set(true, forKey: "sawMarkEditSheet")
            maybeOfferCrashReport()
            return
        }
        showMarkEditSheet = true
    }

    func skipMarkEditSheet() {
        UserDefaults.standard.set(true, forKey: "sawMarkEditSheet")
        showMarkEditSheet = false
        maybeOfferCrashReport()
    }

    func acceptMarkEditRecommend() {
        UserDefaults.standard.set(true, forKey: "sawMarkEditSheet")
        showMarkEditSheet = false
        openMarkEditDownload()
        maybeOfferCrashReport()
    }

    func openMarkEditDownload() {
        if let url = URL(string: "https://github.com/MarkEdit-app/MarkEdit/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    func maybeOfferCrashReport() {
        guard offerCrashReports else { return }
        if showInstallSheet || showOCRSheet || showMarkEditSheet { return }
        if showCrashSheet { return }
        pendingCrash = CrashReports.latestUnsent()
        showCrashSheet = pendingCrash != nil
    }

    func copyPendingCrash() {
        guard let report = pendingCrash else {
            showCrashSheet = false
            return
        }
        CrashReports.copyLog(report)
        CrashReports.markSent(report.id)
        pendingCrash = nil
        showCrashSheet = false
        statusText = "Crash report copied — paste it in a message"
    }

    func sendPendingCrash() {
        guard let report = pendingCrash else {
            showCrashSheet = false
            return
        }
        CrashReports.copyLog(report)
        if let url = CrashReports.githubURL(for: report) {
            NSWorkspace.shared.open(url)
        }
        CrashReports.markSent(report.id)
        pendingCrash = nil
        showCrashSheet = false
    }

    func skipCrashSheet() {
        if let id = pendingCrash?.id {
            CrashReports.markSent(id)
        }
        pendingCrash = nil
        showCrashSheet = false
    }

    func neverOfferCrashes() {
        offerCrashReports = false
        UserDefaults.standard.set(false, forKey: "offerCrashReports")
        skipCrashSheet()
    }

    func setOfferCrashReports(_ on: Bool) {
        offerCrashReports = on
        UserDefaults.standard.set(on, forKey: "offerCrashReports")
    }

    func sendLastCrash() {
        guard let report = CrashReports.latestAny() else { return }
        CrashReports.copyLog(report)
        CrashReports.markSent(report.id)
        statusText = "Crash report copied — paste it in a message"
    }

    func setPreviewFont(_ name: String) {
        previewFontName = name
        UserDefaults.standard.set(name, forKey: "previewFontName")
    }

    func readerFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch previewFontName {
        case "system":
            return .system(size: size, weight: weight)
        case "rounded", "":
            return .system(size: size, weight: weight, design: .rounded)
        default:
            return .custom(previewFontName, size: size).weight(weight)
        }
    }

    private static let cachedFontFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    static var installedFontFamilies: [String] { cachedFontFamilies }

    func installEngine() async {
        guard Distribution.allowsEngineInstall else {
            statusText = "This App Store build uses \(Distribution.converterLabel)"
            return
        }
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

    /// GitHub disk may download Docling. App Store copy may not run downloaded code.
    var prefersDocling: Bool {
        ocrEnabled && ocrScanner == "docling" && Distribution.allowsEngineInstall
    }

    func setOcrScanner(_ value: String) {
        if value == "docling", Distribution.isAppStore {
            ocrScanner = "livetext"
            ocrScannerHint = "This App Store copy cannot download the layout scanner (a large extra). It stays on Apple Live Text. The disk from GitHub can install the better scanner."
            UserDefaults.standard.set("livetext", forKey: "ocrScanner")
            return
        }
        ocrScanner = value
        ocrScannerHint = ""
        UserDefaults.standard.set(value, forKey: "ocrScanner")
        if value == "docling", doclingPath == nil, Distribution.allowsEngineInstall {
            statusText = "Get the layout scanner below — then scans use tables and columns"
        }
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
                previewBaseURL = nil
                previewBackup = nil
                askChapter = "Entire file"
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

    That is why it works so well with AI. A model can read a chapter and quote the words that are there. If that chapter does not have the answer, it can say so — instead of guessing at a scan. You can paste one heading into Grok or ChatGPT, keep notes in Obsidian, or search a whole course. Tables stay tables. Headings stay an outline.

    Keep the original PDF. Markdown is the working copy.

    ## Convert

    Drop a PDF **anywhere** on yourMark — Library, Bookmarks, Convert, the header. Conversion starts at once if nothing else is running. Graphic PDFs ask to install Docling first.

    Settings → **Automatically add chapters with AI** (off unless you tick it) uses your Ask key to insert headings when the file has no outline.

    If the PDF is a **scan** (no text layer), yourMark uses IBM **Docling** for layout — tables, columns, figures. That takes a little longer than a normal convert. Microsoft MarkItDown still handles ordinary PDFs. Pictures in a digital PDF are pulled into a `figures` folder inside a little folder named after the file. If Docling is missing, we fall back to OCRmyPDF / Apple Live Text.

    Settings → **Remove headers and footers** (on by default) drops the repeating page title, page number, date, and header logos.

    ## Picture links

    Pictures are files in the figures folder. The Markdown only points at them. In the reader, rest the pointer on a blue link for a small preview. Click the link: Finder opens with that picture selected.

    ## Bookmarks

    The Bookmarks pane is the PDF outline when the file has one, otherwise headings. Click to jump, like Preview.

    ## Tables and figures

    Real tables become Markdown tables. Pictures from the PDF sit in a figures folder inside the convert folder, linked in page order. Scans get OCR first.

    ## Library cards

    Swipe a card left to delete, or right-click for Open, Show in Finder, and Delete. **Show in Finder** opens the folder with the new Markdown and pictures, not the original PDF. If you change that Markdown, the library updates. Drag to rearrange.

    ## Ask chapter

    Open a file, pick a heading, and ask. The answer comes only from that chapter. With your own key (Settings) you can also ask the entire file.

    If the chapter does not provide an answer, **Search the web** opens a browser tab with the question, the chapter, and that sentence.

    ## Settings

    Pick the model, paste your API key, then press **Enter** to lock it in, and choose where converted files go. **Remove headers and footers** sits at the top of Settings.

    - **Next to the original PDF** — a little folder with the Markdown and pictures together

    - **Next to the original PDF**
    - **yourMark library folder**
    - **Choose a folder** — opens Finder

    The key stays on this Mac. It is sent only when you ask a question, to the provider you pick.

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
        UserDefaults.standard.set(askHasKey, forKey: "askHasKey")
        UserDefaults.standard.set(askKeyKind, forKey: "askKeyKind")
        UserDefaults.standard.set(askKeyTail, forKey: "askKeyTail")
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
        UserDefaults.standard.set(ocrScanner, forKey: "ocrScanner")
        UserDefaults.standard.set(aiChaptersEnabled, forKey: "aiChaptersEnabled")
        UserDefaults.standard.set(askReadPictures, forKey: "askReadPictures")
        UserDefaults.standard.set(stripChrome, forKey: "stripChrome")
        UserDefaults.standard.set(previewFontName, forKey: "previewFontName")
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
        UserDefaults.standard.set(false, forKey: "askHasKey")
        UserDefaults.standard.set("", forKey: "askKeyKind")
        UserDefaults.standard.set("", forKey: "askKeyTail")
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
            let mark = documentOutline.first {
                $0.title.caseInsensitiveCompare(askChapter) == .orderedSame
            }
            let excerpt = AskService.excerpt(
                markdown: markdown,
                heading: askChapter,
                startLine: mark?.lineIndex
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

    func persistTranslateSettings() {
        UserDefaults.standard.set(translateFrom, forKey: "translateFrom")
        UserDefaults.standard.set(translateTo, forKey: "translateTo")
        UserDefaults.standard.set(translateEngine, forKey: "translateEngine")
        UserDefaults.standard.set(translateLayout, forKey: "translateLayout")
        UserDefaults.standard.set(translateSaveMode, forKey: "translateSaveMode")
    }

    @discardableResult
    private func setStatus(_ text: String, important: Bool = false) -> Bool {
        guard text != statusText else { return false }
        if !important, Date().timeIntervalSince(lastStatusAt) < 0.4 { return false }
        lastStatusAt = Date()
        statusText = text
        return true
    }

    private func considerToast(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Ready" else { return }
        if trimmed.hasSuffix("…") || trimmed.hasSuffix("...") { return }
        showToast(trimmed)
    }

    private func showToast(_ text: String) {
        toastText = text
        toastVisible = true
        toastGen += 1
        let gen = toastGen
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard gen == toastGen else { return }
            toastVisible = false
        }
    }

    var translateReadyHint: String {
        if translateEngine == "google" {
            return googleHasKey
                ? "This chapter will be sent to Google Translate"
                : "Add a Google Translate key in Settings, or switch Translate to your Ask key"
        }
        return askHasKey
            ? "This chapter will be sent to your Ask model"
            : "Add an Ask key in Settings, or switch Translate to Google"
    }

    func lockGoogleTranslateKey() {
        let draft = AskService.normalizeKey(googleKeyDraft)
        guard !draft.isEmpty else {
            googleKeyHint = "Paste a Google Translate API key first."
            return
        }
        googleCheckingKey = true
        googleKeyHint = ""
        Task {
            let result = await TranslateService.testGoogleKey(draft)
            googleCheckingKey = false
            if result.passed {
                TranslateSecrets.save(draft)
                googleHasKey = true
                googleKeyDraft = ""
                googleKeyTestPassed = true
                googleKeyTestNote = result.message
                UserDefaults.standard.set(true, forKey: "googleHasKey")
                UserDefaults.standard.set(true, forKey: "googleKeyTestPassed")
                UserDefaults.standard.set(result.message, forKey: "googleKeyTestNote")
                statusText = "Google Translate key locked in"
            } else {
                googleKeyHint = result.message
            }
        }
    }

    func clearGoogleTranslateKey() {
        TranslateSecrets.delete()
        googleHasKey = false
        googleKeyDraft = ""
        googleKeyHint = ""
        googleKeyTestPassed = false
        googleKeyTestNote = ""
        UserDefaults.standard.set(false, forKey: "googleHasKey")
        UserDefaults.standard.set(false, forKey: "googleKeyTestPassed")
        UserDefaults.standard.set("", forKey: "googleKeyTestNote")
        statusText = "Google Translate key cleared"
    }

    func runTranslate(entireFile: Bool) async {
        guard let item = library.first(where: { $0.id == selectedLibraryID }) else {
            translateError = "Open a file in Library first."
            return
        }
        if translateEngine == "google", !googleHasKey {
            translateError = "Add a Google Translate key in Settings, or switch Translate to your Ask key."
            statusText = translateError
            return
        }
        if translateEngine != "google", !askHasKey {
            translateError = "Add an Ask key in Settings, or switch Translate to Google."
            statusText = translateError
            return
        }
        if translateTo == "auto" || translateTo.isEmpty {
            translateError = "Pick a language to translate to."
            return
        }
        translateBusy = true
        translateError = ""
        statusText = entireFile
            ? "Translating the file…"
            : "Translating this chapter…"
        defer { translateBusy = false }
        let disk = (try? String(contentsOf: URL(fileURLWithPath: item.markdownPath), encoding: .utf8))
            ?? previewMarkdown
        let heading = entireFile ? "Entire file" : askChapter
        let mark = entireFile ? nil : documentOutline.first {
            $0.title.caseInsensitiveCompare(heading) == .orderedSame
        }
        let excerpt = AskService.excerpt(
            markdown: disk,
            heading: heading,
            startLine: mark?.lineIndex,
            max: 40_000
        )
        let askSettings = AskService.Settings(
            provider: askProvider,
            model: askModel,
            baseURL: askBaseURL,
            apiKey: AskSecrets.load()
        )
        do {
            let result = try await TranslateService.translate(
                markdown: excerpt,
                from: translateFrom,
                to: translateTo,
                mode: translateLayout,
                engine: translateEngine,
                ask: askSettings,
                googleKey: TranslateSecrets.load()
            )
            translateMarkdown = result
            applyDisplayLines(result)
            if translateSaveMode == "copy" {
                saveTranslationCopy()
            } else {
                statusText = "Translation is in the reader — Save a copy when you want it on disk"
            }
        } catch {
            translateError = error.localizedDescription
            statusText = translateError
        }
    }

    func clearTranslation() {
        translateMarkdown = nil
        translateError = ""
        if let backup = previewBackup {
            previewLines = backup.lines
            previewHeadings = backup.headings
            setStatus(translateReadyHint, important: true)
            return
        }
        guard let item = library.first(where: { $0.id == selectedLibraryID }) else {
            setStatus(translateReadyHint, important: true)
            return
        }
        let path = item.markdownPath
        let scanHeadings = item.bookmarks.isEmpty
        Task.detached {
            let pack = AppModel.buildPreview(path: path, scanHeadings: scanHeadings)
            await MainActor.run {
                self.previewMarkdown = pack.text
                self.previewLines = pack.lines
                self.previewHeadings = pack.headings
                self.previewBaseURL = pack.base
                self.previewBackup = (pack.lines, pack.headings)
                self.setStatus(self.translateReadyHint, important: true)
            }
        }
    }

    func saveTranslationCopy() {
        guard let text = translateMarkdown,
              let item = library.first(where: { $0.id == selectedLibraryID })
        else { return }
        let original = URL(fileURLWithPath: item.markdownPath)
        let folder = original.deletingLastPathComponent()
        let stem = original.deletingPathExtension().lastPathComponent
        let lang = translateTo
        var dest = folder.appendingPathComponent("\(stem).\(lang).md")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(stem).\(lang)-\(n).md")
            n += 1
        }
        quietWatch(8)
        do {
            try text.write(to: dest, atomically: true, encoding: .utf8)
        } catch {
            translateError = error.localizedDescription
            statusText = "Could not save the translation copy"
            return
        }
        let source = item.sourcePath.isEmpty
            ? original
            : URL(fileURLWithPath: item.sourcePath)
        _ = insertLibraryItem(
            source: source,
            markdown: dest,
            bookmarks: item.bookmarks,
            title: "\(item.title) · \(TranslateLang.label(for: lang))"
        )
        statusText = "Saved a copy — the original Markdown is unchanged"
    }

    private func applyDisplayLines(_ text: String) {
        previewLines = Self.readerLines(from: text)
    }

    func openIncoming(_ urls: [URL]) {
        let allowed = urls.flatMap(IncomingURLs.files(from:)).filter { ConvertibleKind.allows($0) }
        guard !allowed.isEmpty else { return }
        for url in allowed { _ = url.startAccessingSecurityScopedResource() }
        showSettings = false
        showHelp = false
        selectedTool = .convert
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        // Classify scans off the first frame — PDFKit here used to crash launch-by-drop.
        Task { await classifyAndEnqueue(allowed) }
    }

    private func classifyAndEnqueue(_ allowed: [URL]) async {
        let ocrOn = ocrEnabled
        let scans = await PdfWork.runAsync { () -> [String] in
            allowed.filter { url in
                guard url.pathExtension.lowercased() == "pdf", ocrOn else { return false }
                return OcrService.profile(url).needsOCR
            }.map(\.path)
        }
        let scanSet = Set(scans)
        let scanURLs = allowed.filter { scanSet.contains($0.path) }
        let rest = allowed.filter { !scanSet.contains($0.path) }
        if !rest.isEmpty { enqueue(rest, scans: []) }

        let doclingReady = prefersDocling && (
            OcrService.doclingPath() != nil
            || UserDefaults.standard.bool(forKey: "doclingReady")
        )
        if !scanURLs.isEmpty, prefersDocling, !doclingReady {
            pendingGraphics.append(contentsOf: scanURLs.filter { g in
                !pendingGraphics.contains(where: { $0.path == g.path })
            })
            showDoclingPrompt = true
        } else if !scanURLs.isEmpty {
            enqueue(scanURLs, scans: scanSet)
        }
        await convertQueued()
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
            .pdf, .plainText, .image, .jpeg, .png, .gif, .webP, .tiff,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data,
            UTType(filenameExtension: "xls") ?? .data,
            UTType(filenameExtension: "html") ?? .html,
            UTType(filenameExtension: "epub") ?? .data,
            UTType(filenameExtension: "csv") ?? .commaSeparatedText,
            UTType(filenameExtension: "json") ?? .json,
            UTType(filenameExtension: "xml") ?? .xml,
            UTType(filenameExtension: "msg") ?? .data,
            UTType(filenameExtension: "zip") ?? .zip,
            UTType(filenameExtension: "rtf") ?? .rtf,
            UTType(filenameExtension: "webp") ?? .webP,
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        openIncoming(panel.urls)
    }

    func enqueue(_ urls: [URL], scans: Set<String>? = nil) {
        var scanCount = 0
        for url in urls where ConvertibleKind.allows(url) {
            if jobs.contains(where: { $0.sourceURL == url }) { continue }
            var scan = false
            if ocrEnabled && url.pathExtension.lowercased() == "pdf" {
                if let scans {
                    scan = scans.contains(url.path)
                } else {
                    scan = OcrService.profile(url).needsOCR
                }
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
        quietWatch()
        defer { isBusy = false }

        do {
            _ = try await service.resolveEngine()
        } catch {
            if Distribution.isAppStore {
                statusText = "Converter missing from this copy"
            } else {
                statusText = "Using Apple Live Text until MarkItDown is installed"
            }
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
            jobs[index].status = .running
            jobs[index].startedAt = Date()
            statusText = "Converting \(original.lastPathComponent)…"
            let output = outputURL(for: original)
            do {
                quietWatch()
                var input = original
                var usedOCR = false
                let isPDF = original.pathExtension.lowercased() == "pdf"
                let pythonReady: Bool
                if enginePath != nil {
                    pythonReady = true
                } else {
                    pythonReady = (try? await service.resolveEngine()) != nil
                }
                if !pythonReady {
                    let onNative: @Sendable (String) -> Void = { msg in
                        Task { @MainActor in
                            if self.setStatus(msg), let i = self.jobs.firstIndex(where: { $0.id == jobID }) {
                                self.jobs[i].detail = msg
                            }
                        }
                    }
                    let url = try await NativeConvert.convert(
                        input: original,
                        output: output,
                        ocr: ocrEnabled && scan,
                        onStatus: onNative
                    )
                    var pictures = 0
                    if isPDF {
                        await tidyPDFMarkdown(url, pdf: original)
                        let bookmarks = await loadBookmarks(original)
                        let (final, located) = await finalizeMarkdown(url, original: original, bookmarks: bookmarks)
                        pictures = await PdfFigures.embed(
                            markdownURL: final,
                            sourcePDF: original,
                            stripChrome: stripChrome,
                            onStatus: onNative
                        )
                        await finishJob(
                            jobID: jobID,
                            markdown: final,
                            original: original,
                            usedOCR: scan,
                            pictures: pictures,
                            bookmarks: located
                        )
                    } else {
                        let bookmarks = await loadBookmarks(original)
                        let (final, located) = await finalizeMarkdown(url, original: original, bookmarks: bookmarks)
                        await finishJob(
                            jobID: jobID,
                            markdown: final,
                            original: original,
                            usedOCR: false,
                            pictures: 0,
                            bookmarks: located
                        )
                    }
                    continue
                }
                let layoutFirst = prefersDocling && isPDF && scan
                if layoutFirst {
                    jobs[index].needsOCR = true
                    jobs[index].detail = "Layout OCR first — this takes a little longer"
                    statusText = "Layout OCR first — this takes a little longer · \(original.lastPathComponent)"
                    let onOCR: @Sendable (String) -> Void = { msg in
                        Task { @MainActor in
                            let line = "Layout OCR first — this takes a little longer. \(msg)"
                            if self.setStatus(line), let i = self.jobs.firstIndex(where: { $0.id == jobID }) {
                                self.jobs[i].detail = line
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
                        if let script = Bundle.main.url(forResource: "pdf_enrich", withExtension: "py"),
                           await markdownNeedsEnrich(output) {
                            await service.enrichPDF(markdown: output, pdf: original, script: script)
                        }
                        let bookmarks = await loadBookmarks(original)
                        let (url, located) = await finalizeMarkdown(output, original: original, bookmarks: bookmarks)
                        let pictures = await PdfFigures.materializeEmbedded(markdownURL: url)
                        await finishJob(jobID: jobID, markdown: url, original: original, usedOCR: true, pictures: pictures, bookmarks: located)
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
                let url = try await service.convert(
                    input: input,
                    output: output,
                    script: Bundle.main.url(forResource: "markitdown_convert", withExtension: "py"),
                    llmKey: (askReadPictures && askHasKey) ? AskSecrets.load() : "",
                    llmBase: askBaseURL,
                    llmModel: askModel
                )
                var pictures = 0
                if isPDF {
                    let onFig: @Sendable (String) -> Void = { msg in
                        Task { @MainActor in
                            if self.setStatus(msg), let i = self.jobs.firstIndex(where: { $0.id == jobID }) {
                                self.jobs[i].detail = msg
                            }
                        }
                    }
                    let pages = await PdfWork.runAsync { OcrService.pageCount(of: original) }
                    let thin = OcrService.markdownLooksThin(url, pageCount: max(pages, 1))
                    if ocrEnabled, thin, !usedOCR {
                        // MarkItDown saw no text layer. OCR first, then convert again.
                        jobs[index].needsOCR = true
                        jobs[index].detail = "Scan detected — OCR first, then convert"
                        statusText = "This PDF is a scan (picture of the page). Running OCR…"
                        let onOCR: @Sendable (String) -> Void = { msg in
                            Task { @MainActor in
                                if self.setStatus(msg), let i = self.jobs.firstIndex(where: { $0.id == jobID }) {
                                    self.jobs[i].detail = msg
                                }
                            }
                        }
                        if await OcrService.layoutMarkdown(
                            from: original,
                            to: output,
                            ocr: true,
                            onStatus: onOCR
                        ) {
                            usedOCR = true
                            UserDefaults.standard.set(true, forKey: "doclingReady")
                        } else {
                            let prepared = try await OcrService.searchablePDF(from: original, force: true, onStatus: onOCR)
                            usedOCR = true
                            if prepared.didOCR || prepared.url != original {
                                _ = try await service.convert(
                                    input: prepared.url,
                                    output: output,
                                    script: Bundle.main.url(forResource: "markitdown_convert", withExtension: "py"),
                                    llmKey: "",
                                    llmBase: askBaseURL,
                                    llmModel: askModel
                                )
                            }
                        }
                    }
                    if usedOCR, OcrService.markdownLooksThin(url, pageCount: max(pages, 1)) {
                        await OcrService.enrichMarkdown(markdownURL: url, sourcePDF: original, onStatus: onFig)
                    } else if usedOCR, OcrService.markdownLooksEmpty(url) {
                        await OcrService.enrichMarkdown(markdownURL: url, sourcePDF: original, onStatus: onFig)
                    }
                    statusText = "Cleaning headers and headings…"
                    await tidyPDFMarkdown(url, pdf: original)
                    if await markdownNeedsEnrich(url) {
                        let script = Bundle.main.url(forResource: "pdf_enrich", withExtension: "py")
                        statusText = "Restoring the PDF outline and tables…"
                        await service.enrichPDF(markdown: url, pdf: original, script: script)
                    }
                    let bookmarks = await loadBookmarks(original)
                    let (final, located) = await finalizeMarkdown(url, original: original, bookmarks: bookmarks)
                    _ = await PdfFigures.materializeEmbedded(markdownURL: final)
                    pictures = 0
                    if !usedOCR {
                        pictures = await PdfFigures.embed(
                            markdownURL: final,
                            sourcePDF: original,
                            stripChrome: stripChrome,
                            onStatus: onFig
                        )
                    }
                    await finishJob(
                        jobID: jobID,
                        markdown: final,
                        original: original,
                        usedOCR: usedOCR,
                        pictures: pictures,
                        bookmarks: located
                    )
                    continue
                }
                let bookmarks = await loadBookmarks(original)
                let (final, located) = await finalizeMarkdown(url, original: original, bookmarks: bookmarks)
                await finishJob(
                    jobID: jobID,
                    markdown: final,
                    original: original,
                    usedOCR: usedOCR,
                    pictures: pictures,
                    bookmarks: located
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
        await PdfWork.runAsync {
            let fromPdf = PdfSidecar.bookmarks(from: url)
            if !fromPdf.isEmpty { return fromPdf }
            return PdfSidecar.fontHeadings(from: url)
        }
    }

    private func finalizeMarkdown(_ url: URL, original: URL, bookmarks: [ManualBookmark]) async -> (URL, [ManualBookmark]) {
        let located = await PdfWork.runAsync { () -> [ManualBookmark] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return bookmarks }
            let stitched = PdfSidecar.stitch(bookmarks: bookmarks, markdown: text, pdf: original)
            try? stitched.text.write(to: url, atomically: true, encoding: .utf8)
            PdfSidecar.writeSidecar(stitched.bookmarks, nextTo: url)
            return stitched.bookmarks
        }
        let after = await maybeAddAIChapters(markdownURL: url, hasOutline: !located.isEmpty)
        return (after, located)
    }

    private func tidyPDFMarkdown(_ url: URL, pdf: URL) async {
        let strip = stripChrome
        let text = await Task.detached { try? String(contentsOf: url, encoding: .utf8) }.value
        guard let text else { return }
        let cleaned = await PdfCleanup.tidyAsync(markdown: text, pdf: pdf, stripChrome: strip)
        if cleaned != text {
            await Task.detached { try? cleaned.write(to: url, atomically: true, encoding: .utf8) }.value
        }
    }

    private func markdownNeedsEnrich(_ url: URL) async -> Bool {
        await Task.detached {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return true }
            let hasPages = text.contains("<!-- page 2 -->")
            let tables = text.components(separatedBy: "\n| ").count
            return !(hasPages && tables >= 6)
        }.value
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
        guard Distribution.allowsEngineInstall else { return }
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
        guard Distribution.allowsEngineInstall else { return }
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
        guard Distribution.allowsEngineInstall else { return }
        installingEngine = true
        statusText = "Installing Docling (layout models)… first run downloads extra files"
        defer {
            installingEngine = false
            refreshOCRTools()
        }
        do {
            lastUpgradeLog = try await OcrService.installDocling()
            refreshOCRTools()
            ocrScanner = "docling"
            UserDefaults.standard.set("docling", forKey: "ocrScanner")
            ocrScannerHint = ""
            statusText = doclingPath == nil ? "Layout scanner finished" : "Layout scanner ready"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Docling install failed"
        }
    }

    func selectLibrary(_ item: LibraryItem, show: Bool = true) {
        selectedLibraryID = item.id
        previewNeedsLoad = false
        translateMarkdown = nil
        translateError = ""
        askChapter = "Entire file"
        if show {
            selectedTool = .library
            showSettings = false
            showHelp = false
        }
        scrollToLine = nil
        previewGen += 1
        let gen = previewGen
        previewMarkdown = "Loading…"
        previewLines = [PreviewLine(id: 0, text: "Loading…")]
        previewHeadings = []
        previewBackup = nil
        previewBaseURL = URL(fileURLWithPath: item.markdownPath).deletingLastPathComponent()
        let path = item.markdownPath
        let scanHeadings = item.bookmarks.isEmpty
        Task.detached {
            let pack = AppModel.buildPreview(path: path, scanHeadings: scanHeadings)
            await MainActor.run {
                guard gen == self.previewGen else { return }
                if pack.missing, !self.previewMarkdown.isEmpty, self.previewMarkdown != "Loading…" {
                    return
                }
                self.previewMarkdown = pack.text
                self.previewLines = pack.lines
                self.previewHeadings = pack.headings
                self.previewBaseURL = pack.base
                self.previewBackup = (pack.lines, pack.headings)
            }
        }
    }

    nonisolated static func readerLines(from text: String) -> [PreviewLine] {
        let raw = text.split(separator: "\n", omittingEmptySubsequences: false)
        var out: [PreviewLine] = []
        out.reserveCapacity(min(raw.count, 4_500))
        for (i, line) in raw.enumerated() {
            if i >= 4_500 { break }
            if line.contains("data:image") {
                out.append(PreviewLine(id: i, text: "_A picture is stored as a file in the figures folder (Finder)._"))
            } else {
                out.append(PreviewLine(id: i, text: String(line)))
            }
        }
        return out
    }

    nonisolated static func packFromText(
        _ text: String,
        base: URL,
        missing: Bool = false,
        scanHeadings: Bool = true
    ) -> PreviewPack {
        var text = text
        let cap = 120_000
        if text.count > cap {
            let idx = text.index(text.startIndex, offsetBy: cap)
            var cut = String(text[..<idx])
            if let nl = cut.lastIndex(of: "\n") { cut = String(cut[..<nl]) }
            text = cut + "\n\n_Preview shows the start of this large file. Open it in Finder for the rest._\n"
        }
        let lines = readerLines(from: text)
        var headings: [ManualBookmark] = []
        if scanHeadings {
            var used = Set<String>()
            for (i, row) in lines.enumerated() {
                let probe = row.text.hasPrefix(TranslateService.marker)
                    ? String(row.text.dropFirst(TranslateService.marker.count))
                    : row.text
                guard let title = PdfSidecar.headingText(probe) else { continue }
                guard title.caseInsensitiveCompare("Outline") != .orderedSame else { continue }
                var key = title.lowercased()
                if used.contains(key) { key += "-\(headings.count)" }
                used.insert(key)
                let n = probe.prefix(while: { $0 == "#" }).count
                headings.append(ManualBookmark(title: title, level: max(1, min(Int(n), 3)), pageIndex: nil, lineIndex: i))
            }
        }
        return PreviewPack(text: text, lines: lines, headings: headings, base: base, missing: missing)
    }

    nonisolated static func buildPreview(path: String, scanHeadings: Bool = true) -> PreviewPack {
        let url = URL(fileURLWithPath: path)
        let base = url.deletingLastPathComponent()
        guard let data = try? Data(contentsOf: url), data.count > 8,
              let text = String(data: data, encoding: .utf8) else {
            let missing = "_File missing on disk._"
            return PreviewPack(
                text: missing,
                lines: [PreviewLine(id: 0, text: missing)],
                headings: [],
                base: base,
                missing: true
            )
        }
        return packFromText(text, base: base, scanHeadings: scanHeadings)
    }

    func setAskChapter(_ title: String) {
        askChapter = title
        guard title != "Entire file" else { return }
        if let mark = documentOutline.first(where: {
            $0.title.caseInsensitiveCompare(title) == .orderedSame
        }) {
            jumpToBookmark(mark)
        }
    }

    func jumpToBookmark(_ bookmark: ManualBookmark) {
        askChapter = bookmark.title
        let lines = previewLines.isEmpty
            ? previewMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            : previewLines.map(\.text)
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
        let folder = url.deletingLastPathComponent()
        let figures = folder.appendingPathComponent("figures", isDirectory: true)
        var urls = [url]
        if FileManager.default.fileExists(atPath: figures.path) {
            urls.append(figures)
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openInMarkEdit(_ item: LibraryItem) {
        let file = URL(fileURLWithPath: item.markdownPath)
        guard FileManager.default.fileExists(atPath: file.path) else {
            errorMessage = "That Markdown file is not on disk anymore."
            return
        }
        if let app = Self.markEditAppURL() {
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Install MarkEdit to edit"
        alert.informativeText = "yourMark is a reader. MarkEdit is a free, open-source Mac editor for Markdown.\n\nInstall it, then press Edit again."
        alert.addButton(withTitle: "Get MarkEdit")
        alert.addButton(withTitle: "Not now")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/MarkEdit-app/MarkEdit/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    static func markEditAppURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.cyan.markedit") {
            return url
        }
        let path = "/Applications/MarkEdit.app"
        if FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func revealLibrary(_ item: LibraryItem) {
        let md = URL(fileURLWithPath: item.markdownPath)
        guard FileManager.default.fileExists(atPath: md.path) else {
            errorMessage = "That Markdown file is not on disk anymore."
            return
        }
        // The convert folder — Markdown and pictures — not the original PDF.
        reveal(md)
    }

    func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Converted Markdown will be saved here."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = FolderAccess.access(url)
        FolderAccess.saveCustomFolder(url)
        customFolderPath = url.path
        filePlace = "custom"
        persistAskSettings()
        statusText = "Saving Markdown in \(url.lastPathComponent)"
    }

    func outputURL(for input: URL) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        let parent: URL
        switch filePlace {
        case "library":
            parent = convertedDir
        case "custom":
            if !customFolderPath.isEmpty {
                parent = FolderAccess.accessPath(customFolderPath)
                    ?? URL(fileURLWithPath: customFolderPath)
            } else {
                parent = input.deletingLastPathComponent()
            }
        default:
            parent = input.deletingLastPathComponent()
        }
        let folder = parent.appendingPathComponent(stem, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.appendingPathComponent(stem + ".md")
        } catch {
            if Distribution.isAppStore, filePlace != "library" {
                let fallback = convertedDir.appendingPathComponent(stem, isDirectory: true)
                try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
                statusText = "Saved in the yourMark library folder (App Store cannot write next to that file)"
                return fallback.appendingPathComponent(stem + ".md")
            }
            return folder.appendingPathComponent(stem + ".md")
        }
    }

    private func startWatching() {
        var paths: [String] = []
        for item in library {
            if !item.markdownPath.isEmpty {
                paths.append(item.markdownPath)
            }
            if !item.sourcePath.isEmpty {
                paths.append(item.sourcePath)
            }
        }
        let unique = Set(paths.filter { !$0.isEmpty })
        guard unique != watchedPaths else { return }
        watchedPaths = unique
        watcher.update(paths: Array(unique))
    }

    private func quietWatch(_ seconds: TimeInterval = 4) {
        ignoreWatchUntil = Date().addingTimeInterval(seconds)
    }

    private func fileDidChange(_ path: String) {
        if isBusy { return }
        if Date() < ignoreWatchUntil { return }
        watchDebounce?.cancel()
        watchDebounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            if self.isBusy || Date() < self.ignoreWatchUntil { return }
            if self.library.contains(where: { $0.sourcePath == path }) {
                self.setStatus("Original file changed on disk", important: true)
                return
            }
            guard let item = self.library.first(where: { $0.id == self.selectedLibraryID }) else { return }
            let md = item.markdownPath
            guard path == md else { return }
            guard FileManager.default.isReadableFile(atPath: md) else { return }
            self.setStatus("Updated from disk", important: true)
            self.selectLibrary(item, show: false)
            self.startWatching()
        }
    }

    private func insertLibraryItem(
        source: URL,
        markdown: URL,
        bookmarks: [ManualBookmark],
        title: String? = nil
    ) -> LibraryItem {
        quietWatch(12)
        let values = try? markdown.resourceValues(forKeys: [.fileSizeKey])
        let item = LibraryItem(
            id: UUID(),
            title: title ?? markdown.deletingPathExtension().lastPathComponent,
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
        return item
    }

    private func addToLibrary(source: URL, markdown: URL, bookmarks: [ManualBookmark]) {
        let item = insertLibraryItem(source: source, markdown: markdown, bookmarks: bookmarks)
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
        // Do not open PDFs here. PDFKit during AppModel.init kills the first frame.
    }

    private func fillMissingBookmarks() async {
        let jobs: [(Int, String)] = library.enumerated().compactMap { idx, item in
            item.bookmarks.isEmpty ? (idx, item.markdownPath) : nil
        }
        guard !jobs.isEmpty else { return }
        let found = await PdfWork.runAsync { () -> [Int: [ManualBookmark]] in
            var map: [Int: [ManualBookmark]] = [:]
            for (idx, md) in jobs {
                let side = PdfSidecar.readSidecar(nextTo: URL(fileURLWithPath: md))
                if !side.isEmpty {
                    map[idx] = side
                    continue
                }
                // Sidecar only at launch — opening every PDF here freezes startup.
            }
            return map
        }
        for (idx, marks) in found where library.indices.contains(idx) {
            library[idx].bookmarks = marks
        }
        if !found.isEmpty { saveLibrary() }
    }

    private func saveLibrary() {
        if let data = try? JSONEncoder().encode(library) {
            try? data.write(to: libraryURL)
        }
    }

    func checkUpdates(force: Bool) async {
        guard Distribution.allowsGitHubUpdates else {
            if force { statusText = "Updates come from the App Store" }
            return
        }
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
