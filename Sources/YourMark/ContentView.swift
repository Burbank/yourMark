import AppKit
import ImageIO
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
        .background(FileDropCatcher(
            onHover: { model.draggingFiles = $0 },
            onURLs: { model.openIncoming($0) }
        ))
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
        .sheet(isPresented: Binding(
            get: { model.showInstallSheet },
            set: { if !$0 { Task { await model.skipFirstRunInstall() } } }
        )) {
            FirstRunInstallSheet()
                .environment(model)
                .environment(\.deck, deck)
        }
        .sheet(isPresented: Binding(
            get: { model.showOCRSheet },
            set: { if !$0 { model.skipOCRSheet() } }
        )) {
            FirstRunOCRSheet()
                .environment(model)
                .environment(\.deck, deck)
        }
        .sheet(isPresented: Binding(
            get: { model.showDoclingPrompt },
            set: { if !$0 { model.skipDoclingInstall() } }
        )) {
            DoclingPromptSheet()
                .environment(model)
                .environment(\.deck, deck)
        }
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

private struct DoclingPromptSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This PDF has graphics")
                .font(.title2.weight(.bold))
            Text("Tables, photos, arrows, and diagrams need IBM Docling (layout OCR). Install it in this app, then conversion starts. Without it, Microsoft MarkItDown only keeps the words.")
                .foregroundStyle(deck.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.pendingGraphics.map(\.lastPathComponent).joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(deck.muted)
            HStack {
                Button("Convert without Docling") {
                    model.skipDoclingInstall()
                }
                Spacer()
                Button("Install Docling, then convert") {
                    Task { await model.acceptDoclingInstall() }
                }
                .buttonStyle(.borderedProminent)
                .tint(deck.btn)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480)
        .background(deck.page)
    }
}

private struct FirstRunOCRSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install OCR for scans")
                .font(.title2.weight(.bold))
            Text("If your PDFs are scans or have tables, photos, and arrows, install the OCR extras now. Open Settings → Scanned PDFs, or install IBM Docling from this window. Ordinary digital PDFs do not need this.")
                .foregroundStyle(deck.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("This download needs the internet and can take a few minutes.")
                .font(.caption)
                .foregroundStyle(deck.muted)
            HStack {
                Button("Later") { model.skipOCRSheet() }
                Button("Open scan settings") { model.openScanSettings() }
                Spacer()
                Button("Install OCR now") {
                    Task { await model.acceptOCRInstall() }
                }
                .buttonStyle(.borderedProminent)
                .tint(deck.btn)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 500)
        .background(deck.page)
    }
}

private struct FirstRunInstallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install converters in this app")
                .font(.title2.weight(.bold))
            Text("We recommend installing everything from this window — not from Terminal or Homebrew by hand. That keeps paths and updates in one place.")
                .foregroundStyle(deck.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Label("Microsoft MarkItDown — ordinary PDFs, Word, PowerPoint", systemImage: "doc.richtext")
                Label("IBM Docling — scans and PDFs with graphics (tables, figures, OCR)", systemImage: "photo.on.rectangle")
            }
            .font(.callout)
            Text("First download needs the internet and can take a few minutes. You can also do this later in Settings.")
                .font(.caption)
                .foregroundStyle(deck.muted)
            HStack {
                Button("Not now") {
                    Task { await model.skipFirstRunInstall() }
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Install in this app") {
                    Task { await model.acceptFirstRunInstall() }
                }
                .buttonStyle(.borderedProminent)
                .tint(deck.btn)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480)
        .background(deck.page)
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
                Text("Drop a PDF anywhere on this window — Library, Bookmarks, the header. yourMark switches here and starts. Microsoft MarkItDown writes the words; pictures from the PDF are added in one extra pass. Keep the original file.")
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
                            Text("Layout OCR first — this takes a little longer")
                                .font(.body.weight(.bold))
                            Text("This PDF is a scan. yourMark uses IBM Docling to recover tables, columns, and figures (not just the words). First time it may download models. Microsoft MarkItDown still handles normal PDFs.")
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
        model.previewHeadings
    }

    private var outline: [ManualBookmark] {
        let fromPdf = selected?.bookmarks ?? []
        return fromPdf.isEmpty ? headingBookmarks : fromPdf
    }

    @AppStorage("splitLibrary") private var libFrac = 0.20
    @AppStorage("splitMarks") private var marksFrac = 0.15

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let libW = max(160, w * libFrac)
            let marksW = max(120, w * marksFrac)
            HStack(spacing: 0) {
                libraryColumn
                    .frame(width: libW)
                SplitDrag(fraction: $libFrac, min: 0.14, max: 0.36, total: w, color: deck.line)
                bookmarksColumn
                    .frame(width: marksW)
                SplitDrag(fraction: $marksFrac, min: 0.10, max: 0.32, total: w, color: deck.line)
                markdownColumn
                    .frame(maxWidth: .infinity)
            }
        }
        .background(deck.page)
        .safeAreaInset(edge: .bottom) {
            AskStrip()
        }
    }

    private struct SplitDrag: View {
    @Binding var fraction: Double
    var min: Double
    var max: Double
    var total: CGFloat
    var color: Color
    @State private var origin: Double?

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 1)
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if origin == nil { origin = fraction }
                        let next = (origin ?? fraction) + Double(value.translation.width / total)
                        fraction = Swift.min(max, Swift.max(min, next))
                    }
                    .onEnded { _ in origin = nil }
            )
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
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(markdownSections) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                                markdownLine(line)
                            }
                        }
                        .id(section.id)
                    }
                }
                .padding(20)
            }
            .background(deck.field)
            .onChange(of: model.scrollToLine) { _, line in
                guard let line else { return }
                let target = markdownSections.last(where: { $0.id <= line })?.id ?? line
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
        }
    }

    @ViewBuilder
    private func markdownLine(_ line: String) -> some View {
        if let img = markdownImage(line, base: model.previewBaseURL) {
            VStack(alignment: .leading, spacing: 4) {
                PreviewPicture(url: img.url)
                if !img.alt.isEmpty {
                    Text(img.alt)
                        .font(.caption)
                        .foregroundStyle(deck.muted)
                }
            }
            .padding(.vertical, 6)
        } else {
            Text(line.isEmpty ? " " : line)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var markdownSections: [PreviewSection] {
        if model.previewSections.isEmpty {
            return [PreviewSection(id: 0, lines: ["Select a converted file."])]
        }
        return model.previewSections
    }
}

private func markdownImage(_ line: String, base: URL?) -> (alt: String, url: URL)? {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard t.hasPrefix("!["), let mid = t.range(of: "]("), t.contains(")") else { return nil }
    let alt = String(t[t.index(t.startIndex, offsetBy: 2)..<mid.lowerBound])
    let after = t[mid.upperBound...]
    guard let end = after.firstIndex(of: ")") else { return nil }
    var path = String(after[..<end])
    if let space = path.firstIndex(of: " ") {
        path = String(path[..<space])
    }
    path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    if path.hasPrefix("data:") { return nil }
    if path.hasPrefix("http://") || path.hasPrefix("https://"), let url = URL(string: path) {
        return (alt, url)
    }
    guard let base else { return nil }
    let url = path.hasPrefix("/")
        ? URL(fileURLWithPath: path)
        : base.appendingPathComponent(path)
    return (alt, url)
}

/// Decode off the main thread and cache a small thumbnail. Loading full JPEGs
/// in the view body is what froze the window after a large convert finished.
private struct PreviewPicture: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .task(id: url) {
            if let cached = PreviewImageCache.shared.image(for: url) {
                image = cached
                return
            }
            let data = await Task.detached(priority: .utility) {
                PreviewImageCache.thumbnailData(url)
            }.value
            if let data, let loaded = NSImage(data: data) {
                PreviewImageCache.shared.store(loaded, for: url)
                image = loaded
            }
        }
    }
}

private final class PreviewImageCache: @unchecked Sendable {
    static let shared = PreviewImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    private init() {
        cache.countLimit = 40
        cache.totalCostLimit = 40 * 1024 * 1024
    }

    func image(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func store(_ img: NSImage, for url: URL) {
        cache.setObject(img, forKey: url as NSURL, cost: Int(img.size.width * img.size.height))
    }

    static func thumbnailData(_ url: URL, maxPixel: CGFloat = 900) -> Data? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts) else { return nil }
        let thumb: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumb as CFDictionary) else {
            return nil
        }
        let destData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            destData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            dest,
            cg,
            [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return nil }
        return destData as Data
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
            if model.settingsFocus == "ocr" {
                Section {
                    Text("Install OCR here — Scanned PDFs, below. IBM Docling handles scans, tables, and figures.")
                        .foregroundStyle(.secondary)
                }
            }
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
                Text("Installs Microsoft MarkItDown, the converter for ordinary PDFs and Office files.")
                    .font(.caption)
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
                        model.persistAskSettings()
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
                        set: {
                            model.askModel = $0
                            model.persistAskSettings()
                        }
                    )) {
                        ForEach(AskModels.list(for: model.askProvider), id: \.id) { m in
                            Text("\(m.label)    \(m.note)").tag(m.id)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("API key")
                    HStack(alignment: .center, spacing: 10) {
                        SecureField(
                            model.askHasKey ? "Key locked in — paste a new one to replace" : "Paste your API key here",
                            text: Binding(
                                get: { model.askKeyDraft },
                                set: {
                                    model.askKeyDraft = $0
                                    model.askKeyHint = ""
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.lockAskKey() }
                        Button("Enter") { model.lockAskKey() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .help("Lock this API key on this Mac")
                    }
                    Text("Paste the key, then press Enter. That locks it on this Mac so you do not have to paste it again.")
                        .foregroundStyle(.secondary)
                    if !model.askKeyHint.isEmpty {
                        Text(model.askKeyHint)
                            .foregroundStyle(.orange)
                    }
                    if model.askHasKey {
                        Label("Your key is locked in. yourMark will use it when you Ask. You do not need to paste it again.", systemImage: "lock.fill")
                            .foregroundStyle(.green)
                        Button("Clear key", role: .destructive) { model.clearAskKey() }
                    }
                }
                Toggle("If the chapter does not provide an answer, also show a model summary", isOn: Binding(
                    get: { model.askWebFallback },
                    set: {
                        model.askWebFallback = $0
                        UserDefaults.standard.set($0, forKey: "askWebFallback")
                    }
                ))
                Toggle("Automatically add chapters with AI when the file has no outline", isOn: Binding(
                    get: { model.aiChaptersEnabled },
                    set: {
                        model.aiChaptersEnabled = $0
                        UserDefaults.standard.set($0, forKey: "aiChaptersEnabled")
                    }
                ))
                Text("Uses your Ask key after conversion. Inserts ## headings where chapters clearly start. Off unless you tick it. Needs a saved key.")
                    .foregroundStyle(.secondary)
            }
            Section("Scanned PDFs") {
                Toggle("Layout OCR for scans", isOn: Binding(
                    get: { model.ocrEnabled },
                    set: {
                        model.ocrEnabled = $0
                        UserDefaults.standard.set($0, forKey: "ocrEnabled")
                    }
                ))
                Text("A scan is a picture of a page. OCRmyPDF and Apple Live Text only read words — they do not rebuild tables or columns. For scans, yourMark uses IBM Docling (layout, TableFormer, figures). That takes a little longer. Normal PDFs still go to Microsoft MarkItDown. If Docling is missing, we fall back to OCRmyPDF / Live Text and keep page pictures.")
                    .foregroundStyle(.secondary)
                LabeledContent("Docling") {
                    Text(model.doclingPath == nil ? "Not installed yet" : "Installed and ready")
                }
                if let path = model.doclingPath {
                    Text(path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                Button(model.doclingPath == nil ? "Install Docling (layout models)" : "Reinstall Docling") {
                    Task { await model.installDocling() }
                }
                .disabled(model.installingEngine)
                Text(model.doclingPath == nil
                     ? "Needed for scans and PDFs with tables or pictures. Install from this app, not Terminal."
                     : "Docling is installed on this Mac and ready. Scanned PDFs will use it. Press Reinstall only if conversion of scans starts failing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("OCRmyPDF fallback") {
                    Text(model.ocrmypdfPath == nil ? "Not installed — Apple Live Text" : "Installed and ready")
                }
                if let path = model.ocrmypdfPath {
                    Text(path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                Button(model.ocrmypdfPath == nil ? "Install OCRmyPDF via Homebrew" : "Reinstall OCRmyPDF") {
                    Task { await model.installOcrmypdf() }
                }
                .disabled(model.installingEngine)
                Text(model.ocrmypdfPath == nil
                     ? "Optional backup. Without it, this Mac can still read scans with Apple Live Text."
                     : "OCRmyPDF is installed on this Mac as a backup if Docling cannot run. Press Reinstall only if something stops working.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 4) {
                    Button("Check for update of the main app") {
                        Task { await model.checkUpdates(force: true) }
                    }
                    Text("Looks on GitHub for a newer yourMark and offers the download.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Button("Check for update of the processing engine") {
                        Task { await model.upgradeEngine() }
                    }
                    .disabled(model.isBusy)
                    Text("Pulls the latest Microsoft MarkItDown from PyPI. Does not change the yourMark app itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Button("Recheck converter") { Task { await model.bootstrap() } }
                    Text("Confirms MarkItDown is on this Mac after an install or a failed launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .onAppear { model.refreshOCRTools() }
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
