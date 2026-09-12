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
    var engineChecked = false
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
    var brightLook = UserDefaults.standard.string(forKey: "brightLook") ?? "paper"
    var errorMessage: String?
    var showHelp = false
    var showSettings = false
    var jobs: [ConvertJob] = []
    var library: [LibraryItem] = []
    var selectedLibraryID: UUID?
    var selectedLibraryIDs: Set<UUID> = []
    var pendingDeleteItems: [LibraryItem] = []
    var pendingDeleteOffersGroup = false
    var showDeleteConfirm = false
    var skipSingleDeleteConfirm = UserDefaults.standard.bool(forKey: "skipSingleDeleteConfirm")
    var deleteFilesWithCard = UserDefaults.standard.object(forKey: "deleteFilesWithCard") as? Bool ?? false
    var libraryDropTargetID: String?
    var previewMarkdown: String = ""
    var previewLines: [PreviewLine] = []
    var previewHeadings: [ManualBookmark] = []
    var previewBaseURL: URL?
    var previewTruncated = false
    var showTranslateCostWarning = false
    var pulseSaveCopy = false
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
    var askHistory: [AskRecord] = []
    var askSourceLine: Int?
    var askSourceText = ""
    var askSourceCardID: UUID?
    var askHitsInReader: [Int] = []
    var askHitIndex = 0
    var askHighlightNeedles: [String] = []
    private var askSourceRevealed = false
    var askScopeTags: Set<String> = []
    var libraryTagFilter: Set<String> = []
    var tagEditorItemID: UUID?
    var tagDraft = ""
    var showTagBrowser = false
    var tagRenameFrom = ""
    var tagRenameDraft = ""
    var hunterSelectChar: Int?
    var hunterSelectLength = 0
    var hunterSelectStamp = 0
    var askBusy = false
    var askError = ""
    var askWebFallback = UserDefaults.standard.bool(forKey: "askWebFallback")
    var filePlace: String = UserDefaults.standard.string(forKey: "filePlace") ?? "beside"
    var customFolderPath: String = UserDefaults.standard.string(forKey: "customFolder") ?? ""
    var appUpdateTag: String?
    var appUpdateURL: URL?
    var draggingFiles = false
    var ocrEnabled = UserDefaults.standard.object(forKey: "ocrEnabled") as? Bool ?? true
    var saveOcrPdf = UserDefaults.standard.object(forKey: "saveOcrPdf") as? Bool ?? false
    var ocrPdfBusy = false
    var ocrPdfNotice: String?
    var ocrScanner: String = UserDefaults.standard.string(forKey: "ocrScanner")
        ?? (Distribution.isAppStore ? "livetext" : "docling")
    var ocrScannerHint = ""
    var showFolderSheet = false
    var showReadySheet = false
    var showInstallSheet = false
    var showOCRSheet = false
    var showMarkEditSheet = false
    var showCrashSheet = false
    var showHunterSaved = false
    var hunterOn = false
    var hunterSnippets: [String] = []
    var hunterGatheredRanges: [NSRange] = []
    var hunterGatheredByPath: [String: [NSRange]] = [:]
    var hunterMarkStamp = 0
    var figureStamp = 0
    var hunterScrollChar: Int?
    var hunterScrollStamp = 0
    var forageBaseBody = ""
    var forageSessionStamp = ""
    var forageSessionIsNew = true
    @ObservationIgnored
    var forageAutosaveTask: Task<Void, Never>?
    var hunterSavedPath = UserDefaults.standard.string(forKey: "hunterSavedPath") ?? ""
    var hunterSavedID: UUID? = UserDefaults.standard.string(forKey: "hunterSavedID").flatMap(UUID.init(uuidString:))
    var deletedForagePaths: [String] = UserDefaults.standard.stringArray(forKey: "deletedForagePaths") ?? []
    var harvestOpen = false
    var forageVaultOpen = false
    var harvestTitle = "FORAGE"
    var harvestLines: [PreviewLine] = []
    var harvestHeadings: [ManualBookmark] = []
    var harvestScrollLine: Int?
    var harvestGen = 0
    var hunterMonitor: Any?
    var askNavMonitor: Any?
    @ObservationIgnored
    var hunterTextMemo: [Int: String] = [:]
    @ObservationIgnored
    var hunterLineMemo: (key: Int, map: [(id: Int, offset: Int)])?
    var interfaceStamp = 0
    var interfaceAddCode = "fr"
    var interfaceAddBusy = false
    var interfaceAddHint = ""
    var interfaceFellBack = false
    var pendingCrash: CrashReport?
    var offerCrashReports = UserDefaults.standard.object(forKey: "offerCrashReports") as? Bool ?? true
    var settingsFocus: String = ""
    var showDoclingPrompt = false
    var pendingGraphics: [URL] = []
    var aiChaptersEnabled = UserDefaults.standard.object(forKey: "aiChaptersEnabled") as? Bool ?? false
    var askReadPictures = UserDefaults.standard.object(forKey: "askReadPictures") as? Bool ?? false
    var stripChrome = UserDefaults.standard.object(forKey: "stripChrome") as? Bool ?? true
    var previewFontName = UserDefaults.standard.string(forKey: "previewFontName") ?? "rounded"
    var editorChoice = UserDefaults.standard.string(forKey: "editorChoice") ?? "markedit"
    var customEditorName = UserDefaults.standard.string(forKey: "customEditorName") ?? ""
    var customEditorScheme = UserDefaults.standard.string(forKey: "customEditorScheme") ?? ""
    var editTarget = UserDefaults.standard.string(forKey: "editTarget") ?? "ask"
    var liveEditPath = ""
    private var lastDiskFingerprint: [String: String] = [:]
    var translateFrom = UserDefaults.standard.string(forKey: "translateFrom") ?? "auto"
    var translateTo = UserDefaults.standard.string(forKey: "translateTo") ?? TranslateLang.deviceTo
    var recentTranslateLangs: [String] = UserDefaults.standard.stringArray(forKey: "recentTranslateLangs") ?? []
    var translateEngine = UserDefaults.standard.string(forKey: "translateEngine") ?? "ask"
    var translateLayout = UserDefaults.standard.string(forKey: "translateLayout") ?? "replace"
    var translateSaveMode = UserDefaults.standard.string(forKey: "translateSaveMode") ?? "keep"
    var translateMarkdown: String?
    var translateLines: [PreviewLine] = []
    var translateHeadings: [ManualBookmark] = []
    var translateScrollLine: Int?
    var translateBusy = false
    @ObservationIgnored
    private var libraryViewCache: (fp: UInt64, groups: [LibraryGroup], total: Int)?
    var sideBySide = false
    var sideBySideNotice: String?
    var pairPickNotice: String?
    var pairMismatchNotice: String?
    var awaitingPairPick = false
    var pairPickLeadID: UUID?
    var sideBySideOpening = false
    var libraryCollapsed = false
    var ocrAppChoice = UserDefaults.standard.string(forKey: "ocrAppChoice") ?? "none"
    var customOcrAppName = UserDefaults.standard.string(forKey: "customOcrAppName") ?? ""
    var linkScroll = true
    var forageLinkActive = false
    var forageLinkUserOff = false
    var linkMaster: LinkPane?
    var windowSize: CGSize = .zero
    var linkedHeading = ""
    var linkedTitles: [(main: String, translate: String)] = []
    private var linkScrollIgnoreUntil = Date.distantPast
    private var linkScrollIgnorePane: LinkPane?
    private var ignoreVisibleUntil = Date.distantPast
    private var visibleHeading: [LinkPane: String] = [:]
    private var visibleLine: [LinkPane: Int] = [:]
    private var lastSlaveFollowAt = Date.distantPast
    private var lastFollowLine: [LinkPane: Int] = [:]
    var librarySort: LibrarySortKind = .dateNew
    var titleSearch = ""
    var fileSearch = ""
    var fileSearchHits: Set<UUID> = []
    var fileSearchPending = false
    var askTitleHits: Set<UUID> = []
    var titleAskBusy = false
    var titleHitIDs: [UUID] = []
    var titleHitIndex = 0
    var fileHitsInReader: [Int] = []
    var fileHitIndex = 0
    private var titleAskGen = 0
    private var fileSearchGen = 0
    static let libraryGroupCap = 100
    var googleKeyDraft = ""
    var googleHasKey = false
    var googleKeyHint = ""
    var googleCheckingKey = false
    var googleKeyTestPassed = false
    var googleKeyTestNote = ""
    var doclingPath: String? = OcrService.doclingPath()
    var ocrmypdfPath: String? = OcrService.ocrmypdfPath()
    private var convertWanted = false
    private var convertCancelled = false
    private var ignoreWatchUntil = Date.distantPast
    private var previewGen = 0
    private var previewNeedsLoad = false

    let service = MarkItDownService()
    let askService = AskService()
    private let libraryURL: URL
    private let askHistoryURL: URL
    let convertedDir: URL
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
        askHistoryURL = dir.appendingPathComponent("ask-history.json")
        convertedDir = dir.appendingPathComponent("Converted", isDirectory: true)
        try? FileManager.default.createDirectory(at: convertedDir, withIntermediateDirectories: true)
        if Distribution.isAppStore {
            if let restored = FolderAccess.restoreCustomFolder() {
                customFolderPath = restored.path
            }
            if UserDefaults.standard.object(forKey: "masFilePlaceSet") == nil {
                if customFolderPath.isEmpty {
                    filePlace = "library"
                    UserDefaults.standard.set("library", forKey: "filePlace")
                }
                UserDefaults.standard.set(true, forKey: "masFilePlaceSet")
            }
        }
        useChosenFolderIfPresent()
        loadLibrary()
        loadAskHistory()
        startAskNavMonitor()
        migrateHiddenConvertedIfNeeded()
        scanForageVault()
        seedGuideIfNeeded()
        interfaceFellBack = InterfaceStore.recoverIfNeeded()
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
        } else if googleHasKey, !askHasKey, translateEngine != "google" {
            translateEngine = "google"
            UserDefaults.standard.set("google", forKey: "translateEngine")
        }
        watcher.onChange = { path in
            DispatchQueue.main.async { [weak self] in
                self?.fileDidChange(path)
            }
        }
        ingestInboxMarkdown(announce: false)
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
        applyWindowAppearance()
    }

    func applyWindowAppearance() {
        let next: NSAppearance?
        switch appearance {
        case "bright": next = NSAppearance(named: .aqua)
        case "dim": next = NSAppearance(named: .darkAqua)
        default: next = nil
        }
        for window in NSApp.windows {
            window.appearance = next
            refreshControlAppearance(window.contentView, next)
        }
    }

    private func refreshControlAppearance(_ view: NSView?, _ appearance: NSAppearance?) {
        guard let view else { return }
        if view is NSTextField {
            view.appearance = appearance
        }
        for child in view.subviews {
            refreshControlAppearance(child, appearance)
        }
    }

    func setBrightLook(_ value: String) {
        brightLook = value
        UserDefaults.standard.set(value, forKey: "brightLook")
    }

    func bootstrap() async {
        if Distribution.isAppStore {
            UserDefaults.standard.set(true, forKey: "sawInstallSheet")
            UserDefaults.standard.set(true, forKey: "sawOCRSheet")
            let status = await service.refreshStatus()
            enginePath = status.path
            engineVersion = status.path == nil ? "missing from this copy" : status.version
            engineChecked = true
            statusText = status.path == nil ? "Converter missing from this copy" : "Ready"
            if offerFolderSheetIfNeeded() {
                Task { await fillMissingBookmarks() }
                startWatching()
                return
            }
            Task { await fillMissingBookmarks() }
            maybeOfferCrashReport()
            startWatching()
            return
        }
        let status = await service.refreshStatus()
        enginePath = status.path
        engineVersion = status.version
        engineChecked = true
        if offerFolderSheetIfNeeded() {
            if status.path != nil {
                statusText = "Ready"
            }
            return
        }
        if status.path == nil, !installingEngine {
            statusText = "Installing Microsoft MarkItDown…"
            await installEngine()
        } else if status.path != nil {
            statusText = "Ready"
            Task { await checkUpdates(force: false) }
        }
        refreshOCRTools()
        Task { await fillMissingBookmarks() }
        maybeOfferCrashReport()
        startWatching()
    }

    func offerFolderSheetIfNeeded() -> Bool {
        if UserDefaults.standard.bool(forKey: "sawFolderSheet") { return false }
        if filePlace == "custom", !customFolderPath.isEmpty {
            UserDefaults.standard.set(true, forKey: "sawFolderSheet")
            return false
        }
        showFolderSheet = true
        return true
    }

    func keepFilesOnThisMac() {
        setFilePlace("library")
        finishFolderChoice()
    }

    func setFilePlace(_ place: String) {
        filePlace = place
        if place != "custom" {
            customFolderPath = ""
            UserDefaults.standard.removeObject(forKey: "customFolder")
            UserDefaults.standard.removeObject(forKey: "customFolderBookmark")
        }
        persistAskSettings()
    }

    func finishFolderChoice() {
        UserDefaults.standard.set(true, forKey: "sawFolderSheet")
        showFolderSheet = false
        showReadySheet = true
    }

    func finishSetupWizard() {
        UserDefaults.standard.set(true, forKey: "sawFolderSheet")
        UserDefaults.standard.set(true, forKey: "sawInstallSheet")
        UserDefaults.standard.set(true, forKey: "sawOCRSheet")
        UserDefaults.standard.set(true, forKey: "sawMarkEditSheet")
        showReadySheet = false
        Task { await continueAfterFolder() }
    }

    func continueAfterFolder() async {
        if Distribution.isAppStore {
            maybeOfferCrashReport()
            startWatching()
            return
        }
        if enginePath == nil, !installingEngine {
            statusText = "Installing Microsoft MarkItDown…"
            await installEngine()
        } else if enginePath != nil {
            statusText = "Ready"
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

    func openMarkTextDownload() {
        if let url = URL(string: "https://github.com/marktext/marktext/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    func maybeOfferCrashReport() {
        if Distribution.isAppStore { return }
        guard offerCrashReports else { return }
        if showFolderSheet || showReadySheet || showInstallSheet || showOCRSheet || showMarkEditSheet { return }
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
        if Distribution.isAppStore {
            CrashReports.openMail(for: report)
        } else if let url = CrashReports.githubURL(for: report) {
            NSWorkspace.shared.open(url)
        }
        CrashReports.markSent(report.id)
        pendingCrash = nil
        showCrashSheet = false
        statusText = Distribution.isAppStore
            ? L("Crash report copied — Mail is open")
            : L("Crash report copied — paste it in a message")
    }

    func emailLastCrash() {
        guard let report = CrashReports.latestAny() else { return }
        CrashReports.copyLog(report)
        CrashReports.openMail(for: report)
        CrashReports.markSent(report.id)
        statusText = L("Crash report copied — Mail is open")
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

    func originKey(for item: LibraryItem) -> String {
        if !item.sourcePath.isEmpty { return item.sourcePath.lowercased() }
        let folder = URL(fileURLWithPath: item.markdownPath).deletingLastPathComponent().standardizedFileURL.path.lowercased()
        return folder + "|" + Self.pairingStem(forMarkdownPath: item.markdownPath).lowercased()
    }

    func isOriginMaster(_ item: LibraryItem) -> Bool {
        let stem = Self.pairingStem(forMarkdownPath: item.markdownPath)
        let name = URL(fileURLWithPath: item.markdownPath).deletingPathExtension().lastPathComponent
        return name.caseInsensitiveCompare(stem) == .orderedSame
    }

    func libraryGroups(from items: [LibraryItem]) -> [LibraryGroup] {
        var buckets: [String: [LibraryItem]] = [:]
        var order: [String] = []
        for item in items where !Self.isForagePath(item.markdownPath) && item.sourceName != "FORAGE" {
            let key = originKey(for: item)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.compactMap { key in
            guard var members = buckets[key], !members.isEmpty else { return nil }
            let master = members.first(where: { isOriginMaster($0) })
                ?? members.min(by: { $0.title.count < $1.title.count })!
            members.removeAll { $0.id == master.id }
            return LibraryGroup(id: key, master: master, children: members)
        }
    }

    var visibleLibraryGroups: [LibraryGroup] { libraryView().groups }

    var libraryCountLabel: String {
        let view = libraryView()
        if view.groups.count == view.total { return "\(view.total)" }
        return "\(view.groups.count) of \(view.total)"
    }

    private func libraryView() -> (groups: [LibraryGroup], total: Int) {
        let fp = libraryViewFingerprint()
        if let libraryViewCache, libraryViewCache.fp == fp {
            return (libraryViewCache.groups, libraryViewCache.total)
        }
        let all = libraryGroups(from: library)
        var groups = all
        let t = titleSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = fileSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !libraryTagFilter.isEmpty {
            groups = groups.filter { g in
                g.items.contains { item in
                    libraryTagFilter.isSubset(of: Set(item.tags))
                }
            }
        }
        if !t.isEmpty || !f.isEmpty {
            groups = groups.filter { g in
                g.items.contains { item in
                    let titleOK = t.isEmpty
                        || Self.titleMatches(item, query: t)
                        || askTitleHits.contains(item.id)
                    let fileOK = f.isEmpty || fileSearchPending || fileSearchHits.contains(item.id)
                    return titleOK && fileOK
                }
            }
        }
        switch librarySort {
        case .manual: break
        case .nameAsc:
            groups.sort { $0.master.title.localizedCaseInsensitiveCompare($1.master.title) == .orderedAscending }
        case .nameDesc:
            groups.sort { $0.master.title.localizedCaseInsensitiveCompare($1.master.title) == .orderedDescending }
        case .dateNew:
            groups.sort { $0.master.addedAt > $1.master.addedAt }
        case .dateOld:
            groups.sort { $0.master.addedAt < $1.master.addedAt }
        case .tagAsc:
            groups.sort { tagSortKey($0) < tagSortKey($1) }
        case .tagDesc:
            groups.sort { tagSortKey($0) > tagSortKey($1) }
        }
        libraryViewCache = (fp, groups, all.count)
        return (groups, all.count)
    }

    private func libraryViewFingerprint() -> UInt64 {
        var h: UInt64 = 2_166_136_261
        func mix(_ v: Int) {
            h ^= UInt64(truncatingIfNeeded: v)
            h &*= 16_777_619
        }
        mix(library.count)
        mix(librarySort.rawValue.hashValue)
        mix(titleSearch.hashValue)
        mix(fileSearch.hashValue)
        mix(fileSearchHits.count)
        mix(askTitleHits.count)
        mix(fileSearchPending ? 1 : 0)
        mix(forageVaultOpen ? 1 : 0)
        for item in library {
            mix(item.id.hashValue)
            mix(item.title.hashValue)
            mix(item.openedAt.hashValue)
            mix(item.addedAt.hashValue)
            mix(item.tags.joined(separator: ",").hashValue)
        }
        mix(libraryTagFilter.sorted().joined(separator: ",").hashValue)
        return h
    }

    private func tagSortKey(_ group: LibraryGroup) -> String {
        group.items.flatMap(\.tags).min() ?? "\u{FFFF}"
    }

    func setLibrarySort(_ kind: LibrarySortKind) {
        if librarySort == kind {
            switch kind {
            case .nameAsc: librarySort = .nameDesc
            case .nameDesc: librarySort = .nameAsc
            case .dateNew: librarySort = .dateOld
            case .dateOld: librarySort = .dateNew
            case .tagAsc: librarySort = .tagDesc
            case .tagDesc: librarySort = .tagAsc
            case .manual: break
            }
        } else if kind == .nameAsc, librarySort == .nameDesc {
            librarySort = .nameAsc
        } else if kind == .dateNew, librarySort == .dateOld {
            librarySort = .dateNew
        } else if kind == .tagAsc, librarySort == .tagDesc {
            librarySort = .tagAsc
        } else {
            librarySort = kind
        }
    }

    func moveLibraryGroup(from: IndexSet, to: Int) {
        guard titleSearch.isEmpty, fileSearch.isEmpty else { return }
        var groups = libraryGroups(from: library)
        guard !groups.isEmpty else { return }
        setLibrarySort(.manual)
        groups.move(fromOffsets: from, toOffset: to)
        library = groups.flatMap(\.items)
        saveLibrary()
    }

    func nudgeLibraryGroup(_ id: String, by delta: Int) {
        guard titleSearch.isEmpty, fileSearch.isEmpty else { return }
        var groups = libraryGroups(from: library)
        guard let from = groups.firstIndex(where: { $0.id == id }) else { return }
        let to = from + delta
        guard groups.indices.contains(to) else { return }
        setLibrarySort(.manual)
        groups.swapAt(from, to)
        library = groups.flatMap(\.items)
        saveLibrary()
    }

    func reorderLibraryGroup(moving src: String, onto dest: String?) {
        guard titleSearch.isEmpty, fileSearch.isEmpty else { return }
        var groups = libraryGroups(from: library)
        guard let from = groups.firstIndex(where: { $0.id == src }) else { return }
        setLibrarySort(.manual)
        let moving = groups.remove(at: from)
        if let dest, let destIdx = groups.firstIndex(where: { $0.id == dest }) {
            groups.insert(moving, at: destIdx)
        } else {
            groups.insert(moving, at: 0)
        }
        library = groups.flatMap(\.items)
        libraryDropTargetID = nil
        saveLibrary()
    }

    func setSkipSingleDeleteConfirm(_ skip: Bool) {
        skipSingleDeleteConfirm = skip
        UserDefaults.standard.set(skip, forKey: "skipSingleDeleteConfirm")
    }

    func setDeleteFilesWithCard(_ on: Bool) {
        deleteFilesWithCard = on
        UserDefaults.standard.set(on, forKey: "deleteFilesWithCard")
    }

    func requestDelete(_ items: [LibraryItem]) {
        var seen = Set<UUID>()
        let unique = items.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { return }
        pendingDeleteOffersGroup = false
        if unique.count == 1, let item = unique.first, isOriginMaster(item),
           !translationChildren(of: item).isEmpty {
            pendingDeleteItems = unique
            pendingDeleteOffersGroup = true
            showDeleteConfirm = true
            return
        }
        if unique.count == 1, skipSingleDeleteConfirm {
            removeLibraryItems(unique)
            return
        }
        pendingDeleteItems = unique
        showDeleteConfirm = true
    }

    func confirmPendingDelete(dontAskAgain: Bool) {
        let items = pendingDeleteItems
        if dontAskAgain, items.count == 1, !pendingDeleteOffersGroup {
            setSkipSingleDeleteConfirm(true)
        }
        pendingDeleteItems = []
        pendingDeleteOffersGroup = false
        showDeleteConfirm = false
        removeLibraryItems(items)
    }

    func confirmDeleteWithTranslations() {
        guard let master = pendingDeleteItems.first else {
            cancelPendingDelete()
            return
        }
        let items = [master] + translationChildren(of: master)
        pendingDeleteItems = []
        pendingDeleteOffersGroup = false
        showDeleteConfirm = false
        removeLibraryItems(items)
    }

    func cancelPendingDelete() {
        pendingDeleteItems = []
        pendingDeleteOffersGroup = false
        showDeleteConfirm = false
    }

    func translationChildren(of item: LibraryItem) -> [LibraryItem] {
        let key = originKey(for: item)
        return library.filter {
            $0.id != item.id && originKey(for: $0) == key && !isOriginMaster($0)
        }
    }

    var deleteConfirmDisplayTitle: String {
        if let item = pendingDeleteItems.first, pendingDeleteItems.count == 1 || pendingDeleteOffersGroup {
            return L("Remove “%@”?").replacingOccurrences(of: "%@", with: item.title)
        }
        return L("Remove these cards?")
    }

    var deleteConfirmDisplayMessage: String {
        var parts: [String] = []
        if pendingDeleteOffersGroup, let item = pendingDeleteItems.first {
            let n = translationChildren(of: item).count
            if n == 1 {
                parts.append(L("This is the original. 1 translation sits under it."))
            } else {
                parts.append(
                    L("This is the original. %d translations sit under it.")
                        .replacingOccurrences(of: "%d", with: "\(n)")
                )
            }
        }
        parts.append(L(deleteConfirmDiskMessage))
        return parts.joined(separator: "\n")
    }

    private var deleteConfirmDiskMessage: String {
        let items = pendingDeleteItems
        let forage = items.contains { Self.isForagePath($0.markdownPath) || $0.sourceName == "FORAGE" }
        let many = items.count > 1 || pendingDeleteOffersGroup
        if deleteFilesWithCard {
            if many {
                return forage
                    ? "This also deletes those converts’ Markdown, figures, and folders. Original PDFs stay. Forage notes stay on disk."
                    : "This also deletes those converts’ Markdown, figures, and folders. Original PDFs stay."
            }
            if let item = items.first, Self.isForagePath(item.markdownPath) || item.sourceName == "FORAGE" {
                return "The forage note stays on disk. Delete it in Finder if you want it gone."
            }
            return "This also deletes the Markdown, figures, and that convert’s folder. The original PDF stays."
        }
        if many {
            return forage
                ? "The files stay on disk, including forage notes."
                : "The files stay on disk."
        }
        if let item = items.first, Self.isForagePath(item.markdownPath) || item.sourceName == "FORAGE" {
            return "The forage note stays on disk. Delete it in Finder if you want it gone."
        }
        return "The file stays on disk."
    }

    func setTitleSearch(_ text: String) {
        titleSearch = text
        askTitleHits = []
        titleAskBusy = false
        titleAskGen += 1
        refreshTitleHits()
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard askHasKey, q.count >= 2 else { return }
        titleAskBusy = true
        let gen = titleAskGen
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard gen == titleAskGen else { return }
            await runAskTitleSearch(q)
        }
    }

    func clearTitleSearch() {
        setTitleSearch("")
    }

    func setFileSearch(_ text: String) {
        fileSearch = text
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            fileSearchHits = []
            fileSearchPending = false
            fileHitsInReader = []
            fileHitIndex = 0
            return
        }
        fileSearchPending = true
        fileSearchGen += 1
        let gen = fileSearchGen
        refreshFileHits(in: previewLines)
        let paths = library.map { ($0.id, $0.markdownPath) }
        Task.detached {
            guard let query = FileSearchQuery.parse(q) else {
                await MainActor.run {
                    guard gen == self.fileSearchGen else { return }
                    self.fileSearchHits = []
                    self.fileSearchPending = false
                    self.refreshTitleHits()
                }
                return
            }
            var hits = Set<UUID>()
            for (id, path) in paths {
                guard let handle = FileHandle(forReadingAtPath: path) else { continue }
                defer { try? handle.close() }
                let data = handle.readData(ofLength: AppModel.readerMaxBytes)
                guard let text = AppModel.decodeMarkdownPrefix(data) else { continue }
                if query.matches(text) {
                    hits.insert(id)
                }
            }
            await MainActor.run {
                guard gen == self.fileSearchGen else { return }
                self.fileSearchHits = hits
                self.fileSearchPending = false
                self.refreshTitleHits()
                self.openFirstFileSearchHitIfNeeded()
            }
        }
    }

    func clearFileSearch() {
        setFileSearch("")
    }

    static func titleMatches(_ item: LibraryItem, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let hay = item.title + " " + item.sourceName
        if hay.localizedCaseInsensitiveContains(q) { return true }
        let tagNeedle = q.hasPrefix("#") ? String(q.dropFirst()) : q
        if item.tags.contains(where: { $0.localizedCaseInsensitiveContains(tagNeedle) }) {
            return true
        }
        let stop: Set<String> = [
            "the", "and", "for", "that", "this", "with", "from", "a", "an", "of", "in", "to",
            "el", "la", "de", "los", "las", "un", "una", "het", "een", "van",
        ]
        let words = q.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 && !stop.contains($0) }
        guard !words.isEmpty else { return false }
        let low = hay.lowercased()
        if words.allSatisfy({ low.contains($0) }) { return true }
        return words.contains { $0.count >= 4 && low.contains($0) }
    }

    var titleSearchSummary: String {
        let q = titleSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return "" }
        if titleAskBusy { return L("Asking…") }
        if titleHitIDs.isEmpty { return L("No matches") }
        return "\(titleHitIndex + 1) of \(titleHitIDs.count)"
    }

    var fileSearchSummary: String {
        let q = fileSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return "" }
        if fileSearchPending, fileHitsInReader.isEmpty { return L("Searching…") }
        if !fileHitsInReader.isEmpty {
            return "\(fileHitIndex + 1) of \(fileHitsInReader.count)"
        }
        if !fileSearchHits.isEmpty {
            return "\(fileSearchHits.count) \(fileSearchHits.count == 1 ? L("file") : L("files"))"
        }
        return L("No matches")
    }

    func refreshTitleHits() {
        let ids = visibleLibraryGroups.flatMap(\.items).map(\.id)
        titleHitIDs = ids
        if let sel = selectedLibraryID, let i = ids.firstIndex(of: sel) {
            titleHitIndex = i
        } else {
            titleHitIndex = ids.isEmpty ? 0 : min(titleHitIndex, ids.count - 1)
        }
    }

    func refreshFileHits(in lines: [PreviewLine]) {
        let q = fileSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let query = FileSearchQuery.parse(q) else {
            fileHitsInReader = []
            fileHitIndex = 0
            return
        }
        var hits: [Int] = []
        hits.reserveCapacity(min(lines.count, 120))
        if query.isSimpleTerm, let needle = query.highlightTerms.first {
            for row in lines {
                var search = row.text.startIndex
                var onLine = 0
                while hits.count < 120, onLine < 6, search < row.text.endIndex,
                      let r = row.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: search..<row.text.endIndex) {
                    hits.append(row.id)
                    onLine += 1
                    search = r.upperBound
                }
                if hits.count >= 120 { break }
            }
        } else {
            hits = query.hitLineIDs(in: lines)
        }
        fileHitsInReader = hits
        if fileHitIndex >= hits.count { fileHitIndex = 0 }
        if let first = hits.first { revealReaderLine(first) }
    }

    private func openFirstFileSearchHitIfNeeded() {
        guard !fileSearchHits.isEmpty else { return }
        if awaitingPairPick || sideBySideOpening { return }
        if let sel = selectedLibraryID, fileSearchHits.contains(sel) {
            refreshFileHits(in: previewLines)
            return
        }
        let first = visibleLibraryGroups.flatMap(\.items).first { fileSearchHits.contains($0.id) }
        if let first {
            selectLibrary(first)
        }
    }

    func nextTitleHit() {
        refreshTitleHits()
        guard !titleHitIDs.isEmpty else { return }
        titleHitIndex = (titleHitIndex + 1) % titleHitIDs.count
        if let item = library.first(where: { $0.id == titleHitIDs[titleHitIndex] }) {
            selectLibrary(item)
        }
    }

    func prevTitleHit() {
        refreshTitleHits()
        guard !titleHitIDs.isEmpty else { return }
        titleHitIndex = (titleHitIndex - 1 + titleHitIDs.count) % titleHitIDs.count
        if let item = library.first(where: { $0.id == titleHitIDs[titleHitIndex] }) {
            selectLibrary(item)
        }
    }

    func nextFileHit() {
        if fileHitsInReader.isEmpty {
            cycleFileCard(1)
            return
        }
        fileHitIndex = (fileHitIndex + 1) % fileHitsInReader.count
        revealReaderLine(fileHitsInReader[fileHitIndex])
    }

    func prevFileHit() {
        if fileHitsInReader.isEmpty {
            cycleFileCard(-1)
            return
        }
        fileHitIndex = (fileHitIndex - 1 + fileHitsInReader.count) % fileHitsInReader.count
        revealReaderLine(fileHitsInReader[fileHitIndex])
    }

    func revealReaderLine(_ idx: Int) {
        ignoreVisibleUntil = Date().addingTimeInterval(0.85)
        if hunterOn {
            hunterScrollChar = hunterCharOffset(forLine: idx, in: previewLines)
            hunterScrollStamp += 1
        } else {
            bumpMainScroll(idx)
        }
    }

    var hunterHighlightStamp: Int {
        var hasher = Hasher()
        hasher.combine(fileSearch)
        hasher.combine(fileHitIndex)
        hasher.combine(fileHitsInReader)
        hasher.combine(askHitIndex)
        hasher.combine(askHitsInReader)
        hasher.combine(askHighlightNeedles)
        hasher.combine(readerHighlightNeedles)
        return hasher.finalize()
    }

    func hunterHighlightPlan(in lines: [PreviewLine]) -> (all: [NSRange], current: [NSRange]) {
        let needles = readerHighlightNeedles
        guard !needles.isEmpty else { return ([], []) }
        let map = hunterLineMap(from: lines)
        let full = hunterReaderText(from: lines) as NSString
        var all: [NSRange] = []
        var current: [NSRange] = []
        let fileQ = fileSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentLine: Int? = {
            if !fileQ.isEmpty {
                return fileHitsInReader.indices.contains(fileHitIndex) ? fileHitsInReader[fileHitIndex] : nil
            }
            return askHitsInReader.indices.contains(askHitIndex) ? askHitsInReader[askHitIndex] : nil
        }()
        let booleanLineIDs: Set<Int> = {
            if !fileQ.isEmpty, let query = FileSearchQuery.parse(fileQ), !query.isSimpleTerm {
                return Set(query.hitLineIDs(in: lines))
            }
            if fileQ.isEmpty, FileSearchQuery.hasBooleanOperators(askQuestion) {
                return Set(askHitsInReader)
            }
            return []
        }()
        var occurrence = 0
        for (i, entry) in map.enumerated() {
            let start = entry.offset
            let end = i + 1 < map.count ? max(start, map[i + 1].offset - 1) : full.length
            let lineLen = max(0, end - start)
            guard lineLen > 0, start + lineLen <= full.length else { continue }
            let line = full.substring(with: NSRange(location: start, length: lineLen))
            if !fileQ.isEmpty, let query = FileSearchQuery.parse(fileQ), query.isSimpleTerm,
               let needle = query.highlightTerms.first {
                var search = line.startIndex
                var onLine = 0
                while onLine < 6, search < line.endIndex,
                      let r = line.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: search..<line.endIndex) {
                    let nr = NSRange(r, in: line)
                    let mark = NSRange(location: start + nr.location, length: nr.length)
                    all.append(mark)
                    if occurrence == fileHitIndex { current.append(mark) }
                    occurrence += 1
                    onLine += 1
                    search = r.upperBound
                }
            } else {
                if !booleanLineIDs.isEmpty, !booleanLineIDs.contains(entry.id) { continue }
                for needle in needles {
                    var search = line.startIndex
                    var marks = 0
                    while marks < 8, search < line.endIndex,
                          let r = line.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: search..<line.endIndex) {
                        let nr = NSRange(r, in: line)
                        let mark = NSRange(location: start + nr.location, length: nr.length)
                        all.append(mark)
                        if entry.id == currentLine { current.append(mark) }
                        marks += 1
                        search = r.upperBound
                    }
                }
            }
            if all.count >= 200 { break }
        }
        return (all, current)
    }

    private func cycleFileCard(_ step: Int) {
        let ids = visibleLibraryGroups.flatMap(\.items).map(\.id)
        guard !ids.isEmpty else { return }
        let current = selectedLibraryID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = (current + step + ids.count) % ids.count
        if let item = library.first(where: { $0.id == ids[next] }) {
            selectLibrary(item)
        }
    }

    func isCurrentFileHit(lineID: Int) -> Bool {
        if !fileSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fileHitsInReader.indices.contains(fileHitIndex) && fileHitsInReader[fileHitIndex] == lineID
        }
        return askHitsInReader.indices.contains(askHitIndex) && askHitsInReader[askHitIndex] == lineID
    }

    func isAskHitLine(_ lineID: Int) -> Bool {
        askHitsInReader.contains(lineID)
    }

    var readerHighlightNeedles: [String] {
        let q = fileSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            return FileSearchQuery.parse(q)?.highlightTerms ?? []
        }
        return askHighlightNeedles
    }

    var askHitSummary: String {
        guard !askHitsInReader.isEmpty else { return "" }
        return "\(askHitIndex + 1) of \(askHitsInReader.count)"
    }

    func nextAskHit() {
        guard !askHitsInReader.isEmpty else { return }
        askHitIndex = (askHitIndex + 1) % askHitsInReader.count
        jumpAskHit()
    }

    func prevAskHit() {
        guard !askHitsInReader.isEmpty else { return }
        askHitIndex = (askHitIndex - 1 + askHitsInReader.count) % askHitsInReader.count
        jumpAskHit()
    }

    private func runAskTitleSearch(_ query: String) async {
        let titles = library.map { item in
            item.sourceName.isEmpty ? item.title : "\(item.title) · \(item.sourceName)"
        }
        let plain = library.map(\.title)
        let settings = AskService.Settings(
            provider: askProvider,
            model: askModel,
            baseURL: askBaseURL,
            apiKey: AskSecrets.load()
        )
        do {
            let names = try await askService.matchLibraryTitles(query: query, titles: titles + plain, settings: settings)
            let hits = Set(library.filter { item in
                names.contains(where: {
                    item.title.caseInsensitiveCompare($0) == .orderedSame
                        || item.sourceName.caseInsensitiveCompare($0) == .orderedSame
                        || item.title.localizedCaseInsensitiveContains($0)
                        || $0.localizedCaseInsensitiveContains(item.title)
                })
            }.map(\.id))
            askTitleHits = hits
        } catch {
            askTitleHits = []
        }
        titleAskBusy = false
        refreshTitleHits()
    }

    private func enforceLibraryCap(keeping newID: UUID?) {
        let groups = libraryGroups(from: library)
        guard groups.count > Self.libraryGroupCap else { return }
        let droppable = groups.filter { $0.master.id != Self.guideID && !$0.items.contains(where: { $0.id == newID }) }
        guard let victim = droppable.min(by: {
            let a = $0.items.map(\.openedAt).max() ?? $0.master.addedAt
            let b = $1.items.map(\.openedAt).max() ?? $1.master.addedAt
            return a < b
        }) else { return }
        let ids = Set(victim.items.map(\.id))
        library.removeAll { ids.contains($0.id) }
        statusText = "Library is full (100). Removed \(victim.master.title) from the list — the file is still on disk."
        saveLibrary()
    }

    private func seedGuideIfNeeded() {
        if UserDefaults.standard.bool(forKey: "dismissedGuide") { return }
        if library.contains(where: { $0.id == Self.guideID }) { return }
        let url = forageHome.appendingPathComponent("Getting started with yourMark.md")
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

    A file that is already Markdown skips the converter. File → Open, a drop on the window, or putting the `.md` in the folder you chose — it appears as a library card and stays that file. No extra convert folder.

    First launch asks you to **choose a folder**. That folder is watched: a new `.md` there shows up in the library at once. You can change it later in Settings → Converted files.

    Settings → **Automatically add chapters with AI** (off unless you tick it) uses your Ask AI key to insert headings when the file has no outline.

    If the PDF is a **scan** (no text layer), yourMark uses IBM **Docling** for layout — tables, columns, figures. That takes a little longer than a normal convert. Microsoft MarkItDown still handles ordinary PDFs. Pictures in a digital PDF are pulled into a `figures` folder inside a little folder named after the file. If Docling is missing, we fall back to OCRmyPDF / Apple Live Text.

    Settings → **Remove headers and footers** (on by default) drops the repeating page title, page number, date, and header logos.

    ## Picture links

    Pictures are files in the figures folder. The Markdown only points at them. In the reader, rest the pointer on a blue link for a small preview. Click the link: Finder opens with that picture selected.

    ## Bookmarks

    The Bookmarks pane is the PDF outline when the file has one, otherwise headings. Click to jump, like Preview.

    ## Tables and figures

    Real tables become Markdown tables. Pictures from the PDF sit in a figures folder inside the convert folder, linked in page order. Scans get OCR first.

    ## Library cards

    Swipe a card left to delete, or right-click for Open, Show in Finder, and Delete. **Show in Finder** highlights the little folder when there are pictures (Markdown plus `figures`), or just the `.md` when there are none. Compress that to share with AI — not the Markdown alone if pictures exist. If you change that Markdown, the library updates. Drag to rearrange.

    ## Ask chapter

    Open a file, pick a heading, and ask. The answer comes only from that chapter. With your own key (Settings) you can also ask the entire file.

    If the chapter does not provide an answer, **Search the web** opens a browser tab with the question, the chapter, and that sentence.

    ## Settings

    Pick the model, paste your API key, then press **Enter** to lock it in. Converted files and Library sit under Interface language.

    - **Next to the original PDF** — a little folder with the Markdown and pictures together
    - **On this Mac only** — a hidden folder, not iCloud
    - **Choose a folder** — the folder you pick (iCloud if you want a copy off this Mac)

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
        UserDefaults.standard.set(saveOcrPdf, forKey: "saveOcrPdf")
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
        statusText = "Ask AI key cleared"
    }

    func runAsk() async {
        let q = askQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        askBusy = true
        askError = ""
        askAnswer = ""
        askOpenAnswer = ""
        askSourceLine = nil
        askSourceText = ""
        askSourceCardID = nil
        askHitsInReader = []
        askHitIndex = 0
        askHighlightNeedles = []
        askSourceRevealed = false
        defer { askBusy = false }
        do {
            if !askScopeTags.isEmpty {
                try await runTaggedAsk(q)
                return
            }
            let markdown: String
            if let item = library.first(where: { $0.id == selectedLibraryID }) {
                let path = item.markdownPath
                markdown = await Task.detached(priority: .utility) {
                    AppModel.readMarkdownPrefix(path: path, maxBytes: 280_000)?.text
                }.value ?? previewMarkdown
            } else {
                markdown = previewMarkdown
            }
            let mark = documentOutline.first {
                $0.title.caseInsensitiveCompare(askChapter) == .orderedSame
            }
            let excerpt: String
            if let query = FileSearchQuery.parse(q), FileSearchQuery.hasBooleanOperators(q) {
                let rows = previewLines.isEmpty
                    ? markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                        .map { PreviewLine(id: $0.offset, text: String($0.element)) }
                    : previewLines
                let plan = booleanAskPlan(query: query, in: rows)
                askHighlightNeedles = query.highlightTerms
                askHitsInReader = plan.hits
                askHitIndex = 0
                if let first = plan.hits.first {
                    askSourceLine = first
                    askSourceText = passageAround(line: first, in: rows)
                }
                guard !plan.excerpt.isEmpty else {
                    askAnswer = "Nothing in this chapter matches that search. Nothing was sent."
                    return
                }
                excerpt = plan.excerpt
            } else {
                excerpt = AskService.excerpt(
                    markdown: markdown,
                    heading: askChapter,
                    startLine: mark?.lineIndex
                )
            }
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
            bindAskSource(answer: askAnswer, question: q, cardID: selectedLibraryID)
            rememberAsk(
                question: q,
                answer: askAnswer,
                openAnswer: askOpenAnswer,
                chapter: askChapter,
                fileTitle: title
            )
        } catch {
            askError = error.localizedDescription
        }
    }

    private func runTaggedAsk(_ q: String) async throws {
        let wanted = askScopeTags
        let cards = library.filter { wanted.isSubset(of: Set($0.tags)) }
        guard !cards.isEmpty else {
            askAnswer = "No library cards have those tags."
            return
        }
        let query = FileSearchQuery.parse(q)
        var chunks: [(item: LibraryItem, excerpt: String)] = []
        var budget = 12_000
        for item in cards {
            if budget < 400 { break }
            let pack = await Task.detached(priority: .utility) {
                AppModel.readMarkdownPrefix(path: item.markdownPath, maxBytes: 280_000)
            }.value
            guard let text = pack?.text, !text.isEmpty else { continue }
            let hit: String
            if let query, query.matches(text) {
                hit = Self.taggedExcerpt(from: text, query: query, cap: min(2_400, budget))
            } else {
                continue
            }
            guard !hit.isEmpty else { continue }
            chunks.append((item, hit))
            budget -= hit.count
        }
        guard !chunks.isEmpty else {
            askAnswer = "None of the tagged cards mention this. Nothing was sent."
            return
        }
        let excerpt = chunks.map { "### \($0.item.title)\n\n\($0.excerpt)" }.joined(separator: "\n\n")
        let title = chunks.map(\.item.title).joined(separator: " · ")
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
        if let first = chunks.first {
            askSourceCardID = first.item.id
            askSourceText = first.excerpt
            if first.item.id == selectedLibraryID {
                bindAskSource(answer: askAnswer, question: q, cardID: first.item.id)
            }
        }
        rememberAsk(
            question: q,
            answer: askAnswer,
            openAnswer: "",
            chapter: askChapter,
            fileTitle: title
        )
    }

    private static func taggedExcerpt(from text: String, query: FileSearchQuery, cap: Int) -> String {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map {
            PreviewLine(id: $0.offset, text: String($0.element))
        }
        guard let i = query.hitLineIDs(in: rows).first ?? rows.first(where: { query.matches($0.text) })?.id else {
            return String(text.prefix(cap))
        }
        let start = max(0, i - 2)
        let end = min(rows.count, i + 8)
        return String(rows[start..<end].map(\.text).joined(separator: "\n").prefix(cap))
    }

    func restoreAsk(_ record: AskRecord) {
        askQuestion = record.question
        askAnswer = record.answer
        askOpenAnswer = record.openAnswer
        askError = ""
        if !record.chapter.isEmpty {
            askChapter = record.chapter
        }
        askSourceCardID = selectedLibraryID
        if let line = record.sourceLine {
            askSourceLine = line
            askSourceText = passageAround(line: line, in: previewLines)
        } else {
            bindAskSource(answer: record.answer, question: record.question, cardID: selectedLibraryID)
        }
    }

    private func rememberAsk(
        question: String,
        answer: String,
        openAnswer: String,
        chapter: String,
        fileTitle: String
    ) {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let record = AskRecord(
            question: question,
            answer: answer,
            openAnswer: openAnswer,
            chapter: chapter,
            fileTitle: fileTitle,
            sourceLine: askSourceLine
        )
        askHistory.removeAll {
            $0.question.caseInsensitiveCompare(question) == .orderedSame
                && $0.chapter.caseInsensitiveCompare(chapter) == .orderedSame
                && $0.fileTitle.caseInsensitiveCompare(fileTitle) == .orderedSame
        }
        askHistory.insert(record, at: 0)
        if askHistory.count > 25 {
            askHistory = Array(askHistory.prefix(25))
        }
        saveAskHistory()
    }

    private func loadAskHistory() {
        guard let data = try? Data(contentsOf: askHistoryURL),
              let items = try? JSONDecoder().decode([AskRecord].self, from: data)
        else { return }
        askHistory = Array(items.prefix(25))
    }

    private func saveAskHistory() {
        guard let data = try? JSONEncoder().encode(askHistory) else { return }
        try? data.write(to: askHistoryURL, options: .atomic)
    }

    func clearAsk() {
        askAnswer = ""
        askOpenAnswer = ""
        askError = ""
        askQuestion = ""
        askSourceLine = nil
        askSourceText = ""
        askSourceCardID = nil
        askHitsInReader = []
        askHitIndex = 0
        askHighlightNeedles = []
        askSourceRevealed = false
    }

    func clearAskHistory() {
        askHistory = []
        saveAskHistory()
    }

    var canRevealAskSource: Bool {
        !askHitsInReader.isEmpty || askSourceLine != nil || !askSourceText.isEmpty
    }

    func revealAskSource() {
        if let id = askSourceCardID, id != selectedLibraryID,
           let item = library.first(where: { $0.id == id }) {
            selectLibrary(item)
        }
        if askHitsInReader.isEmpty {
            bindAskSource(answer: askAnswer, question: askQuestion, cardID: askSourceCardID ?? selectedLibraryID)
        }
        if askHitsInReader.isEmpty {
            statusText = L("No matching line in this file.")
            return
        }
        if askSourceRevealed, askHitsInReader.count > 1 {
            nextAskHit()
            return
        }
        askSourceRevealed = true
        jumpAskHit()
    }

    private func jumpAskHit() {
        guard askHitsInReader.indices.contains(askHitIndex) else { return }
        let line = askHitsInReader[askHitIndex]
        askSourceLine = line
        askSourceText = passageAround(line: line, in: previewLines)
        bumpMainScroll(line)
        hunterScrollChar = hunterCharOffset(forLine: line, in: previewLines)
        hunterScrollStamp += 1
    }

    func forageAskHit() {
        guard canRevealAskSource else { return }
        if let id = askSourceCardID, id != selectedLibraryID,
           let item = library.first(where: { $0.id == id }) {
            selectLibrary(item)
        }
        if !hunterOn {
            toggleHunterGatherer()
        }
        let passage = askSourceText.isEmpty
            ? passageAround(line: askSourceLine ?? 0, in: previewLines)
            : askSourceText
        let q = askQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        gatherPassage(passage, question: q)
        if let line = askSourceLine {
            hunterScrollChar = hunterCharOffset(forLine: line, in: previewLines)
            hunterScrollStamp += 1
        }
        revealAskSource()
    }

    private func booleanAskPlan(query: FileSearchQuery, in rows: [PreviewLine]) -> (excerpt: String, hits: [Int]) {
        let span = askChapterLineRange(in: rows)
        let hits = query.hitLineIDs(in: rows, span: span)
        var parts: [String] = []
        var used = 0
        var seen = Set<Int>()
        for id in hits {
            guard seen.insert(id).inserted else { continue }
            let passage = passageAround(line: id, in: rows)
            guard !passage.isEmpty else { continue }
            if used + passage.count > 12_000 { break }
            parts.append(passage)
            used += passage.count
        }
        return (parts.joined(separator: "\n\n"), hits)
    }

    private func bindAskSource(answer: String, question: String, cardID: UUID?, lines: [PreviewLine]? = nil) {
        let rows = lines ?? previewLines
        if let query = FileSearchQuery.parse(question), FileSearchQuery.hasBooleanOperators(question) {
            let plan = booleanAskPlan(query: query, in: rows)
            askSourceCardID = cardID
            askHighlightNeedles = query.highlightTerms
            askHitsInReader = plan.hits
            askHitIndex = 0
            if let first = plan.hits.first {
                askSourceLine = first
                askSourceText = passageAround(line: first, in: rows)
            } else {
                askSourceLine = nil
                askSourceText = ""
            }
            return
        }
        let needles = Self.askNeedles(answer: answer, question: question)
        askSourceCardID = cardID
        askHighlightNeedles = []
        askHitsInReader = []
        askHitIndex = 0
        guard !rows.isEmpty, !needles.isEmpty else {
            askSourceLine = nil
            askSourceText = ""
            return
        }
        let range = askChapterLineRange(in: rows)
        func collect(in span: ClosedRange<Int>) -> [Int] {
            var hits: [Int] = []
            for row in rows where span.contains(row.id) {
                if needles.contains(where: { FileSearchQuery.contains(row.text, $0) }) {
                    hits.append(row.id)
                    if hits.count >= 120 { break }
                }
            }
            return hits
        }
        var hits = collect(in: range)
        if hits.isEmpty {
            if let first = rows.first?.id, let last = rows.last?.id {
                hits = collect(in: first...last)
            }
        }
        let used = needles.filter { needle in
            rows.contains { FileSearchQuery.contains($0.text, needle) }
        }
        askHighlightNeedles = used.isEmpty ? needles : used
        askHitsInReader = hits
        askHitIndex = 0
        if let first = hits.first {
            askSourceLine = first
            askSourceText = passageAround(line: first, in: rows)
        } else {
            askSourceLine = nil
            askSourceText = ""
        }
    }

    private func askChapterLineRange(in rows: [PreviewLine]) -> ClosedRange<Int> {
        let ids = rows.map(\.id)
        guard let first = ids.first, let last = ids.last else { return 0...0 }
        if askChapter == "Entire file" || askChapter.isEmpty { return first...last }
        let heads = documentOutline
        guard let i = heads.lastIndex(where: {
            $0.title.caseInsensitiveCompare(askChapter) == .orderedSame
        }), let start = heads[i].lineIndex else { return first...last }
        let end = heads.dropFirst(i + 1).compactMap(\.lineIndex).first ?? (last + 1)
        return start...max(start, end - 1)
    }

    private func passageAround(line: Int, in rows: [PreviewLine]) -> String {
        guard let i = rows.firstIndex(where: { $0.id == line }) else { return "" }
        var parts: [String] = []
        for j in i..<min(rows.count, i + 6) {
            let t = rows[j].text.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") && j > i { break }
            if t.hasPrefix("<!--") { continue }
            if !t.isEmpty { parts.append(rows[j].text) }
            if parts.joined(separator: "\n").count > 500 { break }
        }
        return parts.joined(separator: "\n")
    }

    private static func askNeedles(answer: String, question: String) -> [String] {
        var out: [String] = []
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("«", "»")]
        for (open, close) in pairs {
            var search = answer.startIndex
            while let a = answer[search...].firstIndex(of: open) {
                let after = answer.index(after: a)
                guard let b = answer[after...].firstIndex(of: close) else { break }
                let quote = String(answer[after..<b]).trimmingCharacters(in: .whitespacesAndNewlines)
                if quote.count >= 4 { out.append(quote) }
                search = answer.index(after: b)
            }
        }
        let stop: Set<String> = [
            "the", "and", "for", "that", "this", "with", "from", "what", "when",
            "where", "which", "about", "does", "into", "have", "been",
        ]
        let words = question.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 3 && !stop.contains($0) }
            .sorted { $0.count > $1.count }
        out.append(contentsOf: words.prefix(4))
        return out
    }

    static func normalizeTag(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasPrefix("#") || s.hasPrefix("＃") {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        s = s.replacingOccurrences(of: " ", with: "-")
        s = s.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        if s.count > 24 { s = String(s.prefix(24)) }
        return s
    }

    var allLibraryTags: [String] {
        Array(Set(library.flatMap(\.tags))).sorted()
    }

    func displayTag(_ slug: String) -> String {
        let bare = Self.normalizeTag(slug)
        return bare.isEmpty ? "#" : "#\(bare)"
    }

    func beginTagEditor(for item: LibraryItem) {
        tagEditorItemID = item.id
        tagDraft = ""
    }

    func toggleLibraryTagFilter(_ slug: String) {
        if libraryTagFilter.contains(slug) {
            libraryTagFilter.remove(slug)
        } else {
            libraryTagFilter.insert(slug)
        }
    }

    func toggleAskScopeTag(_ slug: String) {
        if askScopeTags.contains(slug) {
            askScopeTags.remove(slug)
        } else {
            askScopeTags.insert(slug)
        }
    }

    func applyTag(_ raw: String, to itemID: UUID) {
        let slug = Self.normalizeTag(raw)
        guard !slug.isEmpty, let i = library.firstIndex(where: { $0.id == itemID }) else { return }
        if library[i].tags.contains(slug) {
            library[i].tags.removeAll { $0 == slug }
        } else if library[i].tags.count < 8 {
            library[i].tags.append(slug)
        }
        saveLibrary()
        tagDraft = ""
    }

    func renameLibraryTag(from old: String, to raw: String) {
        let next = Self.normalizeTag(raw)
        guard !old.isEmpty, !next.isEmpty, old != next else { return }
        for i in library.indices {
            library[i].tags = library[i].tags.map { $0 == old ? next : $0 }
            var seen = Set<String>()
            library[i].tags = library[i].tags.filter { seen.insert($0).inserted }
        }
        if libraryTagFilter.remove(old) != nil { libraryTagFilter.insert(next) }
        if askScopeTags.remove(old) != nil { askScopeTags.insert(next) }
        saveLibrary()
        tagRenameFrom = ""
        tagRenameDraft = ""
    }

    func deleteLibraryTag(_ slug: String) {
        for i in library.indices {
            library[i].tags.removeAll { $0 == slug }
        }
        libraryTagFilter.remove(slug)
        askScopeTags.remove(slug)
        saveLibrary()
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
        rememberTranslateLang(translateFrom)
        rememberTranslateLang(translateTo)
    }

    func rememberTranslateLang(_ code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code != TranslateLang.auto.id else { return }
        guard TranslateLang.spoken.contains(where: { $0.id == code }) else { return }
        var next = recentTranslateLangs.filter { $0 != code }
        next.insert(code, at: 0)
        if next.count > 6 { next = Array(next.prefix(6)) }
        recentTranslateLangs = next
        UserDefaults.standard.set(next, forKey: "recentTranslateLangs")
    }

    var recentSpokenLangs: [TranslateLang] {
        var seen = Set<String>()
        var out: [TranslateLang] = []
        var codes = recentTranslateLangs
        if codes.isEmpty {
            codes = [translateTo, translateFrom, "en"].filter { $0 != TranslateLang.auto.id }
        }
        for id in codes {
            guard !seen.contains(id), let lang = TranslateLang.spoken.first(where: { $0.id == id }) else { continue }
            seen.insert(id)
            out.append(lang)
            if out.count == 6 { break }
        }
        return out
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
        if !engineChecked { return }
        if awaitingPairPick { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Ready" else { return }
        if trimmed.hasSuffix("…") || trimmed.hasSuffix("...") { return }
        if toastVisible, toastText == trimmed { return }
        showToast(trimmed)
    }

    func showToast(_ text: String, sticky: Bool = false) {
        toastText = text
        toastVisible = true
        toastGen += 1
        if sticky { return }
        let gen = toastGen
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard gen == toastGen else { return }
            toastVisible = false
        }
    }

    func dismissToast() {
        toastVisible = false
        toastGen += 1
    }

    var canTranslate: Bool { askHasKey || googleHasKey }

    var translateReadyHint: String {
        if translateEngine == "google" {
            return googleHasKey
                ? "This chapter will be sent to Google Translate"
                : "Add a Google Translate key in Settings, or switch Translate to your Ask AI key"
        }
        return askHasKey
            ? "This chapter will be sent to your Ask model"
            : "Add an Ask AI key in Settings, or switch Translate to Google"
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
                if !askHasKey {
                    translateEngine = "google"
                    persistTranslateSettings()
                }
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

    /// SwiftUI List on macOS was the old ceiling (~2,200 rows). RAM is not.
    /// M1 unified memory holds this many times over; TextKit can layout tens of MB.
    /// 2 MB / 40,000 lines covers a typical aircraft manual (NAT Doc is 0.45 MB / 8,112 lines).
    nonisolated static let readerMaxBytes = 2_000_000
    nonisolated static let readerMaxChars = 2_000_000
    nonisolated static let readerMaxLines = 40_000
    nonisolated static let readerLineCharCap = 1_800
    nonisolated static let readerCapNote = "The reader shows the first 40,000 lines (about 2 MB). Open the file in Finder for the rest."

    /// Sonnet-class: ~$3/1M input + $15/1M output. Translation ≈ same tokens out as in.
    var translateEntireFileIsCostly: Bool {
        estimatedTranslateUSD() > 3
    }

    private func estimatedTranslateUSD() -> Double {
        let bytes: Int64
        if let item = library.first(where: { $0.id == selectedLibraryID }), item.byteCount > 0 {
            bytes = item.byteCount
        } else {
            bytes = Int64(previewMarkdown.utf8.count)
        }
        let tokens = Double(max(bytes, 0)) / 4.0
        let input = tokens * 3.0 / 1_000_000
        let output = tokens * 15.0 / 1_000_000
        return input + output
    }

    private func chapterHeadingForTranslate() -> String {
        let picked = askChapter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !picked.isEmpty, picked != "Entire file" { return picked }
        if let heading = visibleHeading[.main], !heading.isEmpty { return heading }
        if let heading = visibleHeading[.translate], !heading.isEmpty { return heading }
        return documentOutline.first?.title ?? picked
    }

    func requestTranslate(entireFile: Bool) {
        if entireFile, translateEntireFileIsCostly {
            showTranslateCostWarning = true
            return
        }
        Task { await runTranslate(entireFile: entireFile) }
    }

    func confirmCostlyTranslate() {
        showTranslateCostWarning = false
        Task { await runTranslate(entireFile: true) }
    }

    func runTranslate(entireFile: Bool) async {
        guard let item = library.first(where: { $0.id == selectedLibraryID }) else {
            statusText = "Open a file in Library first."
            return
        }
        if translateEngine == "google", !googleHasKey {
            statusText = "Add a Google Translate key in Settings, or switch Translate to your Ask AI key."
            return
        }
        if translateEngine != "google", !askHasKey {
            statusText = "Add an Ask AI key in Settings, or switch Translate to Google."
            return
        }
        if translateTo == "auto" || translateTo.isEmpty {
            statusText = "Pick a language to translate to."
            return
        }
        rememberTranslateLang(translateFrom)
        rememberTranslateLang(translateTo)
        translateBusy = true
        statusText = entireFile
            ? "Translating the file…"
            : "Translating this chapter…"
        defer { translateBusy = false }
        let path = item.markdownPath
        let disk = await Task.detached(priority: .utility) {
            AppModel.readMarkdownPrefix(path: path, maxBytes: 280_000)?.text
        }.value ?? previewMarkdown
        let heading = entireFile ? "Entire file" : chapterHeadingForTranslate()
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
            let applied = await applyOriginalOutline(
                to: result,
                item: item,
                excerpt: excerpt,
                entireFile: entireFile,
                ask: askSettings
            )
            translateMarkdown = applied.text
            let pack = Self.packFromText(
                applied.text,
                base: previewBaseURL ?? URL(fileURLWithPath: item.markdownPath).deletingLastPathComponent(),
                scanHeadings: false
            )
            translateLines = pack.lines
            translateHeadings = relocateOutline(applied.bookmarks, in: pack.lines)
            if sideBySide {
                restoreOriginalPreview()
                refreshLinkedTitles()
                linkScroll = true
                statusText = entireFile
                    ? "Side by side — original and translation scroll together"
                    : "Side by side — this chapter is on the right"
            } else {
                refreshLinkedTitles()
                applyDisplayLines(result)
                statusText = "Translation is in the reader — Save a copy when you want it on disk"
            }
            if translateSaveMode == "copy" {
                saveTranslationCopy()
            } else {
                pulseSaveCopy = true
            }
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func outlineForTranslate(item: LibraryItem, entireFile: Bool, excerpt: String) -> [ManualBookmark] {
        let full = !item.bookmarks.isEmpty ? item.bookmarks : previewHeadings
        guard !full.isEmpty else { return [] }
        if entireFile { return full }
        let heading = chapterHeadingForTranslate()
        if let start = full.firstIndex(where: { $0.title.caseInsensitiveCompare(heading) == .orderedSame }) {
            let startLevel = full[start].level
            var slice = [full[start]]
            var i = start + 1
            while i < full.count, full[i].level > startLevel {
                slice.append(full[i])
                i += 1
            }
            return slice
        }
        return full.filter { excerpt.localizedCaseInsensitiveContains($0.title) }
    }

    private func applyOriginalOutline(
        to text: String,
        item: LibraryItem,
        excerpt: String,
        entireFile: Bool,
        ask: AskService.Settings
    ) async -> (text: String, bookmarks: [ManualBookmark]) {
        let source = outlineForTranslate(item: item, entireFile: entireFile, excerpt: excerpt)
        guard !source.isEmpty else {
            return (text, Self.headings(from: Self.readerLines(from: text)))
        }
        let translatedTitles: [String]
        do {
            translatedTitles = try await TranslateService.translateTitles(
                source.map(\.title),
                from: translateFrom,
                to: translateTo,
                engine: translateEngine,
                ask: ask,
                googleKey: TranslateSecrets.load()
            )
        } catch {
            translatedTitles = source.map(\.title)
        }
        var titled: [ManualBookmark] = []
        titled.reserveCapacity(source.count)
        for (i, mark) in source.enumerated() {
            var copy = mark
            copy.id = UUID()
            let next = i < translatedTitles.count
                ? translatedTitles[i].trimmingCharacters(in: .whitespacesAndNewlines)
                : mark.title
            copy.title = next.isEmpty ? mark.title : next
            copy.lineIndex = nil
            titled.append(copy)
        }
        return PdfSidecar.applyTranslatedOutline(titled, to: text)
    }

    private func relocateOutline(_ marks: [ManualBookmark], in lines: [PreviewLine]) -> [ManualBookmark] {
        guard !marks.isEmpty else { return Self.headings(from: lines) }
        var out = marks
        var claimed = Set<Int>()
        for i in out.indices {
            if let idx = headingLine(out[i].title, in: lines) {
                out[i].lineIndex = idx
                claimed.insert(idx)
            } else {
                out[i].lineIndex = nil
            }
        }
        let extras = Self.headings(from: lines)
        var ei = 0
        for i in out.indices where out[i].lineIndex == nil {
            while ei < extras.count, claimed.contains(extras[ei].lineIndex ?? -1) { ei += 1 }
            guard ei < extras.count else { break }
            out[i].lineIndex = extras[ei].lineIndex
            if let idx = extras[ei].lineIndex { claimed.insert(idx) }
            ei += 1
        }
        return out
    }

    private func outlineForOpenedTranslation(
        right: LibraryItem,
        left: LibraryItem,
        lines: [PreviewLine],
        scanned: [ManualBookmark]
    ) -> [ManualBookmark] {
        if !right.bookmarks.isEmpty {
            return relocateOutline(right.bookmarks, in: lines)
        }
        if !left.bookmarks.isEmpty {
            return relocateOutline(left.bookmarks, in: lines)
        }
        return scanned
    }

    var isLandscapeWide: Bool {
        windowSize.width > 40 && windowSize.height > 40
            && windowSize.width > windowSize.height
            && windowSize.width >= 1100
    }

    func noteWindowSize(_ size: CGSize) {
        guard windowSize != size else { return }
        windowSize = size
        if sideBySide, !isLandscapeWide {
            let originalPath = library.first(where: { $0.id == selectedLibraryID })?.markdownPath ?? ""
            let showTranslation = liveEditPath.isEmpty || liveEditPath != originalPath
            leaveSideBySide(restoreTranslation: showTranslation)
            if !showTranslation {
                restoreOriginalPreview()
            }
            statusText = L("SIDE BY SIDE needs a wide landscape window. Drag it wider, turn the text slider down (A … A), or hide Library.")
        }
    }

    var sideBySidePairReady: Bool { pairFromSelection() != nil }

    private var landscapeTooNarrowMessage: String {
        L("SIDE BY SIDE needs a wide landscape window. Drag it wider, turn the text slider down (A … A), or hide Library.")
    }

    func toggleSideBySide() {
        if awaitingPairPick {
            cancelPairPick()
            return
        }
        if sideBySide {
            leaveSideBySide(restoreTranslation: translateMarkdown != nil)
            return
        }
        guard isLandscapeWide else {
            showToast(landscapeTooNarrowMessage)
            statusText = landscapeTooNarrowMessage
            return
        }
        if let pair = pairFromSelection() {
            openPairSideBySide(left: pair.left, right: pair.right)
            return
        }
        if translateMarkdown != nil, !translateLines.isEmpty {
            restoreOriginalPreview()
            beginSideBySide(status: "Side by side — chapters and scroll stay linked")
            return
        }
        if let pair = stackedPairForCurrent() {
            openPairSideBySide(left: pair.left, right: pair.right)
            return
        }
        guard let lead = library.first(where: { $0.id == selectedLibraryID }) else {
            startPairPick(lead: nil, message: L("Click the matching file."))
            return
        }
        let kids = stackedChildren(of: lead)
        if kids.count > 1 {
            startPairPick(lead: lead, message: "\(L("Click the language to open beside")) \(lead.title).")
            return
        }
        startPairPick(lead: lead, message: L("Click the matching file."))
    }

    /// Master + open child, one stacked translation, or two recent cards that share an origin.
    func stackedPairForCurrent() -> (left: LibraryItem, right: LibraryItem)? {
        guard let current = library.first(where: { $0.id == selectedLibraryID }) else {
            return recentShareOriginPair()
        }
        if let group = libraryGroups(from: library).first(where: { $0.items.contains(where: { $0.id == current.id }) }) {
            if current.id != group.master.id {
                return orderPair(group.master, current)
            }
            if group.children.count == 1, let child = group.children.first {
                return orderPair(group.master, child)
            }
            return nil
        }
        return recentShareOriginPair()
    }

    private func stackedChildren(of item: LibraryItem) -> [LibraryItem] {
        guard let group = libraryGroups(from: library).first(where: { $0.items.contains(where: { $0.id == item.id }) }) else {
            return []
        }
        return group.children
    }

    private func recentShareOriginPair() -> (left: LibraryItem, right: LibraryItem)? {
        if let current = library.first(where: { $0.id == selectedLibraryID }) {
            let mates = library
                .filter { $0.id != current.id && shareOrigin(current, $0) }
                .sorted { $0.openedAt > $1.openedAt }
            if let mate = mates.first {
                return orderPair(current, mate)
            }
            return nil
        }
        let recent = library.sorted { $0.openedAt > $1.openedAt }
        guard recent.count >= 2 else { return nil }
        for i in 0..<recent.count {
            for j in (i + 1)..<recent.count where shareOrigin(recent[i], recent[j]) {
                return orderPair(recent[i], recent[j])
            }
        }
        return nil
    }

    func startPairPick(lead: LibraryItem?, message: String) {
        pairPickLeadID = lead?.id
        awaitingPairPick = true
        pairPickNotice = nil
        pairMismatchNotice = nil
        showToast(message, sticky: true)
        statusText = message
    }

    func cancelPairPick() {
        awaitingPairPick = false
        pairPickLeadID = nil
        pairPickNotice = nil
        pairMismatchNotice = nil
        dismissToast()
        statusText = L("SIDE BY SIDE cancelled")
    }

    func isPairPickCandidate(_ item: LibraryItem) -> Bool {
        guard awaitingPairPick else { return false }
        guard let lead = library.first(where: { $0.id == pairPickLeadID })
            ?? library.first(where: { $0.id == selectedLibraryID })
        else { return true }
        if item.id == lead.id { return false }
        return shareOrigin(lead, item)
    }

    func isPairPickLead(_ item: LibraryItem) -> Bool {
        item.id == pairPickLeadID || (pairPickLeadID == nil && item.id == selectedLibraryID)
    }

    var linkingScroll: Bool { sideBySide || forageLinkActive }

    func pressSyncScroll() {
        if hunterOn {
            statusText = L("Turn Hunter-Gatherer off to SyncScroll FORAGE with the source.")
            return
        }
        if forageLinkActive {
            toggleLinkScroll()
            return
        }
        if harvestOpen, !sideBySide {
            if forageHasMultipleSources() {
                statusText = L("SyncScroll needs clips from one file.")
                return
            }
            if let source = soleForageSourcePath() {
                forageLinkUserOff = false
                if !Self.sameFilePath(source, currentReaderPath),
                   let item = library.first(where: { Self.sameFilePath($0.markdownPath, source) }) {
                    selectLibrary(item, force: true)
                    statusText = L("Opening the source for SyncScroll")
                    return
                }
                updateForageSync(autoOn: true)
                return
            }
        }
        if sideBySide {
            toggleLinkScroll()
            return
        }
        showToast(L("Open a pair with SIDE BY SIDE first."))
        statusText = L("Open a pair with SIDE BY SIDE first.")
    }

    func toggleLinkScroll() {
        if linkScroll {
            linkScroll = false
            if forageLinkActive { forageLinkUserOff = true }
            statusText = "Each file scrolls on its own"
            return
        }
        forageLinkUserOff = false
        resumeLinkScroll()
    }

    private func resumeLinkScroll() {
        linkScroll = true
        linkMaster = .main
        linkedHeading = ""
        lastSlaveFollowAt = .distantPast
        lastFollowLine = [:]
        linkScrollIgnoreUntil = .distantPast
        linkScrollIgnorePane = nil
        ignoreVisibleUntil = .distantPast
        refreshLinkedTitles()
        statusText = "Scrolling both files together"
        let heading = visibleHeading[.main] ?? ""
        let line = visibleLine[.main]
            ?? headingLine(heading, in: previewLines)
            ?? documentOutline.first(where: {
                $0.title.caseInsensitiveCompare(heading) == .orderedSame
            })?.lineIndex
        let heads = markdownHeadings(for: .main)
        let title: String = {
            if let line, let i = headingIndex(at: line, title: heading, in: heads) {
                return heads[i].title
            }
            if !heading.isEmpty { return heading }
            return heads.first?.title ?? ""
        }()
        let followLine = line ?? heads.first?.lineIndex
        if !title.isEmpty || followLine != nil {
            linkedHeading = title
            followSlave(heading: title, line: followLine, master: .main)
        }
    }

    func ignoreHarvestLead(for seconds: TimeInterval) {
        linkScrollIgnorePane = .harvest
        linkScrollIgnoreUntil = Date().addingTimeInterval(seconds)
    }

    func clearHarvestHeading() {
        visibleHeading[.harvest] = nil
    }

    func adoptLinkMaster(_ pane: LinkPane) {
        if forageLinkActive {
            guard pane == .main || pane == .harvest else { return }
            linkMaster = pane
            return
        }
        guard sideBySide, pane != .harvest else { return }
        linkMaster = pane
    }

    func activeHeading(for pane: LinkPane) -> String {
        let seen = visibleHeading[pane] ?? ""
        if !seen.isEmpty { return seen }
        return linkedHeading
    }

    private func beginSideBySide(status: String) {
        stopForageLink()
        linkScroll = true
        linkMaster = .main
        linkedHeading = ""
        visibleHeading = [:]
        visibleLine = [:]
        lastSlaveFollowAt = .distantPast
        lastFollowLine = [:]
        linkScrollIgnoreUntil = .distantPast
        linkScrollIgnorePane = nil
        awaitingPairPick = false
        pairPickLeadID = nil
        sideBySideOpening = false
        pairPickNotice = nil
        pairMismatchNotice = nil
        dismissToast()
        refreshLinkedTitles()
        sideBySide = true
        statusText = status
    }

    private func pairFromSelection() -> (left: LibraryItem, right: LibraryItem)? {
        let items = library.filter { selectedLibraryIDs.contains($0.id) }
        guard items.count == 2 else { return nil }
        let a = items[0]
        let b = items[1]
        guard shareOrigin(a, b) else { return nil }
        return orderPair(a, b)
    }

    func shareOrigin(_ a: LibraryItem, _ b: LibraryItem) -> Bool {
        if !a.sourcePath.isEmpty, a.sourcePath == b.sourcePath { return true }
        let fa = URL(fileURLWithPath: a.markdownPath).deletingLastPathComponent().standardizedFileURL.path
        let fb = URL(fileURLWithPath: b.markdownPath).deletingLastPathComponent().standardizedFileURL.path
        guard fa == fb else { return false }
        let sa = Self.pairingStem(forMarkdownPath: a.markdownPath)
        let sb = Self.pairingStem(forMarkdownPath: b.markdownPath)
        return !sa.isEmpty && sa.caseInsensitiveCompare(sb) == .orderedSame
    }

    private func orderPair(_ a: LibraryItem, _ b: LibraryItem) -> (left: LibraryItem, right: LibraryItem) {
        let base = Self.pairingStem(forMarkdownPath: a.markdownPath)
        let sa = URL(fileURLWithPath: a.markdownPath).deletingPathExtension().lastPathComponent
        let sb = URL(fileURLWithPath: b.markdownPath).deletingPathExtension().lastPathComponent
        if sa.caseInsensitiveCompare(base) == .orderedSame { return (a, b) }
        if sb.caseInsensitiveCompare(base) == .orderedSame { return (b, a) }
        return sa.count <= sb.count ? (a, b) : (b, a)
    }

    nonisolated static func pairingStem(forMarkdownPath path: String) -> String {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let ids = TranslateLang.spoken.map(\.id).sorted { $0.count > $1.count }
        let lower = stem.lowercased()
        for id in ids {
            let suffix = ".\(id.lowercased())"
            if lower.hasSuffix(suffix) {
                return String(stem.dropLast(suffix.count))
            }
            let marked = ".\(id.lowercased())-"
            if let range = lower.range(of: marked, options: .backwards) {
                let after = lower[range.upperBound...]
                if !after.isEmpty, after.allSatisfy(\.isNumber) {
                    let idx = stem.index(stem.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))
                    return String(stem[..<idx])
                }
            }
        }
        return stem
    }

    private func openPairSideBySide(left: LibraryItem, right: LibraryItem) {
        awaitingPairPick = false
        pairPickLeadID = nil
        sideBySideOpening = true
        selectedLibraryID = left.id
        selectedLibraryIDs = [left.id, right.id]
        liveEditPath = ""
        askChapter = "Entire file"
        scrollToLine = nil
        translateScrollLine = nil
        linkedHeading = ""
        previewGen += 1
        let gen = previewGen
        previewMarkdown = "Loading…"
        previewLines = [PreviewLine(id: 0, text: "Loading…")]
        let leftPath = left.markdownPath
        let rightPath = right.markdownPath
        Task.detached {
            let leftPack = AppModel.buildPreview(path: leftPath, scanHeadings: true)
            let rightPack = AppModel.buildPreview(path: rightPath, scanHeadings: true)
            await MainActor.run {
                guard gen == self.previewGen else { return }
                self.previewMarkdown = leftPack.text
                self.previewLines = leftPack.lines
                self.previewHeadings = leftPack.headings
                self.previewBaseURL = leftPack.base
                self.previewBackup = (leftPack.lines, leftPack.headings)
                self.previewTruncated = leftPack.truncated
                self.hunterTextMemo.removeAll(keepingCapacity: true)
                self.translateMarkdown = rightPack.text
                self.translateLines = rightPack.lines
                self.translateHeadings = self.outlineForOpenedTranslation(right: right, left: left, lines: rightPack.lines, scanned: rightPack.headings)
                self.beginSideBySide(status: "Side by side — \(left.title) and \(right.title)")
            }
        }
    }

    private func leaveSideBySide(restoreTranslation: Bool) {
        sideBySide = false
        linkedHeading = ""
        visibleHeading = [:]
        visibleLine = [:]
        lastSlaveFollowAt = .distantPast
        lastFollowLine = [:]
        linkScrollIgnoreUntil = .distantPast
        linkScrollIgnorePane = nil
        translateScrollLine = nil
        if restoreTranslation, let text = translateMarkdown {
            applyDisplayLines(text)
        }
        updateForageSync(autoOn: !forageLinkUserOff)
    }

    func restoreOriginalPreview() {
        if let backup = previewBackup {
            previewLines = backup.lines
            previewHeadings = backup.headings
        }
    }

    func refreshLinkedTitles() {
        if forageLinkActive {
            refreshForageLinkedTitles()
            return
        }
        let main = markdownHeadings(for: .main).map {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let other = markdownHeadings(for: .translate).map {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        linkedTitles = pairedTitles(main: main, other: other)
    }

    private func refreshForageLinkedTitles() {
        let main = markdownHeadings(for: .main).map {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let other = harvestHeadings.map {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        linkedTitles = pairedTitles(main: main, other: other)
    }

    private func pairedTitles(main: [String], other: [String]) -> [(main: String, translate: String)] {
        var pairs: [(main: String, translate: String)] = []
        let n = min(main.count, other.count)
        var usedMain = Set<String>()
        var usedOther = Set<String>()
        for i in 0..<n {
            pairs.append((main[i], other[i]))
            usedMain.insert(main[i].lowercased())
            usedOther.insert(other[i].lowercased())
        }
        for title in main {
            let key = title.lowercased()
            guard !usedMain.contains(key) else { continue }
            if let match = other.first(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) {
                pairs.append((title, match))
                usedMain.insert(key)
                usedOther.insert(match.lowercased())
            }
        }
        return pairs
    }

    private func pairedTranslate(for title: String) -> String? {
        linkedTitles.first { $0.main.caseInsensitiveCompare(title) == .orderedSame }?.translate
    }

    private func pairedMain(for title: String) -> String? {
        linkedTitles.first { $0.translate.caseInsensitiveCompare(title) == .orderedSame }?.main
    }

    func headingLine(_ title: String, in lines: [PreviewLine]) -> Int? {
        for row in lines {
            let raw = row.text.hasPrefix(TranslateService.marker)
                ? String(row.text.dropFirst(TranslateService.marker.count))
                : row.text
            guard let heading = PdfSidecar.headingText(raw) else { continue }
            if heading.caseInsensitiveCompare(title) == .orderedSame {
                return row.id
            }
        }
        return nil
    }

    func noteVisibleHeading(_ title: String, from pane: LinkPane) {
        noteVisibleLine(nil, headingTitle: title, from: pane)
    }

    func noteVisibleLine(_ line: Int?, headingTitle: String, from pane: LinkPane) {
        if Date() < ignoreVisibleUntil { return }
        if pane == .harvest, !forageLinkActive { return }
        let outline: [ManualBookmark] = {
            switch pane {
            case .translate: return translateHeadings
            case .harvest: return harvestHeadings
            case .main: return documentOutline
            }
        }()
        let fromLine: String = {
            guard let line else { return "" }
            return outline.last { ($0.lineIndex ?? Int.max) <= line }?.title ?? ""
        }()
        let trimmed = (fromLine.isEmpty ? headingTitle : fromLine)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let line { visibleLine[pane] = line }
        var headingChanged = false
        if !trimmed.isEmpty {
            if let seen = visibleHeading[pane], seen.caseInsensitiveCompare(trimmed) == .orderedSame {
                headingChanged = false
            } else {
                visibleHeading[pane] = trimmed
                headingChanged = true
            }
        }
        guard linkingScroll, linkScroll else { return }
        guard pane == linkMaster else { return }
        if let ignore = linkScrollIgnorePane, pane == ignore, Date() < linkScrollIgnoreUntil {
            return
        }
        if trimmed.isEmpty, line == nil { return }
        if headingChanged {
            linkedHeading = trimmed
        }
        if let line, lastFollowLine[pane] == line, !headingChanged { return }
        let now = Date()
        if !headingChanged, now.timeIntervalSince(lastSlaveFollowAt) < 0.08 { return }
        lastSlaveFollowAt = now
        if let line { lastFollowLine[pane] = line }
        let title = trimmed.isEmpty ? linkedHeading : trimmed
        followSlave(heading: title, line: line, master: pane)
    }

    /// Same titles and the same count. Any extra, missing, or renamed bookmark skips this tier.
    private func bookmarkOutlinesAlign(_ a: [ManualBookmark], _ b: [ManualBookmark]) -> Bool {
        let left = a.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let right = b.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !left.isEmpty, left.count == right.count else { return false }
        let rightKeys = Set(right.map { $0.lowercased() })
        return left.allSatisfy { rightKeys.contains($0.lowercased()) }
    }

    private func markdownHeadings(for pane: LinkPane) -> [ManualBookmark] {
        switch pane {
        case .main:
            if previewHeadings.isEmpty {
                previewHeadings = Self.headings(from: previewLines)
            }
            return previewHeadings
        case .translate:
            if translateHeadings.isEmpty {
                translateHeadings = Self.headings(from: translateLines)
            }
            return translateHeadings
        case .harvest:
            return harvestHeadings
        }
    }

    private func headingIndex(at line: Int?, title: String, in headings: [ManualBookmark]) -> Int? {
        if let line, let i = headings.lastIndex(where: { ($0.lineIndex ?? Int.max) <= line }) {
            return i
        }
        return headings.firstIndex { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    private func counterpartHeading(
        index: Int,
        master: [ManualBookmark],
        slave: [ManualBookmark]
    ) -> ManualBookmark? {
        guard master.indices.contains(index) else {
            return slave.indices.contains(index) ? slave[index] : nil
        }
        let level = master[index].level
        let ordinal = master.prefix(index + 1).filter { $0.level == level }.count - 1
        let sameLevel = slave.filter { $0.level == level }
        if sameLevel.indices.contains(ordinal) { return sameLevel[ordinal] }
        return slave.indices.contains(index) ? slave[index] : nil
    }

    private func pageComment(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("<!-- page "), t.hasSuffix("-->") else { return nil }
        let inner = t
            .dropFirst("<!-- page ".count)
            .dropLast(3)
            .trimmingCharacters(in: .whitespaces)
        return Int(inner).flatMap { $0 > 0 ? $0 : nil }
    }

    private func pageAtOrAbove(_ line: Int, in lines: [PreviewLine]) -> Int? {
        var found: Int?
        for row in lines where row.id <= line {
            if let page = pageComment(row.text) { found = page }
        }
        return found
    }

    private func lineForPage(_ page: Int, in lines: [PreviewLine]) -> Int? {
        lines.first { pageComment($0.text) == page }?.id
    }

    private func counterpartTitle(_ title: String, master: LinkPane) -> String? {
        if master == .main {
            if let pair = pairedTranslate(for: title) { return pair }
        } else {
            if let pair = pairedMain(for: title) { return pair }
        }
        let slave: LinkPane = {
            if forageLinkActive { return master == .main ? .harvest : .main }
            return master == .main ? .translate : .main
        }()
        let masterHeads = markdownHeadings(for: master)
        let slaveHeads = markdownHeadings(for: slave)
        if let i = masterHeads.firstIndex(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }),
           let pair = counterpartHeading(index: i, master: masterHeads, slave: slaveHeads) {
            return pair.title
        }
        return nil
    }

    private func sectionBounds(at line: Int, headings: [ManualBookmark], lineCount: Int) -> (start: Int, end: Int)? {
        guard let i = headings.lastIndex(where: { ($0.lineIndex ?? Int.max) <= line }),
              let start = headings[i].lineIndex
        else { return nil }
        let next = headings.dropFirst(i + 1).compactMap(\.lineIndex).first ?? lineCount
        return (start, max(next, start + 1))
    }

    private func pageBounds(page: Int, in lines: [PreviewLine], until end: Int) -> (start: Int, end: Int)? {
        guard let start = lineForPage(page, in: lines), start < end else { return nil }
        let next = lines.first { row in
            row.id > start && row.id < end && pageComment(row.text) != nil
        }?.id ?? end
        return (start, max(next, start + 1))
    }

    private func scrollFraction(line: Int, start: Int, end: Int) -> Double {
        let span = max(1, end - start)
        return min(1, max(0, Double(line - start) / Double(span)))
    }

    private func lineAtFraction(_ fraction: Double, start: Int, end: Int) -> Int {
        let span = max(0, end - start)
        return start + Int((Double(span) * fraction).rounded(.down))
    }

    private func followSlave(heading: String, line: Int? = nil, master: LinkPane) {
        let forage = forageLinkActive
        let slavePane: LinkPane = {
            if forage { return master == .main ? .harvest : .main }
            return master == .main ? .translate : .main
        }()
        let masterLines = lines(for: master)
        let slaveLines = lines(for: slavePane)
        let masterMarks = bookmarks(for: master)
        let slaveMarks = bookmarks(for: slavePane)
        let masterHeads = markdownHeadings(for: master)
        let slaveHeads = markdownHeadings(for: slavePane)

        func bump(_ idx: Int) {
            switch slavePane {
            case .main: bumpMainScroll(idx)
            case .translate: bumpTranslateScroll(idx)
            case .harvest: bumpHarvestScroll(idx)
            }
        }

        func mapped(_ slaveStart: Int, masterHeads heads: [ManualBookmark], slaveHeads pairHeads: [ManualBookmark]) {
            guard let line else {
                bump(slaveStart)
                return
            }
            let masterCount = max(masterLines.last.map { $0.id + 1 } ?? 0, line + 1)
            let slaveCount = max(slaveLines.last.map { $0.id + 1 } ?? 0, slaveStart + 1)
            var masterStart = 0
            var masterEnd = masterCount
            var destStart = slaveStart
            var destEnd = slaveCount
            if let bounds = sectionBounds(at: line, headings: heads, lineCount: masterCount) {
                masterStart = bounds.start
                masterEnd = bounds.end
            }
            if let destBounds = sectionBounds(at: slaveStart, headings: pairHeads, lineCount: slaveCount) {
                destStart = destBounds.start
                destEnd = destBounds.end
            } else {
                destStart = slaveStart
                destEnd = slaveCount
            }
            if let page = pageAtOrAbove(line, in: masterLines),
               let masterPage = pageBounds(page: page, in: masterLines, until: masterEnd),
               let slavePage = pageBounds(page: page, in: slaveLines, until: destEnd) {
                masterStart = masterPage.start
                masterEnd = masterPage.end
                destStart = slavePage.start
                destEnd = slavePage.end
            }
            let fraction = scrollFraction(line: line, start: masterStart, end: masterEnd)
            bump(lineAtFraction(fraction, start: destStart, end: destEnd))
        }

        linkScrollIgnorePane = slavePane
        linkScrollIgnoreUntil = Date().addingTimeInterval(0.7)

        if bookmarkOutlinesAlign(masterMarks, slaveMarks) {
            if let match = slaveMarks.first(where: { $0.title.caseInsensitiveCompare(heading) == .orderedSame }),
               let idx = headingLine(match.title, in: slaveLines) ?? match.lineIndex {
                mapped(idx, masterHeads: masterMarks, slaveHeads: slaveMarks)
                return
            }
            if let i = masterMarks.firstIndex(where: { $0.title.caseInsensitiveCompare(heading) == .orderedSame }),
               slaveMarks.indices.contains(i),
               let idx = headingLine(slaveMarks[i].title, in: slaveLines) ?? slaveMarks[i].lineIndex {
                mapped(idx, masterHeads: masterMarks, slaveHeads: slaveMarks)
                return
            }
        }

        if let idx = headingLine(heading, in: slaveLines) {
            mapped(idx, masterHeads: masterHeads, slaveHeads: slaveHeads)
            return
        }
        if let want = counterpartTitle(heading, master: master),
           let idx = headingLine(want, in: slaveLines) {
            mapped(idx, masterHeads: masterHeads, slaveHeads: slaveHeads)
            return
        }
        if let i = headingIndex(at: line, title: heading, in: masterHeads),
           let pair = counterpartHeading(index: i, master: masterHeads, slave: slaveHeads),
           let idx = headingLine(pair.title, in: slaveLines) ?? pair.lineIndex {
            mapped(idx, masterHeads: masterHeads, slaveHeads: slaveHeads)
            return
        }

        if let line,
           let page = pageAtOrAbove(line, in: masterLines),
           let idx = lineForPage(page, in: slaveLines) {
            mapped(idx, masterHeads: masterHeads, slaveHeads: slaveHeads)
        }
    }

    private func lines(for pane: LinkPane) -> [PreviewLine] {
        switch pane {
        case .main: return previewLines
        case .translate: return translateLines
        case .harvest: return harvestLines
        }
    }

    private func bookmarks(for pane: LinkPane) -> [ManualBookmark] {
        switch pane {
        case .main: return documentOutline
        case .translate: return translateHeadings
        case .harvest: return harvestHeadings
        }
    }

    private func bumpMainScroll(_ idx: Int) {
        ignoreVisibleUntil = Date().addingTimeInterval(0.85)
        if scrollToLine == idx { scrollToLine = nil }
        Task { @MainActor in self.scrollToLine = idx }
    }

    private func bumpTranslateScroll(_ idx: Int) {
        if translateScrollLine == idx { translateScrollLine = nil }
        Task { @MainActor in self.translateScrollLine = idx }
    }

    private func bumpHarvestScroll(_ idx: Int) {
        if harvestScrollLine == idx { harvestScrollLine = nil }
        Task { @MainActor in self.harvestScrollLine = idx }
    }

    func clearTranslation() {
        pulseSaveCopy = false
        sideBySide = false
        translateLines = []
        translateHeadings = []
        translateScrollLine = nil
        linkedHeading = ""
        translateMarkdown = nil
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
                self.previewTruncated = pack.truncated
                self.setStatus(self.translateReadyHint, important: true)
            }
        }
    }

    @discardableResult
    func saveTranslationCopy() -> URL? {
        guard let text = translateMarkdown,
              let item = library.first(where: { $0.id == selectedLibraryID })
        else { return nil }
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
            statusText = "Could not save the translation copy"
            return nil
        }
        rememberDiskFingerprint(path: dest.path, text: text)
        let source = item.sourcePath.isEmpty
            ? original
            : URL(fileURLWithPath: item.sourcePath)
        let marks = translateHeadings.isEmpty ? item.bookmarks : translateHeadings
        PdfSidecar.writeSidecar(marks, nextTo: dest)
        _ = insertLibraryItem(
            source: source,
            markdown: dest,
            bookmarks: marks,
            title: "\(item.title) · \(TranslateLang.label(for: lang))"
        )
        liveEditPath = dest.path
        startWatching()
        pulseSaveCopy = false
        statusText = "Saved a copy — the original Markdown is unchanged"
        return dest
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
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        let ready = allowed.filter { ConvertibleKind.isReadyMarkdown($0) }
        let rest = allowed.filter { !ConvertibleKind.isReadyMarkdown($0) }
        if !rest.isEmpty { selectedTool = .convert }
        Task {
            if !ready.isEmpty {
                await importReadyMarkdown(ready, reveal: true)
            }
            if !rest.isEmpty {
                // Classify scans off the first frame — PDFKit here used to crash launch-by-drop.
                await classifyAndEnqueue(rest)
            }
        }
    }

    /// Copy or keep a ready .md in the yourMark folder and put a library card on it.
    private func importReadyMarkdown(_ urls: [URL], reveal: Bool) async {
        quietWatch(8)
        var last: LibraryItem?
        var added = 0
        for url in urls {
            guard let placed = placeReadyMarkdown(url) else { continue }
            if let existing = library.first(where: { Self.sameFilePath($0.markdownPath, placed.path) }) {
                last = existing
                continue
            }
            let bookmarks = await Task.detached(priority: .utility) {
                PdfSidecar.readSidecar(nextTo: placed)
            }.value
            last = insertLibraryItem(
                source: placed,
                markdown: placed,
                bookmarks: bookmarks
            )
            added += 1
        }
        if added == 0, last == nil {
            statusText = "Could not add that Markdown"
            return
        }
        statusText = added == 0
            ? "Already in the library"
            : added == 1
                ? "Added \(last?.title ?? "Markdown") to the library"
                : "Added \(added) Markdown files to the library"
        if reveal, let last {
            selectLibrary(last)
        }
    }

    /// Ready Markdown lives in the chosen folder as itself — no convert little-folder.
    private func placeReadyMarkdown(_ url: URL) -> URL? {
        _ = url.startAccessingSecurityScopedResource()
        let src = url.standardizedFileURL
        guard FileManager.default.isReadableFile(atPath: src.path) else { return nil }
        let home = forageHome.standardizedFileURL
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let homePath = home.path
        if src.path == homePath || src.path.hasPrefix(homePath + "/") {
            return src
        }
        var dest = home.appendingPathComponent(src.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            if Self.sameFilePath(dest.path, src.path) { return dest }
            dest = uniqueInboxName(home: home, preferred: src.lastPathComponent)
        }
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            return dest
        } catch {
            statusText = "Could not copy \(src.lastPathComponent) into \(home.lastPathComponent)"
            return nil
        }
    }

    private func uniqueInboxName(home: URL, preferred: String) -> URL {
        let stem = URL(fileURLWithPath: preferred).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: preferred).pathExtension
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            let dest = home.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: dest.path) { return dest }
            n += 1
        }
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
        if !rest.isEmpty { await enqueue(rest, scans: []) }

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
            await enqueue(scanURLs, scans: scanSet)
        }
        await convertQueued()
    }

    func acceptDoclingInstall() async {
        let waiting = pendingGraphics
        pendingGraphics = []
        showDoclingPrompt = false
        await enqueue(waiting)
        await installDocling()
        UserDefaults.standard.set(true, forKey: "doclingReady")
        await convertQueued()
    }

    func skipDoclingInstall() {
        showDoclingPrompt = false
        let waiting = pendingGraphics
        pendingGraphics = []
        guard !waiting.isEmpty else { return }
        Task {
            await enqueue(waiting)
            await convertQueued()
        }
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .pdf, .plainText, .image, .jpeg, .png, .gif, .webP, .tiff,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
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

    func enqueue(_ urls: [URL], scans: Set<String>? = nil) async {
        let ocrOn = ocrEnabled
        let resolved: Set<String>
        if let scans {
            resolved = scans
        } else {
            resolved = await PdfWork.runAsync {
                Set(urls.compactMap { url -> String? in
                    guard ocrOn, url.pathExtension.lowercased() == "pdf" else { return nil }
                    return OcrService.profile(url).needsOCR ? url.path : nil
                })
            }
        }
        var scanCount = 0
        for url in urls where ConvertibleKind.allows(url) {
            if jobs.contains(where: { $0.sourceURL == url }) { continue }
            var scan = false
            if ocrOn && url.pathExtension.lowercased() == "pdf" {
                scan = resolved.contains(url.path)
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

    /// Queued and running stay. Only the ten newest done/failed rows remain.
    private static let convertFinishedCap = 10

    var recentConvertJobs: [ConvertJob] {
        jobs.sorted { $0.touchedAt > $1.touchedAt }
    }

    var hasRecentConvertJobs: Bool {
        jobs.contains { $0.status == .done || $0.status == .failed }
    }

    var isConvertRunning: Bool {
        jobs.contains { $0.status == .running }
    }

    func clearRecentConvertJobs() {
        jobs.removeAll { $0.status == .done || $0.status == .failed }
    }

    func stopCurrentConvert() {
        guard isConvertRunning || isBusy else { return }
        convertWanted = false
        convertCancelled = true
        ProcessRun.cancelConvert()
    }

    /// Marks the running job Stopped. Returns true when convert should exit.
    private func finishIfStopped(_ jobID: UUID) -> Bool {
        guard convertCancelled || ProcessRun.convertWasCancelled else { return false }
        convertCancelled = true
        convertWanted = false
        if let i = jobs.firstIndex(where: { $0.id == jobID }), jobs[i].status == .running {
            jobs[i].status = .failed
            jobs[i].detail = "Stopped"
            jobs[i].touchedAt = Date()
        }
        pruneConvertJobs()
        statusText = "Stopped"
        return true
    }

    private func pruneConvertJobs() {
        let finished = jobs
            .filter { $0.status == .done || $0.status == .failed }
            .sorted { $0.touchedAt < $1.touchedAt }
        guard finished.count > Self.convertFinishedCap else { return }
        let drop = Set(finished.dropLast(Self.convertFinishedCap).map(\.id))
        jobs.removeAll { drop.contains($0.id) }
    }

    func convertQueued() async {
        convertWanted = true
        if isBusy { return }
        convertCancelled = false
        ProcessRun.resetConvertCancel()
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
            if convertCancelled { break }
            if jobs.contains(where: { $0.status == .queued }) {
                convertWanted = true
            }
        }
        quietWatch(12)
        if convertCancelled {
            statusText = "Stopped"
        } else {
            statusText = jobs.contains(where: { $0.status == .failed }) ? "Finished with errors" : "Done"
        }
    }

    private static func pageTick(in message: String) -> (page: Int, count: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"page\s+(\d+)\s+of\s+(\d+)"#, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = regex.firstMatch(in: message, range: range),
              let pageRange = Range(match.range(at: 1), in: message),
              let countRange = Range(match.range(at: 2), in: message),
              let page = Int(message[pageRange]),
              let count = Int(message[countRange]),
              count > 0
        else { return nil }
        return (page, count)
    }

    private func beginConvertJob(_ index: Int, batchIndex: Int, batchCount: Int) {
        jobs[index].status = .running
        jobs[index].touchedAt = Date()
        jobs[index].startedAt = Date()
        jobs[index].phase = "Markdown"
        jobs[index].progress = nil
        jobs[index].page = 0
        jobs[index].pageCount = 0
        jobs[index].etaSeconds = nil
        jobs[index].firstTickAt = nil
        jobs[index].firstTickPage = 0
        jobs[index].fileIndex = batchIndex
        jobs[index].fileCount = batchCount
    }

    private func setJobPhase(_ jobID: UUID, _ phase: String, detail: String? = nil, progress: Double? = nil) {
        guard let i = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        if jobs[i].phase != phase {
            jobs[i].phase = phase
            jobs[i].progress = nil
            jobs[i].page = 0
            jobs[i].pageCount = 0
            jobs[i].etaSeconds = nil
            jobs[i].firstTickAt = nil
            jobs[i].firstTickPage = 0
        }
        if let detail { jobs[i].detail = detail }
        if let progress {
            jobs[i].progress = progress
        }
        jobs[i].touchedAt = Date()
    }

    @discardableResult
    private func applyJobStatus(_ jobID: UUID, _ message: String, phase: String) -> Bool {
        _ = setStatus(message)
        guard let i = jobs.firstIndex(where: { $0.id == jobID }) else { return false }
        if jobs[i].phase != phase {
            jobs[i].phase = phase
            jobs[i].progress = nil
            jobs[i].page = 0
            jobs[i].pageCount = 0
            jobs[i].etaSeconds = nil
            jobs[i].firstTickAt = nil
            jobs[i].firstTickPage = 0
        }
        jobs[i].detail = message
        jobs[i].touchedAt = Date()
        if let tick = Self.pageTick(in: message) {
            jobs[i].page = tick.page
            jobs[i].pageCount = tick.count
            jobs[i].progress = Double(tick.page) / Double(tick.count)
            if jobs[i].firstTickAt == nil {
                jobs[i].firstTickAt = Date()
                jobs[i].firstTickPage = tick.page
                jobs[i].etaSeconds = nil
            } else {
                let advanced = tick.page - jobs[i].firstTickPage
                if advanced >= 1, tick.count > tick.page, let start = jobs[i].firstTickAt {
                    let elapsed = Date().timeIntervalSince(start)
                    jobs[i].etaSeconds = Int((elapsed / Double(advanced) * Double(tick.count - tick.page)).rounded())
                }
            }
        } else {
            jobs[i].progress = nil
            jobs[i].etaSeconds = nil
        }
        return true
    }

    private func convertOnePass() async {
        let batch = jobs.indices.filter { jobs[$0].status == .queued || jobs[$0].status == .failed }
        let batchCount = batch.count
        for (batchOffset, index) in batch.enumerated() {
            if convertCancelled { return }
            let original = jobs[index].sourceURL
            let jobID = jobs[index].id
            let scan = jobs[index].needsOCR
            beginConvertJob(index, batchIndex: batchOffset + 1, batchCount: batchCount)
            statusText = "Converting \(original.lastPathComponent)…"
            let output = outputURL(for: original)
            let work = Self.sandboxReadable(original)
            defer { Self.removeSandboxCopy(work) }
            do {
                quietWatch()
                var input = work.url
                var usedOCR = false
                var ocrTempPDF: URL?
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
                            let phase = msg.localizedCaseInsensitiveContains("picture")
                                || msg.localizedCaseInsensitiveContains("page")
                                ? "Pictures" : "Markdown"
                            _ = self.applyJobStatus(jobID, msg, phase: phase)
                        }
                    }
                    let url = try await NativeConvert.convert(
                        input: work.url,
                        output: output,
                        ocr: ocrEnabled && scan,
                        onStatus: onNative
                    )
                    if finishIfStopped(jobID) { return }
                    var pictures = 0
                    if isPDF {
                        await tidyPDFMarkdown(url, pdf: work.url)
                        let bookmarks = await loadBookmarks(work.url)
                        let (final, located) = await finalizeMarkdown(url, original: original, bookmarks: bookmarks)
                        pictures = await PdfFigures.embed(
                            markdownURL: final,
                            sourcePDF: work.url,
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
                        let bookmarks = await loadBookmarks(work.url)
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
                    setJobPhase(jobID, "OCR", detail: "Layout OCR first — this takes a little longer")
                    statusText = "Layout OCR first — this takes a little longer · \(original.lastPathComponent)"
                    let onOCR: @Sendable (String) -> Void = { msg in
                        Task { @MainActor in
                            let line = "Layout OCR first — this takes a little longer. \(msg)"
                            _ = self.applyJobStatus(jobID, line, phase: "OCR")
                        }
                    }
                    if finishIfStopped(jobID) { return }
                    if await OcrService.layoutMarkdown(
                        from: work.url,
                        to: output,
                        ocr: scan,
                        onStatus: onOCR
                    ) {
                        UserDefaults.standard.set(true, forKey: "doclingReady")
                        if let script = Bundle.main.url(forResource: "pdf_enrich", withExtension: "py"),
                           await markdownNeedsEnrich(output) {
                            await service.enrichPDF(markdown: output, pdf: work.url, script: script)
                        }
                        let bookmarks = await loadBookmarks(work.url)
                        let (url, located) = await finalizeMarkdown(output, original: original, bookmarks: bookmarks)
                        let pictures = await PdfFigures.materializeEmbedded(markdownURL: url)
                        await finishJob(jobID: jobID, markdown: url, original: original, usedOCR: true, pictures: pictures, bookmarks: located)
                        continue
                    }
                    if finishIfStopped(jobID) { return }
                    let prepared = try await OcrService.searchablePDF(from: work.url, onStatus: onOCR)
                    input = prepared.url
                    usedOCR = prepared.didOCR
                    if prepared.url != work.url { ocrTempPDF = prepared.url }
                    setJobPhase(jobID, "Markdown", detail: "OCR done — converting with MarkItDown…")
                    statusText = "OCR done — converting \(original.lastPathComponent)…"
                }
                setJobPhase(jobID, "Markdown", detail: "Markdown — converting…")
                let url = try await service.convert(
                    input: input,
                    output: output,
                    script: Bundle.main.url(forResource: "markitdown_convert", withExtension: "py"),
                    llmKey: (askReadPictures && askHasKey) ? AskSecrets.load() : "",
                    llmBase: askBaseURL,
                    llmModel: askModel
                )
                if finishIfStopped(jobID) { return }
                var pictures = 0
                if isPDF {
                    let onFig: @Sendable (String) -> Void = { msg in
                        Task { @MainActor in
                            let phase = msg.localizedCaseInsensitiveContains("picture") ? "Pictures" : "OCR"
                            _ = self.applyJobStatus(jobID, msg, phase: phase)
                        }
                    }
                    let pages = await PdfWork.runAsync { OcrService.pageCount(of: work.url) }
                    let thin = await PdfWork.runAsync {
                        OcrService.markdownLooksThin(url, pageCount: max(pages, 1))
                    }
                    if ocrEnabled, thin, !usedOCR {
                        // MarkItDown saw no text layer. OCR first, then convert again.
                        jobs[index].needsOCR = true
                        setJobPhase(jobID, "OCR", detail: "Scan detected — OCR first, then convert")
                        statusText = "This PDF is a scan (picture of the page). Running OCR…"
                        let onOCR: @Sendable (String) -> Void = { msg in
                            Task { @MainActor in
                                _ = self.applyJobStatus(jobID, msg, phase: "OCR")
                            }
                        }
                        if finishIfStopped(jobID) { return }
                        if await OcrService.layoutMarkdown(
                            from: work.url,
                            to: output,
                            ocr: true,
                            onStatus: onOCR
                        ) {
                            usedOCR = true
                            UserDefaults.standard.set(true, forKey: "doclingReady")
                        } else {
                            let prepared = try await OcrService.searchablePDF(from: work.url, force: true, onStatus: onOCR)
                            usedOCR = true
                            if prepared.url != work.url { ocrTempPDF = prepared.url }
                            if prepared.didOCR || prepared.url != work.url {
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
                    let stillThin: Bool
                    let stillEmpty: Bool
                    if usedOCR {
                        stillThin = await PdfWork.runAsync {
                            OcrService.markdownLooksThin(url, pageCount: max(pages, 1))
                        }
                        stillEmpty = await PdfWork.runAsync {
                            OcrService.markdownLooksEmpty(url)
                        }
                    } else {
                        stillThin = false
                        stillEmpty = false
                    }
                    if stillThin || stillEmpty {
                        await OcrService.enrichMarkdown(markdownURL: url, sourcePDF: work.url, onStatus: onFig)
                    }
                    statusText = "Cleaning headers and headings…"
                    await tidyPDFMarkdown(url, pdf: work.url)
                    if await markdownNeedsEnrich(url) {
                        let script = Bundle.main.url(forResource: "pdf_enrich", withExtension: "py")
                        statusText = "Restoring the PDF outline and tables…"
                        await service.enrichPDF(markdown: url, pdf: work.url, script: script)
                    }
                    let bookmarks = await loadBookmarks(work.url)
                    let (final, located) = await finalizeMarkdown(url, original: original, bookmarks: bookmarks)
                    keepSearchableIfWanted(temp: ocrTempPDF, original: work.url, markdown: final)
                    _ = await PdfFigures.materializeEmbedded(markdownURL: final)
                    pictures = 0
                    if !usedOCR {
                        pictures = await PdfFigures.embed(
                            markdownURL: final,
                            sourcePDF: work.url,
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
                let bookmarks = await loadBookmarks(work.url)
                let (final, located) = await finalizeMarkdown(url, original: original, bookmarks: bookmarks)
                await finishJob(
                    jobID: jobID,
                    markdown: final,
                    original: original,
                    usedOCR: usedOCR,
                    pictures: pictures,
                    bookmarks: located
                )
            } catch is ProcessRun.ConvertCancel {
                _ = finishIfStopped(jobID)
                return
            } catch {
                if finishIfStopped(jobID) { return }
                if let i = jobs.firstIndex(where: { $0.id == jobID }) {
                    jobs[i].status = .failed
                    jobs[i].detail = error.localizedDescription
                    jobs[i].touchedAt = Date()
                }
                pruneConvertJobs()
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

    static func searchablePdfURL(beside markdown: URL) -> URL {
        markdown.deletingPathExtension().appendingPathExtension("searchable.pdf")
    }

    private func keepSearchableIfWanted(temp: URL?, original: URL, markdown: URL) {
        guard saveOcrPdf, let temp, temp.path != original.path else { return }
        guard FileManager.default.fileExists(atPath: temp.path) else { return }
        let dest = Self.searchablePdfURL(beside: markdown)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: temp, to: dest)
    }

    func saveOcrPdf(for item: LibraryItem) async {
        guard !ocrPdfBusy else { return }

        let sourceLooksPDF = !item.sourcePath.isEmpty && item.sourcePath.lowercased().hasSuffix(".pdf")
        if !sourceLooksPDF {
            let kind = item.sourceName.split(separator: ".").last.map(String.init)?.uppercased() ?? "this file"
            ocrPdfNotice = "SAVE OCR PDF only works on a PDF. “\(item.title)” is \(kind == "MD" ? "Markdown" : kind), not a scanned PDF. Open a converted PDF in the library."
            return
        }

        ocrPdfBusy = true
        defer { ocrPdfBusy = false }

        let markdown = URL(fileURLWithPath: item.markdownPath)
        let dest = Self.searchablePdfURL(beside: markdown)
        if FileManager.default.fileExists(atPath: dest.path) {
            NSWorkspace.shared.activateFileViewerSelecting([dest])
            statusText = "Searchable PDF is already next to the Markdown"
            return
        }
        let source = URL(fileURLWithPath: item.sourcePath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            statusText = "The original PDF is no longer at that path"
            return
        }
        guard OcrService.ocrmypdfPath() != nil else {
            statusText = Distribution.isAppStore
                ? "This App Store copy cannot write a searchable PDF"
                : "Install the optional backup scanner in Settings first"
            return
        }

        statusText = "Writing searchable PDF — this takes extra time…"
        do {
            let prepared = try await OcrService.searchablePDF(from: source, force: true) { msg in
                Task { @MainActor in
                    _ = self.setStatus("Writing searchable PDF. \(msg)")
                }
            }
            guard prepared.url != source, FileManager.default.fileExists(atPath: prepared.url.path) else {
                statusText = "OCRmyPDF did not write a searchable PDF"
                return
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: prepared.url, to: dest)
            try? FileManager.default.removeItem(at: prepared.url)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
            statusText = "Saved \(dest.lastPathComponent) next to the Markdown"
        } catch {
            statusText = "Could not save the searchable PDF"
        }
    }

    private func finishJob(
        jobID: UUID,
        markdown: URL,
        original: URL,
        usedOCR: Bool,
        pictures: Int,
        bookmarks: [ManualBookmark]
    ) async {
        if finishIfStopped(jobID) { return }
        quietWatch()
        if let i = jobs.firstIndex(where: { $0.id == jobID }) {
            jobs[i].status = .done
            jobs[i].outputURL = markdown
            jobs[i].touchedAt = Date()
            var bits: [String] = []
            if usedOCR { bits.append("Layout OCR") }
            if pictures > 0 { bits.append("\(pictures) pictures") }
            if !bookmarks.isEmpty { bits.append("\(bookmarks.count) bookmarks") }
            bits.append(markdown.lastPathComponent)
            jobs[i].detail = bits.joined(separator: " · ")
            jobs[i].progress = nil
            jobs[i].etaSeconds = nil
            jobs[i].phase = ""
        }
        addToLibrary(source: original, markdown: markdown, bookmarks: bookmarks)
        ConvertNotice.fileReady(markdown: markdown)
        pruneConvertJobs()
    }

    func openConvertedFromNotice(_ markdownPath: String?) {
        guard let markdownPath,
              let item = library.first(where: { $0.markdownPath == markdownPath })
        else { return }
        selectedTool = .library
        showSettings = false
        showHelp = false
        selectLibrary(item)
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

    func isLibrarySelected(_ item: LibraryItem) -> Bool {
        selectedLibraryIDs.contains(item.id)
    }

    func clickLibrary(_ item: LibraryItem) {
        if awaitingPairPick {
            finishPairPick(with: item)
            return
        }
        if sideBySideOpening { return }
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            toggleLibrarySelection(item)
        } else if flags.contains(.shift) {
            extendLibrarySelection(to: item)
        } else {
            selectLibrary(item)
        }
    }

    private func finishPairPick(with item: LibraryItem) {
        guard let lead = library.first(where: { $0.id == pairPickLeadID })
            ?? library.first(where: { $0.id == selectedLibraryID })
        else {
            startPairPick(lead: item, message: L("Click the matching file."))
            return
        }
        if item.id == lead.id { return }
        guard shareOrigin(lead, item) else {
            let note = L("Not a pair — click a file under the same original")
            showToast(note, sticky: true)
            statusText = note
            return
        }
        let pair = orderPair(lead, item)
        openPairSideBySide(left: pair.left, right: pair.right)
    }

    func toggleLibrarySelection(_ item: LibraryItem) {
        if selectedLibraryIDs.contains(item.id) {
            selectedLibraryIDs.remove(item.id)
            if selectedLibraryID == item.id {
                selectedLibraryID = selectedLibraryIDs.first
            }
            return
        }
        if selectedLibraryIDs.isEmpty, let lead = selectedLibraryID {
            selectedLibraryIDs.insert(lead)
        }
        selectedLibraryIDs.insert(item.id)
        if selectedLibraryID == nil {
            selectedLibraryID = item.id
        }
    }

    func extendLibrarySelection(to item: LibraryItem) {
        guard let lead = selectedLibraryID,
              let from = library.firstIndex(where: { $0.id == lead }),
              let to = library.firstIndex(where: { $0.id == item.id })
        else {
            selectLibrary(item)
            return
        }
        let lo = min(from, to)
        let hi = max(from, to)
        selectedLibraryIDs = Set(library[lo...hi].map(\.id))
    }

    func contextTargets(for item: LibraryItem) -> [LibraryItem] {
        if selectedLibraryIDs.contains(item.id), selectedLibraryIDs.count > 1 {
            return library.filter { selectedLibraryIDs.contains($0.id) }
        }
        return [item]
    }

    func revealLibraryItems(_ items: [LibraryItem]) {
        let urls = items.compactMap { Self.finderShareURL(forMarkdown: URL(fileURLWithPath: $0.markdownPath)) }
        guard !urls.isEmpty else {
            errorMessage = "Those Markdown files are not on disk anymore."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func moveLibraryItems(_ items: [LibraryItem]) {
        let panel = NSOpenPanel()
        panel.title = "Move Markdown here"
        panel.message = "The original PDF or Word file stays where it is. Pictures in a figures folder stay put."
        panel.prompt = "Move"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        quietWatch(8)
        for item in items {
            let src = URL(fileURLWithPath: item.markdownPath)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            var dest = folder.appendingPathComponent(src.lastPathComponent)
            if dest.path == src.path { continue }
            if FileManager.default.fileExists(atPath: dest.path) {
                let stem = dest.deletingPathExtension().lastPathComponent
                dest = folder.appendingPathComponent("\(stem)-moved.md")
            }
            do {
                try FileManager.default.moveItem(at: src, to: dest)
                if let idx = library.firstIndex(where: { $0.id == item.id }) {
                    library[idx].markdownPath = dest.path
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        saveLibrary()
        startWatching()
        statusText = items.count == 1 ? "Moved 1 file" : "Moved \(items.count) files"
    }

    func removeLibraryItems(_ items: [LibraryItem]) {
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty else { return }
        let next = library.first { !ids.contains($0.id) }
        for item in items {
            if item.id == Self.guideID {
                UserDefaults.standard.set(true, forKey: "dismissedGuide")
                try? FileManager.default.removeItem(atPath: item.markdownPath)
            } else if Self.isForagePath(item.markdownPath) || item.sourceName == "FORAGE" {
                rememberDeletedForage(item.markdownPath)
                if isOpenForage(item) {
                    forgetOpenForageSession(keepLiveBoard: hunterOn)
                }
            } else if deleteFilesWithCard {
                removeConvertPackage(for: item, deleting: ids)
            }
            library.removeAll { $0.id == item.id }
            selectedLibraryIDs.remove(item.id)
        }
        if let lead = selectedLibraryID, ids.contains(lead) {
            if let next {
                selectLibrary(next)
            } else {
                selectedLibraryID = nil
                selectedLibraryIDs = []
                previewMarkdown = ""
                previewLines = []
                previewHeadings = []
                previewBaseURL = nil
                previewBackup = nil
                previewTruncated = false
                askChapter = "Entire file"
            }
        }
        saveLibrary()
        startWatching()
    }

    /// Markdown, figures, sidecar, searchable PDF, and the convert folder. Never the original PDF.
    private func removeConvertPackage(for item: LibraryItem, deleting ids: Set<UUID>) {
        let md = URL(fileURLWithPath: item.markdownPath)
        let folder = md.deletingLastPathComponent().standardizedFileURL
        let source: URL? = item.sourcePath.isEmpty
            ? nil
            : URL(fileURLWithPath: item.sourcePath).standardizedFileURL
        if let source, Self.sameFilePath(source.path, md.path) { return }

        let siblingStays = library.contains { other in
            !ids.contains(other.id)
                && URL(fileURLWithPath: other.markdownPath).deletingLastPathComponent()
                    .standardizedFileURL.path == folder.path
        }

        trashURL(md)
        trashURL(PdfSidecar.sidecarURL(for: md))
        trashURL(Self.searchablePdfURL(beside: md))
        guard !siblingStays else { return }

        trashURL(folder.appendingPathComponent(PdfFigures.folderName, isDirectory: true))
        let stem = md.deletingPathExtension().lastPathComponent
        trashURL(folder.appendingPathComponent(stem + PdfFigures.folderSuffix, isDirectory: true))

        let roots = [
            forageHome.standardizedFileURL.path,
            convertedDir.standardizedFileURL.path,
        ]
        if roots.contains(folder.path) { return }
        if let source, folder.path == source.deletingLastPathComponent().standardizedFileURL.path {
            return
        }
        if let source, folder.path == source.path { return }

        let leftover = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let stillHasMarkdown = leftover.contains { $0.pathExtension.lowercased() == "md" }
        if !stillHasMarkdown {
            trashURL(folder)
        }
    }

    private func trashURL(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Cards for Markdown already in the chosen folder (or On this Mac only). Does not drop existing cards.
    func rebuildLibraryFromDefaultFolder() {
        let added = ingestInboxMarkdown(announce: false)
        let root = forageHome
        if added == 0 {
            statusText = "Library already matches \(root.lastPathComponent)"
        } else {
            statusText = added == 1
                ? "Added 1 card from \(root.lastPathComponent)"
                : "Added \(added) cards from \(root.lastPathComponent)"
        }
    }

    /// Add .md files that appeared in the yourMark folder (Finder drop, copy, or File → Open).
    @discardableResult
    private func ingestInboxMarkdown(announce: Bool) -> Int {
        let root = forageHome
        let fm = FileManager.default
        var markdowns: [URL] = []
        let kids = (try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for kid in kids {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: kid.path, isDirectory: &isDir)
            if isDir.boolValue {
                if kid.lastPathComponent.lowercased() == "figures" { continue }
                let inner = (try? fm.contentsOfDirectory(
                    at: kid,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
                markdowns.append(contentsOf: inner.filter { ConvertibleKind.isReadyMarkdown($0) })
            } else if ConvertibleKind.isReadyMarkdown(kid) {
                markdowns.append(kid)
            }
        }

        var added = 0
        for md in markdowns.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            if Self.isForagePath(md.path) || Self.looksLikeForage(url: md) { continue }
            if library.contains(where: { Self.sameFilePath($0.markdownPath, md.path) }) { continue }
            let bookmarks = PdfSidecar.readSidecar(nextTo: md)
            _ = insertLibraryItem(source: md, markdown: md, bookmarks: bookmarks)
            added += 1
        }
        if added > 0 {
            scanForageVault()
            if announce {
                statusText = added == 1
                    ? "Added 1 Markdown file from \(root.lastPathComponent)"
                    : "Added \(added) Markdown files from \(root.lastPathComponent)"
            }
        }
        return added
    }

    func selectLibrary(_ item: LibraryItem, show: Bool = true, force: Bool = false) {
        if !force, awaitingPairPick || sideBySideOpening { return }
        if force {
            awaitingPairPick = false
            pairPickLeadID = nil
            sideBySideOpening = false
        }
        if let idx = library.firstIndex(where: { $0.id == item.id }) {
            library[idx].openedAt = Date()
            let key = originKey(for: library[idx])
            if let masterIdx = library.firstIndex(where: { originKey(for: $0) == key && isOriginMaster($0) }) {
                library[masterIdx].openedAt = Date()
            }
            saveLibrary()
        }
        if hunterOn {
            hunterGatheredRanges = hunterGatheredByPath[item.markdownPath] ?? []
            applyForageCardMarks(for: item.markdownPath)
        }
        hunterMarkStamp += 1
        selectedLibraryID = item.id
        selectedLibraryIDs = [item.id]
        if !hunterOn {
            updateForageSync(autoOn: !forageLinkUserOff)
        }
        previewNeedsLoad = false
        liveEditPath = ""
        sideBySide = false
        pulseSaveCopy = false
        translateMarkdown = nil
        translateLines = []
        translateHeadings = []
        translateScrollLine = nil
        linkedHeading = ""
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
                self.previewTruncated = pack.truncated
                self.hunterTextMemo.removeAll(keepingCapacity: true)
                self.refreshFileHits(in: pack.lines)
                if self.hunterOn {
                    self.hunterGatheredRanges = self.hunterGatheredByPath[path] ?? []
                    self.applyForageCardMarks(for: path)
                    self.hunterMarkStamp += 1
                } else {
                    self.updateForageSync(autoOn: !self.forageLinkUserOff)
                }
                self.startWatching()
            }
        }
    }

    /// Read a prefix for the reader. Default is 2 MB — a full NAT-sized manual.
    nonisolated static func readMarkdownPrefix(path: String, maxBytes: Int = readerMaxBytes) -> (text: String, truncated: Bool)? {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 8 else { return nil }
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: maxBytes)
        guard let text = decodeMarkdownPrefix(data) else { return nil }
        return (text, size > maxBytes)
    }

    nonisolated static func decodeMarkdownPrefix(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        var slice = data
        for _ in 0..<4 where slice.count > 8 {
            slice = slice.dropLast()
            if let text = String(data: slice, encoding: .utf8) { return text }
        }
        return String(data: data, encoding: .isoLatin1)
    }

    nonisolated static func readerLines(from text: String) -> [PreviewLine] {
        let raw = text.split(separator: "\n", omittingEmptySubsequences: false)
        let cap = readerMaxLines
        let lineCap = readerLineCharCap
        var out: [PreviewLine] = []
        out.reserveCapacity(min(raw.count, cap))
        for (i, line) in raw.enumerated() {
            if i >= cap { break }
            if line.contains("data:image") {
                out.append(PreviewLine(id: i, text: "_A picture is stored as a file in the figures folder (Finder)._"))
            } else if line.count > lineCap {
                let cut = line.index(line.startIndex, offsetBy: lineCap)
                out.append(PreviewLine(id: i, text: String(line[..<cut]) + "…"))
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
        var truncated = false
        let cap = readerMaxChars
        if text.count > cap {
            let idx = text.index(text.startIndex, offsetBy: cap)
            var cut = String(text[..<idx])
            if let nl = cut.lastIndex(of: "\n") { cut = String(cut[..<nl]) }
            text = cut + "\n\n_\(readerCapNote)_\n"
            truncated = true
        }
        var lines = readerLines(from: text)
        if lines.count >= readerMaxLines { truncated = true }
        if truncated, !text.contains("40,000 lines") {
            lines.append(PreviewLine(id: lines.count, text: "_\(readerCapNote)_"))
        }
        let headings = scanHeadings ? headings(from: lines) : []
        return PreviewPack(text: text, lines: lines, headings: headings, base: base, missing: missing, truncated: truncated)
    }

    nonisolated static func headings(from lines: [PreviewLine]) -> [ManualBookmark] {
        var headings: [ManualBookmark] = []
        var used = Set<String>()
        for (i, row) in lines.enumerated() {
            if headings.count >= 180 { break }
            let probe = row.text.hasPrefix(TranslateService.marker)
                ? String(row.text.dropFirst(TranslateService.marker.count))
                : row.text
            guard let title = PdfSidecar.headingText(probe) else { continue }
            guard title.caseInsensitiveCompare("Outline") != .orderedSame else { continue }
            guard !PdfSidecar.isPageLikeHeading(title) else { continue }
            var key = title.lowercased()
            if used.contains(key) { key += "-\(headings.count)" }
            used.insert(key)
            let n = probe.prefix(while: { $0 == "#" }).count
            headings.append(ManualBookmark(title: title, level: max(1, min(Int(n), 3)), pageIndex: nil, lineIndex: i))
        }
        return headings
    }

    nonisolated static func buildPreview(path: String, scanHeadings: Bool = true) -> PreviewPack {
        let url = URL(fileURLWithPath: path)
        let base = url.deletingLastPathComponent()
        guard let read = readMarkdownPrefix(path: path) else {
            let missing = "_File missing on disk._"
            return PreviewPack(
                text: missing,
                lines: [PreviewLine(id: 0, text: missing)],
                headings: [],
                base: base,
                missing: true
            )
        }
        var text = read.text
        if read.truncated, !text.contains("40,000 lines") {
            if let nl = text.lastIndex(of: "\n") { text = String(text[..<nl]) }
            text += "\n\n_\(readerCapNote)_\n"
        }
        var pack = packFromText(text, base: base, scanHeadings: scanHeadings)
        if read.truncated { pack.truncated = true }
        return pack
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

    func jumpToFileSearchHit(in lines: [PreviewLine]? = nil) {
        refreshFileHits(in: lines ?? previewLines)
    }

    func jumpToBookmark(_ bookmark: ManualBookmark) {
        askChapter = bookmark.title
        adoptLinkMaster(.main)
        linkedHeading = bookmark.title
        visibleHeading[.main] = bookmark.title
        ignoreVisibleUntil = Date().addingTimeInterval(0.85)
        let line: Int? = {
            if let idx = bookmark.lineIndex, previewLines.contains(where: { $0.id == idx }) {
                return idx
            }
            if let idx = bookmark.lineIndex {
                if previewTruncated {
                    statusText = Self.readerCapNote
                    return previewLines.last?.id
                }
                if previewLines.indices.contains(idx) {
                    return previewLines[idx].id
                }
            }
            let lines = previewLines.map(\.text)
            let pdf = selectedLibraryID.flatMap { id in
                library.first(where: { $0.id == id }).flatMap { item -> URL? in
                    item.sourcePath.isEmpty ? nil : URL(fileURLWithPath: item.sourcePath)
                }
            }
            return PdfSidecar.line(for: bookmark, in: lines, pdf: pdf)
                ?? headingLine(bookmark.title, in: previewLines)
        }()
        if let line {
            visibleLine[.main] = line
            if hunterOn {
                hunterScrollChar = hunterCharOffset(forLine: line, in: previewLines)
                hunterScrollStamp += 1
            } else {
                bumpMainScroll(line)
            }
        }
        if linkingScroll, linkScroll {
            followSlave(heading: bookmark.title, line: line, master: .main)
        }
    }

    func jumpToTranslatedBookmark(_ bookmark: ManualBookmark) {
        askChapter = bookmark.title
        adoptLinkMaster(.translate)
        linkedHeading = bookmark.title
        visibleHeading[.translate] = bookmark.title
        let line = headingLine(bookmark.title, in: translateLines) ?? bookmark.lineIndex
        if let line {
            visibleLine[.translate] = line
            bumpTranslateScroll(line)
        }
        if sideBySide, linkScroll {
            followSlave(heading: bookmark.title, line: line, master: .translate)
        }
    }

    /// Package folder when pictures sit beside the Markdown; otherwise the .md itself.
    private static func finderShareURL(forMarkdown url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let folder = url.deletingLastPathComponent()
        let figures = folder.appendingPathComponent("figures", isDirectory: true)
        if FileManager.default.fileExists(atPath: figures.path) {
            return folder
        }
        return url
    }

    func reveal(_ url: URL) {
        guard let target = Self.finderShareURL(forMarkdown: url) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    var editorButtonHelp: String {
        let editor: String
        if editorChoice == "custom", !customEditorName.isEmpty {
            editor = customEditorName
        } else if editorChoice == "marktext" {
            editor = "MarkText"
        } else {
            editor = "MarkEdit"
        }
        return "Edit one file in \(editor). If Library and FORAGE are both open, you pick which one."
    }

    func persistEditorPrefs() {
        UserDefaults.standard.set(editorChoice, forKey: "editorChoice")
        UserDefaults.standard.set(customEditorName, forKey: "customEditorName")
        UserDefaults.standard.set(customEditorScheme, forKey: "customEditorScheme")
        UserDefaults.standard.set(editTarget, forKey: "editTarget")
    }

    func persistOcrAppPrefs() {
        UserDefaults.standard.set(ocrAppChoice, forKey: "ocrAppChoice")
        UserDefaults.standard.set(customOcrAppName, forKey: "customOcrAppName")
    }

    var hasChosenOcrApp: Bool {
        ocrAppChoice == "custom" && resolveCustomOcrApp() != nil
    }

    func libraryItemHasPdfSource(_ item: LibraryItem) -> Bool {
        !item.sourcePath.isEmpty && item.sourcePath.lowercased().hasSuffix(".pdf")
    }

    func canOpenInOcrApp(_ item: LibraryItem?) -> Bool {
        guard let item, hasChosenOcrApp else { return false }
        return libraryItemHasPdfSource(item)
    }

    var ocrAppButtonTitle: String {
        if !customOcrAppName.isEmpty { return "\(L("Open in")) \(customOcrAppName)" }
        return L("OCR")
    }

    func setOcrAppChoice(_ value: String) {
        if value == "custom" {
            if resolveCustomOcrApp() == nil {
                pickCustomOcrApp()
                return
            }
            ocrAppChoice = "custom"
            persistOcrAppPrefs()
            return
        }
        ocrAppChoice = "none"
        persistOcrAppPrefs()
    }

    func pickCustomOcrApp() {
        let panel = NSOpenPanel()
        panel.title = L("Choose an OCR app")
        panel.message = L("This is Applications. Click the app you use to make a PDF searchable.")
        panel.prompt = L("Use this app")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            if resolveCustomOcrApp() == nil {
                ocrAppChoice = "none"
                persistOcrAppPrefs()
            }
            return
        }
        saveCustomOcrApp(url)
        ocrAppChoice = "custom"
        persistOcrAppPrefs()
        statusText = L("OCR will open in \(customOcrAppName)")
    }

    private func saveCustomOcrApp(_ url: URL) {
        customOcrAppName = url.deletingPathExtension().lastPathComponent
        UserDefaults.standard.set(url.path, forKey: "customOcrAppPath")
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: "customOcrAppBookmark")
        }
    }

    private func resolveCustomOcrApp() -> URL? {
        if let data = UserDefaults.standard.data(forKey: "customOcrAppBookmark") {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                if stale { saveCustomOcrApp(url) }
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        let path = UserDefaults.standard.string(forKey: "customOcrAppPath") ?? ""
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func openInOcrApp(_ item: LibraryItem) {
        guard let app = resolveCustomOcrApp() else {
            statusText = L("Choose an OCR app in Settings first.")
            return
        }
        guard libraryItemHasPdfSource(item) else {
            statusText = L("Open a converted PDF first.")
            return
        }
        let pdf = URL(fileURLWithPath: item.sourcePath)
        guard FileManager.default.fileExists(atPath: pdf.path) else {
            errorMessage = L("That PDF is not on disk anymore.")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([pdf], withApplicationAt: app, configuration: config)
        statusText = L("Opened in \(customOcrAppName)")
    }

    func openOcrmypdfSite() {
        if let url = URL(string: "https://github.com/ocrmypdf/OCRmyPDF") {
            NSWorkspace.shared.open(url)
        }
    }

    func setEditTarget(_ value: String) {
        editTarget = value
        persistEditorPrefs()
    }

    func setEditorChoice(_ value: String) {
        if value == "custom" {
            if resolveCustomEditor() == nil {
                pickCustomEditor()
                return
            }
            editorChoice = "custom"
            persistEditorPrefs()
            return
        }
        editorChoice = value
        persistEditorPrefs()
    }

    func pickCustomEditor() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Markdown editor"
        panel.message = "This is Applications. Click the editor you want. Edit will open your file there at once."
        panel.prompt = "Use this editor"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            if resolveCustomEditor() == nil {
                editorChoice = "markedit"
                persistEditorPrefs()
            }
            return
        }
        saveCustomEditor(url)
        editorChoice = "custom"
        persistEditorPrefs()
        statusText = "Edit will open in \(customEditorName)"
    }

    private func saveCustomEditor(_ url: URL) {
        customEditorName = url.deletingPathExtension().lastPathComponent
        customEditorScheme = Self.urlScheme(forApp: url) ?? ""
        UserDefaults.standard.set(url.path, forKey: "customEditorPath")
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: "customEditorBookmark")
        }
    }

    private func resolveCustomEditor() -> URL? {
        if let data = UserDefaults.standard.data(forKey: "customEditorBookmark") {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                if stale { saveCustomEditor(url) }
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        let path = UserDefaults.standard.string(forKey: "customEditorPath") ?? ""
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func urlScheme(forApp url: URL) -> String? {
        guard let bundle = Bundle(url: url),
              let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        else { return nil }
        for type in types {
            if let schemes = type["CFBundleURLSchemes"] as? [String],
               let first = schemes.first, !first.isEmpty {
                return first
            }
        }
        return nil
    }

    func openInEditor(_ item: LibraryItem?) {
        let forage = forageEditURL
        let libraryPath = item.map(\.markdownPath) ?? ""
        let libraryReady = !libraryPath.isEmpty && FileManager.default.isReadableFile(atPath: libraryPath)
        let sameFile = forage.map { $0.path == libraryPath } ?? false
        let hasLibrary = libraryReady && !sameFile
        let hasForage = forage != nil

        if hasForage, !hasLibrary {
            openForageInEditor()
            return
        }
        if hasForage, hasLibrary {
            switch askLibraryOrForage() {
            case .forage:
                openForageInEditor()
                return
            case .library:
                break
            case .cancel:
                return
            }
        }
        guard let item else { return }
        guard let file = resolveEditFile(for: item) else { return }
        guard let app = resolveEditorApp() else { return }
        let editingOriginal = file.path == item.markdownPath
        showFileInReaderForEdit(original: editingOriginal)
        liveEditPath = file.path
        startWatching()
        tileReaderForLiveEdit()
        openFile(file, in: app)
        statusText = editingOriginal
            ? "Editing the original — yourMark shows that file"
            : "Editing the translation — yourMark shows that file"
    }

    private enum EditPick { case library, forage, cancel }

    private func askLibraryOrForage() -> EditPick {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("Which file should yourMark show?")
        alert.informativeText = L("Edit opens that one file in the editor beside this window.")
        alert.addButton(withTitle: L("Library"))
        alert.addButton(withTitle: L("FORAGE"))
        alert.addButton(withTitle: L("Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .library
        case .alertSecondButtonReturn: return .forage
        default: return .cancel
        }
    }

    private func openForageInEditor() {
        writeForageFile()
        guard let file = forageEditURL else {
            errorMessage = L("No FORAGE file yet.")
            return
        }
        guard let app = resolveEditorApp() else { return }
        liveEditPath = file.path
        startWatching()
        tileReaderForLiveEdit()
        openFile(file, in: app)
        statusText = L("Editing the FORAGE note")
    }

    /// Edit is one file. Close SIDE BY SIDE and put that file in the reader.
    private func showFileInReaderForEdit(original: Bool) {
        if sideBySide {
            leaveSideBySide(restoreTranslation: !original)
        }
        if original {
            restoreOriginalPreview()
        } else if let text = translateMarkdown {
            applyDisplayLines(text)
        }
    }

    private func resolveEditFile(for item: LibraryItem) -> URL? {
        let original = URL(fileURLWithPath: item.markdownPath)
        guard FileManager.default.fileExists(atPath: original.path) else {
            errorMessage = "That Markdown file is not on disk anymore."
            return nil
        }
        var want = editTarget
        let hasTranslation = translateMarkdown != nil || translationCopyURL(beside: original) != nil
        if want == "ask", hasTranslation {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Which file should yourMark show?"
            alert.informativeText = "Edit opens that one file in the editor beside this window — not both languages at the same time. SIDE BY SIDE turns off so you can see the file you pick."
            alert.addButton(withTitle: "Original")
            alert.addButton(withTitle: "Translation")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                want = "original"
            case .alertSecondButtonReturn:
                want = "translation"
            default:
                return nil
            }
        }
        if want == "translation" {
            if let file = ensureTranslationFile(beside: original) {
                return file
            }
            errorMessage = "Translate the file first if you want to edit the translation."
            return nil
        }
        return original
    }

    private func ensureTranslationFile(beside original: URL) -> URL? {
        if let text = translateMarkdown {
            if let existing = translationCopyURL(beside: original) {
                quietWatch(8)
                do {
                    try text.write(to: existing, atomically: true, encoding: .utf8)
                } catch {
                    errorMessage = "Could not write the translation file to edit."
                    return nil
                }
                rememberDiskFingerprint(path: existing.path, text: text)
                liveEditPath = existing.path
                startWatching()
                return existing
            }
            return saveTranslationCopy()
        }
        return translationCopyURL(beside: original)
    }

    func rememberDiskFingerprint(path: String, text: String) {
        lastDiskFingerprint[path] = "\(text.utf8.count)-\(text.hashValue)"
    }

    private func translationCopyURL(beside original: URL) -> URL? {
        if !liveEditPath.isEmpty, liveEditPath != original.path,
           FileManager.default.fileExists(atPath: liveEditPath) {
            return URL(fileURLWithPath: liveEditPath)
        }
        let folder = original.deletingLastPathComponent()
        let stem = original.deletingPathExtension().lastPathComponent
        let lang = translateTo
        let dest = folder.appendingPathComponent("\(stem).\(lang).md")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        return nil
    }

    private func resolveEditorApp() -> URL? {
        if editorChoice == "custom" {
            if let app = resolveCustomEditor() { return app }
            pickCustomEditor()
            return resolveCustomEditor()
        }
        if editorChoice == "marktext" {
            if let app = Self.markTextAppURL() { return app }
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Install MarkText to edit"
            alert.informativeText = "MarkText is the editor we recommend on Windows. It is also free on the Mac. Install it from GitHub, then press Edit again."
            alert.addButton(withTitle: "Get MarkText")
            alert.addButton(withTitle: "Not now")
            if alert.runModal() == .alertFirstButtonReturn {
                openMarkTextDownload()
            }
            return nil
        }
        if let app = Self.markEditAppURL() { return app }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Install MarkEdit to edit"
        alert.informativeText = "yourMark is a reader. MarkEdit is a free, open-source Mac editor for Markdown.\n\nInstall it, then press Edit again. Or pick MarkText or another editor in Settings."
        alert.addButton(withTitle: "Get MarkEdit")
        alert.addButton(withTitle: "Choose another editor")
        alert.addButton(withTitle: "Not now")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openMarkEditDownload()
        case .alertSecondButtonReturn:
            pickCustomEditor()
            return resolveCustomEditor()
        default:
            break
        }
        return nil
    }

    private func tileReaderForLiveEdit() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
                ?? NSApp.mainWindow
        else { return }
        var frame = screen
        frame.origin = screen.origin
        frame.size.width = max(780, (screen.width * 0.5).rounded())
        frame.size.height = screen.height
        window.setFrame(frame, display: true, animate: false)
    }

    private func openFile(_ file: URL, in app: URL) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: cfg) { _, _ in }
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

    static func markTextAppURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.github.marktext.marktext") {
            return url
        }
        for name in ["MarkText.app", "marktext.app"] {
            let path = "/Applications/\(name)"
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
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

    /// Converted Markdown and new forage notes. Custom cloud folder when the user picked one.
    var forageHome: URL {
        if filePlace == "custom", !customFolderPath.isEmpty {
            return FolderAccess.accessPath(customFolderPath)
                ?? URL(fileURLWithPath: customFolderPath)
        }
        return convertedDir
    }

    func forageScanRoots() -> [URL] {
        let home = forageHome.standardizedFileURL
        if filePlace == "custom" {
            return [home]
        }
        return [convertedDir.standardizedFileURL]
    }

    /// A stored folder wins over “On this Mac only”, which used to keep writing to Application Support.
    private func useChosenFolderIfPresent() {
        guard !customFolderPath.isEmpty else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: customFolderPath, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        if filePlace != "custom" {
            filePlace = "custom"
            UserDefaults.standard.set("custom", forKey: "filePlace")
        }
    }

    /// Move leftover Application Support/Converted items into the folder the user chose.
    private func migrateHiddenConvertedIfNeeded() {
        guard filePlace == "custom", !customFolderPath.isEmpty else { return }
        let dest = forageHome.standardizedFileURL
        let src = convertedDir.standardizedFileURL
        guard dest.path != src.path else { return }
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: src,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), !kids.isEmpty else { return }
        var moved = 0
        for child in kids {
            let target = dest.appendingPathComponent(child.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                rewriteStoredPaths(from: child.path, to: target.path)
                continue
            }
            do {
                try fm.moveItem(at: child, to: target)
                rewriteStoredPaths(from: child.path, to: target.path)
                moved += 1
            } catch {
                continue
            }
        }
        saveLibrary()
        if moved > 0 {
            statusText = "Moved converted files into \(dest.lastPathComponent)"
        }
    }

    private func rewriteStoredPaths(from old: String, to new: String) {
        let oldStd = URL(fileURLWithPath: old).standardizedFileURL.path
        let newStd = URL(fileURLWithPath: new).standardizedFileURL.path
        for i in library.indices {
            if library[i].markdownPath == oldStd || library[i].markdownPath.hasPrefix(oldStd + "/") {
                library[i].markdownPath = newStd + library[i].markdownPath.dropFirst(oldStd.count)
            }
            if !library[i].sourcePath.isEmpty,
               library[i].sourcePath == oldStd || library[i].sourcePath.hasPrefix(oldStd + "/") {
                library[i].sourcePath = newStd + library[i].sourcePath.dropFirst(oldStd.count)
            }
        }
        if hunterSavedPath == oldStd || hunterSavedPath.hasPrefix(oldStd + "/") {
            hunterSavedPath = newStd + hunterSavedPath.dropFirst(oldStd.count)
            UserDefaults.standard.set(hunterSavedPath, forKey: "hunterSavedPath")
        }
    }

    func pickOutputFolder(firstRun: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = firstRun
            ? "Pick or create a yourMark folder. iCloud Drive or another cloud folder is safer."
            : "Converted Markdown and forage notes will be saved here."
        let cloud = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: cloud.path) {
            panel.directoryURL = cloud
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = FolderAccess.access(url)
        FolderAccess.saveCustomFolder(url)
        customFolderPath = url.path
        filePlace = "custom"
        persistAskSettings()
        migrateHiddenConvertedIfNeeded()
        scanForageVault()
        startWatching()
        ingestInboxMarkdown(announce: false)
        statusText = "Saving Markdown in \(url.lastPathComponent)"
        if firstRun { finishFolderChoice() }
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
                statusText = "Saved on this Mac only (App Store cannot write next to that file)"
                return fallback.appendingPathComponent(stem + ".md")
            }
            return folder.appendingPathComponent(stem + ".md")
        }
    }

    /// Child processes do not inherit security-scoped access. Copy into the container first.
    private static func sandboxReadable(_ original: URL) -> (url: URL, cleanup: URL?) {
        guard Distribution.isAppStore else { return (original, nil) }
        _ = original.startAccessingSecurityScopedResource()
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ym-in-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(original.lastPathComponent)
            try fm.copyItem(at: original, to: dest)
            return (dest, dir)
        } catch {
            return (original, nil)
        }
    }

    private static func removeSandboxCopy(_ work: (url: URL, cleanup: URL?)) {
        guard let dir = work.cleanup else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    private func startWatching() {
        watcher.watchInbox(forageHome.path)
        var paths: [String] = []
        for item in library {
            if !item.markdownPath.isEmpty {
                paths.append(item.markdownPath)
            }
            if !item.sourcePath.isEmpty {
                paths.append(item.sourcePath)
            }
        }
        if !liveEditPath.isEmpty {
            paths.append(liveEditPath)
        }
        if let item = library.first(where: { $0.id == selectedLibraryID }) {
            let figs = URL(fileURLWithPath: item.markdownPath)
                .deletingLastPathComponent()
                .appendingPathComponent("figures", isDirectory: true)
            if FileManager.default.fileExists(atPath: figs.path) {
                paths.append(figs.path)
            }
        }
        let unique = Set(paths.filter { !$0.isEmpty })
        guard unique != watchedPaths else { return }
        watchedPaths = unique
        watcher.update(paths: Array(unique))
    }

    private static func isFigureWatchPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if url.lastPathComponent == "figures" { return true }
        return url.deletingLastPathComponent().lastPathComponent == "figures"
    }

    func quietWatch(_ seconds: TimeInterval = 4) {
        ignoreWatchUntil = Date().addingTimeInterval(seconds)
    }

    private func fileDidChange(_ path: String) {
        if isBusy { return }
        if Date() < ignoreWatchUntil { return }
        watchDebounce?.cancel()
        watchDebounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            if self.isBusy || Date() < self.ignoreWatchUntil { return }
            if Self.isFigureWatchPath(path) {
                PreviewImageCache.shared.dropAll()
                self.figureStamp += 1
                return
            }
            let home = self.forageHome.standardizedFileURL.path
            if path == home || path.hasPrefix(home + "/") {
                self.ingestInboxMarkdown(announce: true)
                if path == home { return }
            }
            if self.library.contains(where: { $0.sourcePath == path && $0.markdownPath != path }) {
                self.setStatus("Original file changed on disk", important: true)
                return
            }
            await self.refreshPreviewFromDisk(path)
        }
    }

    /// Reload Markdown from disk without resetting translation or SIDE BY SIDE.
    private func refreshPreviewFromDisk(_ path: String) async {
        guard FileManager.default.isReadableFile(atPath: path) else { return }
        guard let item = library.first(where: { $0.id == selectedLibraryID }) else { return }
        let originalPath = item.markdownPath
        let editingOriginal = path == originalPath
        let editingTranslation = !liveEditPath.isEmpty
            && path == liveEditPath
            && path != originalPath
            && (sideBySide || translateMarkdown != nil)
        guard editingOriginal || editingTranslation else { return }

        let scanHeadings = editingTranslation || item.bookmarks.isEmpty
        let pack = await Task.detached(priority: .utility) {
            AppModel.buildPreview(path: path, scanHeadings: scanHeadings)
        }.value
        if pack.missing { return }
        let fp = "\(pack.text.utf8.count)-\(pack.text.hashValue)"
        if lastDiskFingerprint[path] == fp { return }
        lastDiskFingerprint[path] = fp

        if editingOriginal {
            previewMarkdown = pack.text
            previewLines = pack.lines
            previewHeadings = pack.headings
            previewBaseURL = pack.base
            previewBackup = (pack.lines, pack.headings)
            previewTruncated = pack.truncated
            hunterTextMemo.removeAll(keepingCapacity: true)
            setStatus("Updated from disk", important: true)
            return
        }
        translateMarkdown = pack.text
        translateLines = pack.lines
        if let stored = library.first(where: { $0.markdownPath == path }), !stored.bookmarks.isEmpty {
            translateHeadings = relocateOutline(stored.bookmarks, in: pack.lines)
        } else if let src = library.first(where: { $0.id == selectedLibraryID }), !src.bookmarks.isEmpty {
            translateHeadings = relocateOutline(src.bookmarks, in: pack.lines)
        } else {
            translateHeadings = pack.headings
        }
        if !sideBySide {
            applyDisplayLines(pack.text)
        }
        setStatus("Translation updated from disk", important: true)
    }

    func isNewestLibraryCard(_ item: LibraryItem) -> Bool {
        guard item.id != Self.guideID else { return false }
        return library
            .filter { $0.id != Self.guideID }
            .max(by: { $0.addedAt < $1.addedAt })?
            .id == item.id
    }

    func insertLibraryItem(
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
        let key = originKey(for: item)
        let existing = library.firstIndex(where: { originKey(for: $0) == key && isOriginMaster($0) })
        if !isOriginMaster(item), let idx = existing {
            library.insert(item, at: idx + 1)
        } else {
            library.insert(item, at: 0)
            enforceLibraryCap(keeping: item.id)
        }
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
            guard item.bookmarks.isEmpty, !Self.isForagePath(item.markdownPath) else { return nil }
            return (idx, item.markdownPath)
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

    func saveLibrary() {
        libraryViewCache = nil
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

}
