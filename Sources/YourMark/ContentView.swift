import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            TopBar()
            if model.installingEngine || model.enginePath == nil {
                SetupPane()
            } else {
                Group {
                    switch model.selectedTool {
                    case .convert:
                        ConvertPanel()
                    case .library:
                        LibraryPanel()
                    case .settings:
                        EnginePanel()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text(model.statusText)
                    .foregroundStyle(DeckTheme.muted)
                    .lineLimit(1)
                Spacer()
                if model.isBusy || model.installingEngine {
                    ProgressView().controlSize(.small).padding(.trailing, 8)
                }
                if model.selectedTool == .convert, model.enginePath != nil {
                    Button("Convert") {
                        Task { await model.convertQueued() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || model.jobs.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(DeckTheme.navy)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(DeckTheme.page)
        .preferredColorScheme(model.colorScheme)
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
}

private struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 0) {
                Text("yourMark")
                    .font(.title3.weight(.bold))
                Text("PDFs → Markdown")
                    .font(.caption)
                    .foregroundStyle(DeckTheme.muted)
            }
            Spacer()
            ForEach(AppTool.allCases) { tool in
                Button(tool.rawValue) { model.selectedTool = tool }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(model.selectedTool == tool ? DeckTheme.navy : DeckTheme.panel)
                    )
                    .foregroundStyle(model.selectedTool == tool ? Color.white : DeckTheme.ink)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DeckTheme.line, lineWidth: model.selectedTool == tool ? 0 : 2)
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
                        .background(model.appearance == mode ? DeckTheme.navy : DeckTheme.panel)
                        .foregroundStyle(model.appearance == mode ? Color.white : DeckTheme.muted)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DeckTheme.line, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DeckTheme.panel)
        .overlay(Rectangle().frame(height: 2).foregroundStyle(DeckTheme.line), alignment: .bottom)
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
                .fill(DeckTheme.navy)
                .frame(width: 32, height: 32)
                .overlay(Text("M").font(.headline.bold()).foregroundStyle(.white))
        }
    }
}

private struct SetupPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("INSTALL CONVERTER")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DeckTheme.cyan)
            Text("Microsoft MarkItDown")
                .font(.title.bold())
            Text("yourMark is the window. The converter is Microsoft’s official package, installed on this Mac from PyPI — not a copy bundled in the app. That way you get their updates.")
                .foregroundStyle(DeckTheme.muted)
                .frame(maxWidth: 520, alignment: .leading)
            if model.installingEngine {
                ProgressView("Installing…")
                Text(model.installLog)
                    .font(.caption.monospaced())
                    .foregroundStyle(DeckTheme.muted)
                    .textSelection(.enabled)
            } else {
                Button("Install Microsoft MarkItDown") {
                    Task { await model.installEngine() }
                }
                .buttonStyle(.borderedProminent)
                .tint(DeckTheme.navy)
                .controlSize(.large)
                if !model.installLog.isEmpty {
                    Text(model.installLog)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ConvertPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DropZone(
                    title: "Drop PDFs, papers, lecture notes, slides",
                    subtitle: "PDF, DOCX, PPTX, XLSX, HTML, EPUB — Microsoft MarkItDown writes Markdown beside the original"
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
                                        .font(.body.weight(.bold))
                                    Text(job.detail)
                                        .font(.caption)
                                        .foregroundStyle(DeckTheme.muted)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if let out = job.outputURL {
                                    Button("Reveal") { model.reveal(out) }
                                        .buttonStyle(.borderless)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DeckTheme.panel)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DeckTheme.line, lineWidth: 2))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                Text("Keep the original file. Markdown is for search and asking a chapter.")
                    .font(.caption)
                    .foregroundStyle(DeckTheme.muted)
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
        case .queued: return DeckTheme.muted
        case .running: return DeckTheme.cyan
        case .done: return Color(red: 0.23, green: 0.41, blue: 0.25)
        case .failed: return Color(red: 0.54, green: 0.23, blue: 0.17)
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
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.library) { item in
                        Button {
                            model.selectLibrary(item)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("MARKDOWN")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(DeckTheme.cyan)
                                    Text(item.title)
                                        .font(.body.weight(.bold))
                                        .foregroundStyle(DeckTheme.ink)
                                    Text(item.sourceName)
                                        .font(.caption)
                                        .foregroundStyle(DeckTheme.muted)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "folder")
                                    .foregroundStyle(DeckTheme.muted)
                                    .onTapGesture { model.revealLibrary(item) }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DeckTheme.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        model.selectedLibraryID == item.id ? DeckTheme.cyan : DeckTheme.line,
                                        lineWidth: 2
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Show in Finder") { model.revealLibrary(item) }
                            if !item.sourcePath.isEmpty {
                                Button("Show original") {
                                    model.reveal(URL(fileURLWithPath: item.sourcePath))
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
            .frame(minWidth: 220)

            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bookmarks")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DeckTheme.cyan)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    if outline.isEmpty {
                        Text("No outline. Scanned PDFs need OCR first, or the source had no bookmarks/headings.")
                            .font(.caption)
                            .foregroundStyle(DeckTheme.muted)
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
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
                .background(DeckTheme.panel)
                .frame(minWidth: 180, idealWidth: 220)

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
                    .background(DeckTheme.field)
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
                Text(model.askHasKey ? "Your model · \(model.askModel)" : "Ask this chapter · from the file")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DeckTheme.cyan)
                Spacer()
                Text(model.askChapter)
                    .font(.caption)
                    .foregroundStyle(DeckTheme.muted)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                TextField("What does this chapter say about…", text: Binding(
                    get: { model.askQuestion },
                    set: { model.askQuestion = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.runAsk() } }
                Button(model.askBusy ? "Asking…" : (!model.askAnswer.isEmpty || !model.askError.isEmpty) ? "Clear" : "Ask") {
                    if !model.askAnswer.isEmpty || !model.askError.isEmpty {
                        model.clearAsk()
                    } else {
                        Task { await model.runAsk() }
                    }
                }
                .disabled(model.askBusy || (model.askAnswer.isEmpty && model.askError.isEmpty && model.askQuestion.trimmingCharacters(in: .whitespaces).isEmpty))
                .buttonStyle(.borderedProminent)
                .tint(DeckTheme.navy)
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
                        .foregroundStyle(DeckTheme.muted)
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
        .background(DeckTheme.field)
        .overlay(Rectangle().frame(height: 2).foregroundStyle(DeckTheme.line), alignment: .top)
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
                Text("The GUI does not pin or vendor the converter. Install / Upgrade pulls the current package from PyPI.")
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
        .scrollContentBackground(.hidden)
        .background(DeckTheme.page)
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
                .foregroundStyle(DeckTheme.cyan)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(DeckTheme.muted)
                .multilineTextAlignment(.center)
            Button("Choose files", action: onClick)
                .buttonStyle(.borderedProminent)
                .tint(DeckTheme.navy)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(DeckTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundStyle(hovering ? DeckTheme.cyan : DeckTheme.line)
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
    static let navy = Color(red: 0.12, green: 0.29, blue: 0.45)
    static let cyan = Color(red: 0, green: 0.63, blue: 0.89)
    static let ink = Color(red: 0.17, green: 0.15, blue: 0.11)
    static let muted = Color(red: 0.37, green: 0.34, blue: 0.29)
    static let line = Color(red: 0.76, green: 0.68, blue: 0.57)
    static let panel = Color(red: 0.90, green: 0.85, blue: 0.77)
    static let field = Color(red: 0.93, green: 0.89, blue: 0.81)
    static let page = Color(red: 0.84, green: 0.78, blue: 0.69)
    static let accent = cyan
    static let bg = page
}
