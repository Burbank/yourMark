import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    private var deck: DeckTheme { DeckTheme.resolve(model.appearance, scheme) }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            TopBar()
            if model.installingEngine || model.enginePath == nil {
                EngineBanner()
            }
            if let tag = model.appUpdateTag {
                AppUpdateBanner(tag: tag)
            }
            Group {
                if model.showSettings {
                    EnginePanel()
                } else if model.showHelp {
                    HelpView()
                } else if model.selectedTool == .convert {
                    ConvertPanel()
                } else {
                    LibraryPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusBar
        }
        .background(deck.page)
        .foregroundStyle(deck.ink)
        .environment(\.deck, deck)
        .preferredColorScheme(model.colorScheme)
        .background(FileDropCatcher { urls in model.openIncoming(urls) })
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { model.draggingFiles },
            set: { model.draggingFiles = $0 }
        )) { providers in
            ingestDrop(providers)
            return true
        }
        .overlay {
            if model.draggingFiles {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(deck.cyan, lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .task { await model.bootstrap() }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func ingestDrop(_ providers: [NSItemProvider]) -> Bool {
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let value = item as? URL {
                    url = value
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                guard let url, ConvertibleKind.allows(url) else { return }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { model.openIncoming(urls) }
        }
        return true
    }

    private var statusBar: some View {
        HStack {
            Text(model.statusText)
                .foregroundStyle(deck.muted)
                .lineLimit(1)
            Spacer()
            if model.isBusy || model.installingEngine {
                ProgressView().controlSize(.small).padding(.trailing, 8)
            }
            if model.selectedTool == .convert, model.enginePath != nil, !model.showSettings, !model.showHelp {
                Button("Convert") {
                    Task { await model.convertQueued() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy || model.jobs.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(deck.btn)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(deck.panel)
        .overlay(Rectangle().frame(height: deck.border).foregroundStyle(deck.line), alignment: .top)
    }
}

private struct EngineBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if model.installingEngine {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installing Microsoft MarkItDown")
                        .font(.body.weight(.bold))
                    Text("Official package from PyPI — not a copy inside the app, so their updates still reach you.")
                        .font(.caption)
                        .foregroundStyle(deck.muted)
                }
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(deck.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Converter not installed yet")
                        .font(.body.weight(.bold))
                    Text(model.installLog.isEmpty
                         ? "yourMark will download Microsoft MarkItDown. Needs a network connection."
                         : model.installLog)
                        .font(.caption)
                        .foregroundStyle(deck.muted)
                        .lineLimit(3)
                }
                Spacer()
                Button("Install converter") {
                    Task { await model.installEngine() }
                }
                .buttonStyle(.borderedProminent)
                .tint(deck.btn)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(deck.field)
        .overlay(Rectangle().frame(height: deck.border).foregroundStyle(deck.line), alignment: .bottom)
    }
}

private struct AppUpdateBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck
    let tag: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.app")
                .foregroundStyle(deck.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("yourMark \(tag) is on GitHub")
                    .font(.body.weight(.bold))
                Text("This app is \(AppUpdates.currentVersion). Open the release page to download.")
                    .font(.caption)
                    .foregroundStyle(deck.muted)
            }
            Spacer()
            Button("GitHub") { model.openAppUpdate() }
                .buttonStyle(.borderedProminent)
                .tint(deck.btn)
            Button("Later") { model.dismissAppUpdate() }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(deck.field)
        .overlay(Rectangle().frame(height: deck.border).foregroundStyle(deck.line), alignment: .bottom)
    }
}

private struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 0) {
                Text("yourMark")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("PDFs → Markdown")
                    .font(.caption)
                    .foregroundStyle(deck.muted)
            }
            Spacer()
            ForEach(AppTool.allCases) { tool in
                Button(tool.rawValue) { model.selectTool(tool) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(model.selectedTool == tool && !model.showSettings && !model.showHelp
                                  ? deck.btn : deck.panel)
                    )
                    .foregroundStyle(model.selectedTool == tool && !model.showSettings && !model.showHelp
                                     ? deck.btnText : deck.ink)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(deck.line, lineWidth: model.selectedTool == tool ? 0 : deck.border)
                    )
                    .font(.body.weight(.bold))
            }
            HStack(spacing: 0) {
                ForEach(["system", "bright", "dim"], id: \.self) { mode in
                    Button(mode.uppercased()) { model.setAppearance(mode) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(model.appearance == mode ? deck.btn : deck.panel)
                        .foregroundStyle(model.appearance == mode ? deck.btnText : deck.muted)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Button {
                model.toggleSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.body.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(model.showSettings ? deck.btn : deck.panel))
                    .foregroundStyle(model.showSettings ? deck.btnText : deck.ink)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: model.showSettings ? 0 : deck.border))
            }
            .buttonStyle(.plain)
            Button {
                model.toggleHelp()
            } label: {
                Text("i")
                    .font(.body.weight(.bold))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 8).fill(model.showHelp ? deck.btn : deck.panel))
                    .foregroundStyle(model.showHelp ? deck.btnText : deck.ink)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: model.showHelp ? 0 : deck.border))
            }
            .buttonStyle(.plain)
            .help("Guide")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(deck.panel)
        .overlay(Rectangle().frame(height: deck.border).foregroundStyle(deck.line), alignment: .bottom)
    }

    @ViewBuilder
    private var icon: some View {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(deck.navy)
                .frame(width: 32, height: 32)
                .overlay(Text("M").font(.headline.bold()).foregroundStyle(.white))
        }
    }
}

struct ConvertPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("CONVERT")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(deck.cyan)
                Text("Drop a PDF")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text("Drop a PDF anywhere on this window — Library, Bookmarks, the header. yourMark switches here and starts. Microsoft MarkItDown writes Markdown on this Mac. Keep the original file.")
                    .foregroundStyle(deck.muted)
                    .frame(maxWidth: 520, alignment: .leading)

                DropZone(
                    title: "Drop PDFs, Word, PowerPoint, Excel",
                    subtitle: "Or choose files. Markdown is saved next to the original unless you pick another folder in Settings."
                ) {
                    model.pickFiles()
                } onDrop: { urls in
                    model.openIncoming(urls)
                }

                if model.jobs.contains(where: { $0.needsOCR && ($0.status == .queued || $0.status == .running) }) {
                    HStack(alignment: .top, spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OCR first — this takes a little longer")
                                .font(.body.weight(.bold))
                            Text("This PDF is a scan (a picture of a page, no text layer). yourMark writes the words first, then Microsoft MarkItDown converts. Page pictures are kept so tables, arrows, and diagrams still show.")
                                .font(.caption)
                                .foregroundStyle(deck.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(deck.field)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(deck.cyan, lineWidth: deck.border))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if !model.jobs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.jobs) { job in
                            HStack {
                                Image(systemName: icon(for: job.status))
                                    .foregroundStyle(color(for: job.status))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.sourceURL.lastPathComponent)
                                        .font(.body.weight(.bold))
                                    Text(job.detail)
                                        .font(.caption)
                                        .foregroundStyle(job.needsOCR && job.status == .running ? deck.cyan : deck.muted)
                                        .lineLimit(3)
                                }
                                Spacer()
                                if let out = job.outputURL {
                                    Button("Reveal") { model.reveal(out) }
                                        .buttonStyle(.borderless)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(deck.panel)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(deck.line, lineWidth: deck.border))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(deck.page)
    }

    private func icon(for status: ConvertJob.Status) -> String {
        switch status {
        case .queued: return "tray"
        case .running: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func color(for status: ConvertJob.Status) -> Color {
        switch status {
        case .queued: return deck.muted
        case .running: return deck.cyan
        case .done: return Color(hex: "3a6840")
        case .failed: return Color(hex: "8a3a2c")
        }
    }
}

struct LibraryPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    private var selected: LibraryItem? {
        model.library.first(where: { $0.id == model.selectedLibraryID })
    }

    private var headingBookmarks: [ManualBookmark] {
        var used = Set<String>()
        var items: [ManualBookmark] = []
        for line in model.previewMarkdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            guard s.hasPrefix("#") else { continue }
            var level = 0
            for ch in s {
                if ch == "#" { level += 1 } else { break }
            }
            guard (1...3).contains(level) else { continue }
            let title = s.drop(while: { $0 == "#" || $0 == " " }).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, title != "Outline" else { continue }
            var key = title.lowercased()
            if used.contains(key) { key += "-\(items.count)" }
            used.insert(key)
            items.append(ManualBookmark(title: title, level: level, pageIndex: nil))
        }
        return items
    }

    private var outline: [ManualBookmark] {
        let fromPdf = selected?.bookmarks ?? []
        return fromPdf.isEmpty ? headingBookmarks : fromPdf
    }

    var body: some View {
        GeometryReader { geo in
            let libraryW = max(180, geo.size.width * 0.20)
            let marksW = max(140, geo.size.width * 0.15)
            HSplitView {
                libraryColumn
                    .frame(minWidth: 160, idealWidth: libraryW, maxWidth: max(280, geo.size.width * 0.36))

                HSplitView {
                    bookmarksColumn
                        .frame(minWidth: 120, idealWidth: marksW, maxWidth: max(240, geo.size.width * 0.32))
                    markdownColumn
                        .frame(minWidth: 280)
                }
            }
        }
        .background(deck.page)
        .safeAreaInset(edge: .bottom) {
            AskStrip()
        }
    }

    private var libraryColumn: some View {
        List {
            ForEach(model.library) { item in
                LibraryCard(item: item)
                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            model.removeLibrary(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Open") { model.selectLibrary(item) }
                        Button("Show in Finder") { model.revealLibrary(item) }
                        Divider()
                        Button("Delete", role: .destructive) { model.removeLibrary(item) }
                    }
            }
            .onMove { model.moveLibrary(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(deck.page)
    }

    private var bookmarksColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bookmarks")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(deck.cyan)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            if outline.isEmpty {
                Text("No outline. Scanned PDFs need OCR first, or the source had no bookmarks/headings.")
                    .font(.caption)
                    .foregroundStyle(deck.muted)
                    .padding(12)
            }
            List(outline) { item in
                Button {
                    model.jumpToBookmark(item)
                } label: {
                    Text(item.title)
                        .padding(.leading, CGFloat((item.level - 1) * 10))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .foregroundStyle(deck.ink)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(deck.panel)
    }

    private var markdownColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let lines = model.previewMarkdown.isEmpty
                        ? ["Select a converted file."]
                        : model.previewMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(20)
            }
            .background(deck.field)
            .onChange(of: model.scrollToLine) { _, line in
                if let line {
                    withAnimation { proxy.scrollTo(line, anchor: .top) }
                }
            }
        }
    }
}

private struct LibraryCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck
    let item: LibraryItem

    var body: some View {
        Button {
            model.selectLibrary(item)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.id == AppModel.guideID ? "GUIDE" : "MARKDOWN")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(deck.cyan)
                    Text(item.title)
                        .font(.body.weight(.bold))
                        .foregroundStyle(deck.ink)
                        .multilineTextAlignment(.leading)
                    Text(item.sourceName)
                        .font(.caption)
                        .foregroundStyle(deck.muted)
                }
                Spacer(minLength: 8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(deck.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        model.selectedLibraryID == item.id ? deck.cyan : deck.line,
                        lineWidth: deck.border
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

private struct AskStrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    private var hasResult: Bool { !model.askAnswer.isEmpty || !model.askError.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.askHasKey ? "Your model · \(model.askModel)" : "Ask this chapter · from the file")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(deck.cyan)
                Spacer()
                Picker("Chapter", selection: Binding(
                    get: { model.askChapter },
                    set: { model.askChapter = $0 }
                )) {
                    Text("Entire file").tag("Entire file")
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }
            HStack(spacing: 8) {
                TextField("What does this chapter say about…", text: Binding(
                    get: { model.askQuestion },
                    set: { model.askQuestion = $0 }
                ))
                .textFieldStyle(.plain)
                .padding(8)
                .background(deck.panel)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
                .onSubmit { Task { await model.runAsk() } }
                Button(model.askBusy ? "Asking…" : hasResult ? "Clear" : "Ask") {
                    if hasResult {
                        model.clearAsk()
                    } else {
                        Task { await model.runAsk() }
                    }
                }
                .disabled(model.askBusy || (!hasResult && model.askQuestion.trimmingCharacters(in: .whitespaces).isEmpty))
                .buttonStyle(.borderedProminent)
                .tint(deck.btn)
            }
            if !model.askError.isEmpty {
                Text(model.askError).font(.caption).foregroundStyle(.orange)
            }
            if !model.askAnswer.isEmpty {
                ScrollView {
                    Text(model.askAnswer)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                if AskService.chapterWasSilent(model.askAnswer) {
                    Button("Search the web") { model.searchAskOnWeb() }
                }
                if !model.askOpenAnswer.isEmpty {
                    Text("From the model — not in this file")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(deck.muted)
                    ScrollView {
                        Text(model.askOpenAnswer)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            }
        }
        .padding(12)
        .background(deck.field)
        .overlay(Rectangle().frame(height: deck.border).foregroundStyle(deck.line), alignment: .top)
    }
}

struct EnginePanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        Form {
            Section("Microsoft MarkItDown") {
                LabeledContent("Version", value: model.engineVersion)
                LabeledContent("Path") {
                    Text(model.enginePath ?? "Not found")
                        .textSelection(.enabled)
                }
                Text("The GUI does not pin or vendor the converter. About once a day it checks PyPI and upgrades if Microsoft shipped a newer package. Install / Upgrade does that immediately.")
                    .foregroundStyle(.secondary)
                Button("Install or reinstall") { Task { await model.installEngine() } }
                    .disabled(model.installingEngine)
            }
            Section("Ask AI") {
                Picker("Provider", selection: Binding(
                    get: { model.askProvider },
                    set: {
                        model.askProvider = $0
                        if $0 == "xai" {
                            model.askBaseURL = "https://api.x.ai/v1"
                            model.askModel = AskModels.defaultID(for: "xai")
                        } else if $0 == "openai" {
                            model.askBaseURL = "https://api.openai.com/v1"
                            model.askModel = AskModels.defaultID(for: "openai")
                        }
                    }
                )) {
                    Text("xAI (Grok)").tag("xai")
                    Text("OpenAI").tag("openai")
                    Text("Custom").tag("custom")
                }
                if model.askProvider == "custom" {
                    TextField("Model", text: Binding(
                        get: { model.askModel },
                        set: { model.askModel = $0 }
                    ))
                    TextField("Base URL", text: Binding(
                        get: { model.askBaseURL },
                        set: { model.askBaseURL = $0 }
                    ))
                } else {
                    Picker("Model", selection: Binding(
                        get: { model.askModel },
                        set: { model.askModel = $0 }
                    )) {
                        ForEach(AskModels.list(for: model.askProvider), id: \.id) { m in
                            Text("\(m.label)    \(m.note)").tag(m.id)
                        }
                    }
                }
                SecureField("API key", text: Binding(
                    get: { model.askKeyDraft },
                    set: { model.askKeyDraft = $0 }
                ))
                Text("Stored in the Keychain on this Mac. Sent only to the provider you pick when you Ask.")
                    .foregroundStyle(.secondary)
                Toggle("If the chapter does not provide an answer, also show a model summary", isOn: Binding(
                    get: { model.askWebFallback },
                    set: {
                        model.askWebFallback = $0
                        UserDefaults.standard.set($0, forKey: "askWebFallback")
                    }
                ))
                HStack {
                    Button("Save key") { model.persistAskSettings() }
                    Button("Clear key", role: .destructive) { model.clearAskKey() }
                }
            }
            Section("Scanned PDFs") {
                Toggle("OCR scans before MarkItDown", isOn: Binding(
                    get: { model.ocrEnabled },
                    set: {
                        model.ocrEnabled = $0
                        UserDefaults.standard.set($0, forKey: "ocrEnabled")
                    }
                ))
                Text("Microsoft MarkItDown only reads a text layer. A scan is a picture of a page, so tables, arrows, and photos would vanish. OCR writes the words first — that takes a little longer — then MarkItDown runs. Page pictures are kept so diagrams still show.")
                    .foregroundStyle(.secondary)
                LabeledContent("OCRmyPDF") {
                    Text(OcrService.ocrmypdfPath() ?? "Not installed — using Apple Live Text")
                        .textSelection(.enabled)
                }
                Button("Install OCRmyPDF via Homebrew") {
                    Task { await model.installOcrmypdf() }
                }
                .disabled(model.installingEngine)
            }
            Section("Converted files") {
                Picker("Save Markdown", selection: Binding(
                    get: { model.filePlace },
                    set: {
                        model.filePlace = $0
                        if $0 == "custom" { model.pickOutputFolder() }
                        else { model.persistAskSettings() }
                    }
                )) {
                    Text("Next to the original PDF").tag("beside")
                    Text("yourMark library folder").tag("library")
                    Text("Choose a folder…").tag("custom")
                }
                if model.filePlace == "custom", !model.customFolderPath.isEmpty {
                    Text(model.customFolderPath)
                        .font(.caption)
                        .textSelection(.enabled)
                    Button("Change folder") { model.pickOutputFolder() }
                }
            }
            Section("Actions") {
                Button("Recheck converter") { Task { await model.bootstrap() } }
                Button("Upgrade engine") { Task { await model.upgradeEngine() } }
                    .disabled(model.isBusy)
            }
            if !model.lastUpgradeLog.isEmpty {
                Section("Last upgrade") {
                    Text(model.lastUpgradeLog)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .scrollContentBackground(.hidden)
        .background(deck.page)
        .foregroundStyle(deck.ink)
    }
}

struct DropZone: View {
    @Environment(\.deck) private var deck
    let title: String
    let subtitle: String
    var onClick: () -> Void
    var onDrop: ([URL]) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(deck.cyan)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(deck.muted)
                .multilineTextAlignment(.center)
            Button("Choose files", action: onClick)
                .buttonStyle(.borderedProminent)
                .tint(deck.btn)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(deck.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundStyle(hovering ? deck.cyan : deck.line)
        )
        .onDrop(of: [.fileURL], isTargeted: $hovering) { providers in
            let lock = NSLock()
            var urls: [URL] = []
            let group = DispatchGroup()
            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    let url: URL?
                    if let value = item as? URL {
                        url = value
                    } else if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = nil
                    }
                    guard let url else { return }
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
            group.notify(queue: .main) {
                if !urls.isEmpty { onDrop(urls) }
            }
            return true
        }
    }
}
