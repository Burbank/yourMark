import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class AppModel {
    var selectedTool: AppTool = .convert
    var enginePath: String?
    var engineVersion: String = "checking…"
    var isBusy = false
    var statusText = "Ready"
    var errorMessage: String?
    var showHelp = false
    var jobs: [ConvertJob] = []
    var library: [LibraryItem] = []
    var selectedLibraryID: UUID?
    var previewMarkdown: String = ""
    var lastUpgradeLog: String = ""
    var scrollToLine: Int?

    let service = MarkItDownService()
    private let libraryURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = appSupport.appendingPathComponent("yourMark", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        libraryURL = dir.appendingPathComponent("library.json")
        loadLibrary()
    }

    func bootstrap() async {
        let status = await service.refreshStatus()
        enginePath = status.path
        engineVersion = status.version
        statusText = status.path == nil ? "Engine not found" : "MarkItDown \(status.version)"
    }

    func clearError() { errorMessage = nil }

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
            let output = await service.suggestedOutput(for: input)
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
            await bootstrap()
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

    private func addToLibrary(source: URL, markdown: URL, bookmarks: [ManualBookmark]) {
        let values = try? markdown.resourceValues(forKeys: [.fileSizeKey])
        let item = LibraryItem(
            id: UUID(),
            title: markdown.deletingPathExtension().lastPathComponent,
            sourceName: source.lastPathComponent,
            markdownPath: markdown.path,
            addedAt: Date(),
            byteCount: Int64(values?.fileSize ?? 0),
            bookmarks: bookmarks
        )
        library.removeAll { $0.markdownPath == item.markdownPath }
        library.insert(item, at: 0)
        saveLibrary()
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
