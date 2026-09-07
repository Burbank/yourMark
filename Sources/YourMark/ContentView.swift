import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(selection: $model.selectedTool) {
                Section("yourMark") {
                    ForEach(AppTool.allCases) { tool in
                        Label(tool.rawValue, systemImage: tool.systemImage)
                            .tag(tool)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) {
                EngineFooter()
                    .padding(12)
            }
        } detail: {
            VStack(spacing: 0) {
                header

                Divider()

                Group {
                    switch model.selectedTool {
                    case .convert:
                        ConvertPanel()
                    case .library:
                        LibraryPanel()
                    case .engine:
                        EnginePanel()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack {
                    Text(model.statusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if model.isBusy {
                        ProgressView().controlSize(.small).padding(.trailing, 8)
                    }
                    if model.selectedTool == .convert {
                        Button("Convert") {
                            Task { await model.convertQueued() }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.isBusy || model.jobs.isEmpty || model.enginePath == nil)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(DeckTheme.bg)
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

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: model.selectedTool.systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DeckTheme.accent)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedTool.rawValue)
                    .font(.title2.weight(.semibold))
                Text(model.selectedTool.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

private struct EngineFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(model.enginePath == nil ? "MarkItDown missing" : model.engineVersion)
                    .font(.caption.weight(.medium))
            } icon: {
                Image(systemName: model.enginePath == nil ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(model.enginePath == nil ? .orange : Color(red: 0.56, green: 0.81, blue: 0.48))
            }
            Text(model.enginePath ?? "uv tool install 'markitdown[all]'")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ConvertPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DropZone(
                    title: "Drop PDFs, papers, lecture notes, slides",
                    subtitle: "PDF, DOCX, PPTX, XLSX, HTML, EPUB — converted beside the original as .md"
                ) {
                    model.pickFiles()
                } onDrop: { urls in
                    model.enqueue(urls)
                }

                if !model.jobs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.jobs) { job in
                            HStack {
                                Image(systemName: icon(for: job.status))
                                    .foregroundStyle(color(for: job.status))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.sourceURL.lastPathComponent)
                                    Text(job.detail)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if let out = job.outputURL {
                                    Button("Reveal") { model.reveal(out) }
                                        .buttonStyle(.borderless)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                        }
                    }
                }

                Text("Keep the original file. Markdown is for search and asking a chapter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
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
        case .queued: return .secondary
        case .running: return DeckTheme.accent
        case .done: return Color(red: 0.56, green: 0.81, blue: 0.48)
        case .failed: return .orange
        }
    }
}

struct LibraryPanel: View {
    @Environment(AppModel.self) private var model

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
        HSplitView {
            List(model.library, selection: Binding(
                get: { model.selectedLibraryID },
                set: { id in
                    if let id, let item = model.library.first(where: { $0.id == id }) {
                        model.selectLibrary(item)
                    }
                }
            )) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline)
                        Text(item.sourceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button {
                        model.revealLibrary(item)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                }
                .tag(item.id)
                .contextMenu {
                    Button("Show in Finder") { model.revealLibrary(item) }
                    if !item.sourcePath.isEmpty {
                        Button("Show original") {
                            model.reveal(URL(fileURLWithPath: item.sourcePath))
                        }
                    }
                }
            }
            .frame(minWidth: 200)

            HSplitView {
                List {
                    Section("Bookmarks") {
                        if outline.isEmpty {
                            Text("No outline. Scanned PDFs need OCR first, or the source had no bookmarks/headings.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(outline) { item in
                            Button {
                                model.jumpToBookmark(item)
                            } label: {
                                Text(item.title)
                                    .font(.callout)
                                    .padding(.leading, CGFloat((item.level - 1) * 10))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minWidth: 180, idealWidth: 220)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            let lines = model.previewMarkdown.isEmpty
                                ? ["Select a converted file."]
                                : model.previewMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: model.scrollToLine) { _, line in
                        if let line {
                            withAnimation {
                                proxy.scrollTo(line, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            AskStrip()
        }
    }
}

private struct AskStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.askHasKey ? "Ask this chapter" : "Ask needs an API key (Engine)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DeckTheme.accent)
                Spacer()
                if model.askHasKey {
                    Text(model.askChapter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                TextField("What does this chapter say about…", text: Binding(
                    get: { model.askQuestion },
                    set: { model.askQuestion = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(!model.askHasKey)
                .onSubmit { Task { await model.runAsk() } }
                Button(model.askBusy ? "Asking…" : (!model.askAnswer.isEmpty || !model.askError.isEmpty) ? "Clear" : "Ask") {
                    if !model.askAnswer.isEmpty || !model.askError.isEmpty {
                        model.clearAsk()
                    } else {
                        Task { await model.runAsk() }
                    }
                }
                .disabled(!model.askHasKey || model.askBusy || (model.askAnswer.isEmpty && model.askError.isEmpty && model.askQuestion.trimmingCharacters(in: .whitespaces).isEmpty))
                .buttonStyle(.borderedProminent)
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
                        .foregroundStyle(.secondary)
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
        .background(.bar)
    }
}

struct EnginePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Microsoft MarkItDown") {
                LabeledContent("Version", value: model.engineVersion)
                LabeledContent("Path") {
                    Text(model.enginePath ?? "Not found")
                        .textSelection(.enabled)
                }
                Text("The GUI does not pin or vendor the converter. Upgrade pulls the current package from PyPI.")
                    .foregroundStyle(.secondary)
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
                Text("Off by default. Chapter answers stay from the file. The extra summary is labelled “not in this file”.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save key") { model.persistAskSettings() }
                    Button("Clear key", role: .destructive) { model.clearAskKey() }
                }
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
                Text("Next to the original keeps the PDF and the Markdown in the same folder.")
                    .foregroundStyle(.secondary)
            }
            Section("What you get") {
                LabeledContent("Tables") {
                    Text("Yes — GFM tables when the PDF has a real table. Colours / merged cells flatten.")
                }
                LabeledContent("Pictures") {
                    Text("Reading order, not page layout. Word/PPTX usually include them. PDF figures need extras.")
                }
                LabeledContent("Outline") {
                    Text("Yes — PDF bookmarks + Markdown headings. Click to jump, like Preview.app.")
                }
            }
            Section("Actions") {
                Button("Recheck") { Task { await model.bootstrap() } }
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
    }
}

struct DropZone: View {
    let title: String
    let subtitle: String
    var onClick: () -> Void
    var onDrop: ([URL]) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(DeckTheme.accent)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose files", action: onClick)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundStyle(hovering ? DeckTheme.accent : Color.secondary.opacity(0.4))
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

enum DeckTheme {
    static let accent = Color(red: 0, green: 0.63, blue: 0.89)
    static let bg = Color(nsColor: .windowBackgroundColor)
}
