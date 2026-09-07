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
        if status.path == nil, !installingEngine {
            statusText = "Installing Microsoft MarkItDown…"
            await installEngine()
        } else if status.path != nil {
            statusText = "MarkItDown \(status.version)"
        }
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

    var showInfoButton: Bool {
        !library.contains(where: { $0.id == Self.guideID })
    }

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

    Swipe this card **to the left** when you are done — an **i** in the header keeps this same guide. Right-click a card for Open, Show in Finder, and Delete.

    ## Why Markdown

    A PDF is a picture of a page. Markdown is the words, in order, as plain text you can search and edit.

    That is why it works so well with AI. A model can read a chapter, quote it, and tell you when the file is silent — instead of guessing at columns or a scan. You can paste one heading into Grok or ChatGPT, keep notes in Obsidian, or search a whole course. Tables stay tables. Headings stay an outline.

    Keep the original PDF. Markdown is the working copy.

    ## Convert

    Open **Convert** and drop a PDF, Word, PowerPoint, or Excel file. yourMark asks Microsoft MarkItDown (the official PyPI package) to write Markdown. The first launch installs that converter for you — it is not frozen inside the app, so Microsoft’s updates still reach you.

    ## Bookmarks

    The Bookmarks pane is the PDF outline when the file has one, otherwise headings. Click to jump, like Preview.

    ## Tables and figures

    Real tables become Markdown tables. Pictures sit in reading order, not the original page x/y. Scans need OCR extras.

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

    Swipe this card left to delete it. The **i** in the header shows this guide whenever you need it.
    """

    func persistAskSettings() {
        UserDefaults.standard.set(askProvider, forKey: "askProvider")
        UserDefaults.standard.set(askModel, forKey: "askModel")
        UserDefaults.standard.set(askBaseURL, forKey: "askBaseURL")
        UserDefaults.standard.set(askWebFallback, forKey: "askWebFallback")
        UserDefaults.standard.set(filePlace, forKey: "filePlace")
        UserDefaults.standard.set(customFolderPath, forKey: "customFolder")
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
        let allowed = urls.filter { Self.isConvertible($0) }
        guard !allowed.isEmpty else { return }
        selectedTool = .convert
        enqueue(allowed)
        NSApp.activate(ignoringOtherApps: true)
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
        enqueue(panel.urls)
    }

    func enqueue(_ urls: [URL]) {
        for url in urls where Self.isConvertible(url) {
            if jobs.contains(where: { $0.sourceURL == url }) { continue }
            jobs.append(ConvertJob(
                id: UUID(),
                sourceURL: url,
                outputURL: nil,
                status: .queued,
                detail: url.path,
                startedAt: nil
            ))
        }
        statusText = jobs.count == 1
            ? "Queued \(urls.first?.lastPathComponent ?? "file")"
            : "Queued \(jobs.filter { $0.status == .queued }.count) files"
    }

    func convertQueued() async {
        clearError()
        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await service.resolveEngine()
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Engine missing"
            return
        }

        for index in jobs.indices where jobs[index].status == .queued || jobs[index].status == .failed {
            let input = jobs[index].sourceURL
            jobs[index].status = .running
            jobs[index].startedAt = Date()
            statusText = "Converting \(input.lastPathComponent)…"
            let output = outputURL(for: input)
            do {
                let url = try await service.convert(input: input, output: output)
                let bookmarks = PdfSidecar.bookmarks(from: input)
                if !bookmarks.isEmpty, var text = try? String(contentsOf: url, encoding: .utf8) {
                    if !text.contains("## Outline") {
                        text = PdfSidecar.outlineMarkdown(bookmarks) + text
                        try? text.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
                jobs[index].status = .done
                jobs[index].outputURL = url
                jobs[index].detail = bookmarks.isEmpty
                    ? url.path
                    : "\(bookmarks.count) bookmarks · \(url.lastPathComponent)"
                addToLibrary(source: input, markdown: url, bookmarks: bookmarks)
            } catch {
                jobs[index].status = .failed
                jobs[index].detail = error.localizedDescription
            }
        }
        statusText = jobs.contains(where: { $0.status == .failed }) ? "Finished with errors" : "Done"
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

    func selectLibrary(_ item: LibraryItem) {
        selectedLibraryID = item.id
        selectedTool = .library
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
        let lines = previewMarkdown.split(separator: "\n", omittingEmptySubsequences: false)
        let needle = bookmark.title.trimmingCharacters(in: .whitespaces)
        if let idx = lines.firstIndex(where: {
            $0.localizedCaseInsensitiveContains(needle)
        }) {
            scrollToLine = idx
            return
        }
        if let page = bookmark.pageIndex {
            let label = "p. \(page + 1)"
            if let idx = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains(label) }) {
                scrollToLine = idx
            }
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
        selectLibrary(item)
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

    static func isConvertible(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["pdf", "docx", "pptx", "xlsx", "xls", "html", "htm", "md", "txt", "epub"].contains(ext)
    }
}
