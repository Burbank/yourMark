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
            if !Distribution.isAppStore, model.installingEngine || model.enginePath == nil {
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
            if model.selectedTool == .convert, !model.showSettings, !model.showHelp {
                StatusBar()
            }
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
            get: { model.showMarkEditSheet },
            set: { if !$0 { model.skipMarkEditSheet() } }
        )) {
            FirstRunMarkEditSheet()
                .environment(model)
                .environment(\.deck, deck)
        }
        .sheet(isPresented: Binding(
            get: { model.showCrashSheet },
            set: { if !$0 { model.skipCrashSheet() } }
        )) {
            CrashReportSheet()
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

}

private struct StatusBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        HStack {
            Spacer()
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
            Text("This PDF has tables or pictures. The layout scanner (IBM Docling) reads those better than Apple Live Text. Get it in this app, then conversion starts. Or convert with the words only.")
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
                Button("Get the layout scanner, then convert") {
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

private struct FirstRunMarkEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A free editor for your Markdown")
                .font(.title2.weight(.bold))
            Text("yourMark is a reader. To change a converted file, we recommend MarkEdit — a native Mac Markdown editor, free and open source. Press Edit in the reader after it is installed.")
                .foregroundStyle(deck.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("brew install --cask markedit")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            HStack {
                Button("Not now") { model.skipMarkEditSheet() }
                Spacer()
                Button("Get MarkEdit") { model.acceptMarkEditRecommend() }
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

private struct CrashReportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("yourMark closed unexpectedly")
                .font(.title2.weight(.bold))
            Text("macOS saved a crash report. Copy it and send it however you like — you do not need a GitHub account. Nothing leaves this Mac until you choose. API keys and documents are not included.")
                .foregroundStyle(deck.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = model.pendingCrash?.summary {
                Text(summary)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            HStack {
                Button("Don't offer this") { model.neverOfferCrashes() }
                Spacer()
                Button("Not now") { model.skipCrashSheet() }
                    .keyboardShortcut(.cancelAction)
                Button("Copy report") { model.copyPendingCrash() }
                    .buttonStyle(.borderedProminent)
                    .tint(deck.btn)
                    .keyboardShortcut(.defaultAction)
            }
            Button("I have a GitHub account") { model.sendPendingCrash() }
                .buttonStyle(.plain)
                .foregroundStyle(deck.muted)
        }
        .padding(28)
        .frame(width: 520)
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
            Spacer(minLength: 8)
            if !bannerText.isEmpty {
                HStack(spacing: 8) {
                    if bannerLive {
                        ProgressView().controlSize(.small)
                    }
                    Text(bannerText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(deck.cyan)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(deck.field))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
                .frame(minWidth: 0, maxWidth: 420, alignment: .trailing)
                .layoutPriority(-1)
                .help(bannerText)
                .transition(.opacity)
            }
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
        .animation(.easeInOut(duration: 0.2), value: bannerText)
    }

    private var bannerLive: Bool {
        let text = model.statusText
        guard !text.isEmpty, text != "Ready" else { return false }
        return model.isBusy || model.installingEngine
            || text.hasSuffix("…")
            || text.hasSuffix("...")
    }

    private var bannerText: String {
        if bannerLive { return model.statusText }
        if model.toastVisible { return model.toastText }
        return ""
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
                Text("Drop a PDF anywhere on this window — Library, Bookmarks, the header. yourMark switches here and starts. Microsoft MarkItDown writes the words; pictures from the PDF are added in one extra pass. Word, PowerPoint, Excel, pictures, ZIP folders, HTML, EPUB, CSV, RTF, and Outlook mail work too. Keep the original file.")
                    .foregroundStyle(deck.muted)
                    .frame(maxWidth: 520, alignment: .leading)

                DropZone(
                    title: "Drop PDFs, Word, PowerPoint, Excel, pictures, ZIP…",
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

    private var outlineFromPdf: Bool {
        !(selected?.bookmarks ?? []).isEmpty
    }

    private var outline: [ManualBookmark] {
        model.documentOutline
    }

    @AppStorage("splitLibrary") private var libFrac = 0.20
    @AppStorage("splitMarks") private var marksFrac = 0.15
    @AppStorage("previewPointSize") private var previewPointSize = 16.0
    @AppStorage("figurePreviewSize") private var figurePreviewSize = 600.0
    @AppStorage("previewRendered") private var previewRendered = true
    @State private var figureHover: FigureHover?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let libW = max(160, w * libFrac)
            let marksW = max(120, w * marksFrac)
            let readW = max(240, w - libW - marksW - 2)
            HStack(spacing: 0) {
                libraryColumn
                    .frame(width: libW, height: h, alignment: .top)
                SplitDrag(fraction: $libFrac, min: 0.14, max: 0.36, total: w, color: deck.line)
                bookmarksColumn
                    .frame(width: marksW, height: h, alignment: .top)
                SplitDrag(fraction: $marksFrac, min: 0.10, max: 0.32, total: w, color: deck.line)
                markdownColumn(width: readW)
                    .frame(width: readW, height: h, alignment: .top)
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
            Text(selected?.title ?? "Markdown")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(deck.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            Text(outlineFromPdf ? "Bookmarks · from the PDF" : "Bookmarks")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(deck.cyan)
                .padding(.horizontal, 12)
                .padding(.top, 2)
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

    private func markdownColumn(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            markdownHeader(narrow: width < 860)
            ScrollViewReader { proxy in
                List(model.previewLines) { row in
                    markdownLine(row.text)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                        .listRowBackground(deck.field)
                        .id(row.id)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(deck.field)
                .onChange(of: model.scrollToLine) { _, line in
                    guard let line else { return }
                    proxy.scrollTo(line, anchor: .top)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let figureHover {
                    HoverThumb(
                        url: figureHover.url,
                        caption: figureHover.alt,
                        previewSize: figurePreviewSize
                    )
                    .padding(16)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func markdownHeader(narrow: Bool) -> some View {
        Group {
            if narrow {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        translateTools
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        readerTools
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    translateTools
                    Spacer(minLength: 8)
                    readerTools
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(deck.panel)
        .overlay(Rectangle().frame(height: deck.border).foregroundStyle(deck.line), alignment: .bottom)
    }

    @ViewBuilder
    private var translateTools: some View {
        TranslateLangPicker(
            title: TranslateLang.label(for: model.translateFrom),
            includeAuto: true,
            code: Binding(
                get: { model.translateFrom },
                set: {
                    model.translateFrom = $0
                    model.persistTranslateSettings()
                }
            )
        )
        Text("translate to")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(deck.muted)
            .fixedSize()
        TranslateLangPicker(
            title: TranslateLang.label(for: model.translateTo),
            includeAuto: false,
            code: Binding(
                get: { model.translateTo },
                set: {
                    model.translateTo = $0
                    model.persistTranslateSettings()
                }
            )
        )
        Picker("", selection: Binding(
            get: { model.translateLayout },
            set: {
                model.translateLayout = $0
                model.persistTranslateSettings()
            }
        )) {
            Text("Below").tag("below")
            Text("Replace").tag("replace")
        }
        .pickerStyle(.segmented)
        .frame(width: 132)
        .help("Below each paragraph keeps the original. Replace shows only the translation.")
        Menu {
            Button("This chapter") {
                Task { await model.runTranslate(entireFile: false) }
            }
            Button("Entire file") {
                Task { await model.runTranslate(entireFile: true) }
            }
        } label: {
            Text(model.translateBusy ? "Translating…" : "Translate")
                .font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.translateBusy || selected == nil)
        .help(model.translateReadyHint)
        if model.translateMarkdown != nil {
            Button("Save a copy") { model.saveTranslationCopy() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .help("Write a second file. The original Markdown stays as it is.")
            Button("Clear") { model.clearTranslation() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
        }
    }

    @ViewBuilder
    private var readerTools: some View {
        Button {
            previewPointSize = max(12, previewPointSize - 1)
        } label: {
            Text("A").font(.system(size: 10, weight: .bold))
        }
        .buttonStyle(.plain)
        .help("Smaller text")
        Slider(value: $previewPointSize, in: 12...26, step: 1)
            .frame(width: 88)
            .controlSize(.mini)
            .help("Text size")
        Button {
            previewPointSize = min(26, previewPointSize + 1)
        } label: {
            Text("A").font(.system(size: 16, weight: .bold))
        }
        .buttonStyle(.plain)
        .help("Larger text")
        Image(systemName: "photo")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(deck.muted)
            .help("Picture preview size")
        Slider(value: $figurePreviewSize, in: 240...900, step: 20)
            .frame(width: 88)
            .controlSize(.mini)
            .help("Picture preview size when you hover a figure link. Default is large.")
        Button {
            figurePreviewSize = min(900, figurePreviewSize + 40)
        } label: {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.plain)
        .help("Larger picture preview")
        Button(previewRendered ? "Rendered" : "Plain") {
            previewRendered.toggle()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(previewRendered ? deck.btn : deck.field))
        .foregroundStyle(previewRendered ? deck.btnText : deck.ink)
        .help("Rendered shows headings. Plain shows the raw Markdown.")
        if let item = selected {
            Button("Edit") {
                model.openInMarkEdit(item)
            }
            .buttonStyle(.plain)
            .font(.body.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(deck.btn))
            .foregroundStyle(deck.btnText)
            .help("Open this file in MarkEdit, a free Markdown editor")
            Button("Finder") {
                model.revealLibrary(item)
            }
            .buttonStyle(.plain)
            .font(.body.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
            .help("Show this file in Finder")
        }
    }

    @ViewBuilder
    private func markdownLine(_ line: String) -> some View {
        let size = CGFloat(previewPointSize)
        if line.hasPrefix(TranslateService.marker) {
            let rest = String(line.dropFirst(TranslateService.marker.count))
            translatedMarkdownLine(rest, size: size)
        } else if let img = markdownImage(line, base: model.previewBaseURL) {
            FigureLink(url: img.url, alt: img.alt, hover: $figureHover)
        } else if !previewRendered {
            Text(line.isEmpty ? " " : line)
                .font(.system(size: size, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let page = pageMark(line) {
            HStack(spacing: 8) {
                Rectangle().fill(deck.line).frame(height: 1)
                Text("Page \(page)")
                    .font(.system(size: max(10, size - 4), weight: .semibold, design: .monospaced))
                    .foregroundStyle(deck.muted)
                Rectangle().fill(deck.line).frame(height: 1)
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
        } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("<!--") {
            EmptyView()
        } else if let heading = atxHeading(line) {
            if heading.level == 1,
               heading.text.caseInsensitiveCompare(selected?.title ?? "") == .orderedSame {
                EmptyView()
            } else {
            Text(heading.text)
                .font(model.readerFont(size: headingSize(heading.level, base: size), weight: heading.level <= 2 ? .bold : .semibold))
                .foregroundStyle(deck.ink)
                .textSelection(.enabled)
                .padding(.top, heading.level <= 2 ? 14 : 8)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let callout = wholeLineBold(line) {
            Text(callout)
                .font(model.readerFont(size: size, weight: .semibold))
                .foregroundStyle(deck.ink)
                .textSelection(.enabled)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            inlineMarkdown(line, size: size)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func translatedMarkdownLine(_ line: String, size: CGFloat) -> some View {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(" ")
                .font(model.readerFont(size: size))
        } else if let heading = atxHeading(line) {
            Text(heading.text)
                .font(model.readerFont(size: headingSize(heading.level, base: size), weight: heading.level <= 2 ? .bold : .semibold))
                .foregroundStyle(deck.muted)
                .textSelection(.enabled)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            inlineMarkdown(line, size: size)
                .foregroundStyle(deck.muted)
                .textSelection(.enabled)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headingSize(_ level: Int, base: CGFloat) -> CGFloat {
        switch level {
        case 1: return base + 10
        case 2: return base + 7
        case 3: return base + 4
        case 4: return base + 2
        default: return base + 1
        }
    }

    private func inlineMarkdown(_ line: String, size: CGFloat) -> Text {
        let body = model.readerFont(size: size)
        let bold = model.readerFont(size: size, weight: .semibold)
        if line.isEmpty { return Text(" ").font(body) }
        var text = Text("")
        var rest = line
        while let start = rest.range(of: "**") {
            let before = String(rest[rest.startIndex..<start.lowerBound])
            if !before.isEmpty {
                text = text + Text(before).font(body)
            }
            let afterStart = start.upperBound
            if let end = rest.range(of: "**", range: afterStart..<rest.endIndex) {
                let chunk = String(rest[afterStart..<end.lowerBound])
                text = text + Text(chunk).font(bold)
                rest = String(rest[end.upperBound...])
            } else {
                text = text + Text("**" + String(rest[afterStart...])).font(body)
                rest = ""
            }
        }
        if !rest.isEmpty {
            text = text + Text(rest).font(body)
        }
        return text.foregroundStyle(deck.ink)
    }
}

private struct TranslateLangPicker: View {
    @Environment(\.deck) private var deck
    var title: String
    var includeAuto: Bool
    @Binding var code: String
    @State private var open = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).stroke(deck.line, lineWidth: deck.border))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if includeAuto {
                        langRow(TranslateLang.auto)
                    }
                    ForEach(TranslateLang.spoken) { lang in
                        langRow(lang)
                    }
                }
                .padding(8)
            }
            .frame(width: 220, height: 280)
        }
    }

    private func langRow(_ lang: TranslateLang) -> some View {
        Button {
            code = lang.id
            open = false
        } label: {
            HStack {
                Text(lang.label)
                Spacer()
                if code == lang.id {
                    Image(systemName: "checkmark")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func atxHeading(_ line: String) -> (level: Int, text: String)? {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard t.hasPrefix("#") else { return nil }
    var n = 0
    var i = t.startIndex
    while i < t.endIndex, t[i] == "#", n < 6 {
        n += 1
        i = t.index(after: i)
    }
    guard n > 0, i < t.endIndex, t[i].isWhitespace else { return nil }
    let text = t[i...].trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return nil }
    return (n, text)
}

private func wholeLineBold(_ line: String) -> String? {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard t.hasPrefix("**"), t.hasSuffix("**"), t.count > 4 else { return nil }
    let inner = String(t.dropFirst(2).dropLast(2))
    if inner.contains("**") { return nil }
    return inner
}

private func pageMark(_ line: String) -> String? {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard t.hasPrefix("<!-- page "), t.hasSuffix("-->") else { return nil }
    let inner = t.dropFirst(10).dropLast(3).trimmingCharacters(in: .whitespaces)
    return inner.isEmpty ? nil : inner
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

private struct FigureHover: Equatable {
    let url: URL
    let alt: String
}

/// A hyperlink in the reader. The picture is drawn in the reader overlay, not
/// in a system popover — those ignore our size and hug a tiny NSImage.
private struct FigureLink: View {
    @Environment(\.deck) private var deck
    let url: URL
    let alt: String
    @Binding var hover: FigureHover?
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Text(alt.isEmpty ? url.lastPathComponent : alt)
            .font(.system(size: 13, weight: .semibold))
            .underline()
            .foregroundStyle(deck.cyan)
            .onTapGesture {
                hover = nil
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                hoverTask?.cancel()
                if inside {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        guard !Task.isCancelled else { return }
                        hover = FigureHover(url: url, alt: alt)
                    }
                } else {
                    hover = nil
                }
            }
            .padding(.vertical, 2)
    }
}

private struct HoverThumb: View {
    @Environment(\.deck) private var deck
    let url: URL
    let caption: String
    var previewSize: Double
    @State private var image: NSImage?

    private var box: CGFloat { CGFloat(max(280, min(previewSize, 900))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        Rectangle().fill(deck.field)
                        Text("Preview…")
                            .font(.caption)
                            .foregroundStyle(deck.muted)
                    }
                }
            }
            .frame(width: box, height: box * 0.75)
            .clipped()
            Text(caption.isEmpty ? url.lastPathComponent : caption)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(deck.muted)
                .lineLimit(2)
                .frame(width: box, alignment: .leading)
        }
        .padding(12)
        .frame(width: box + 24)
        .background(RoundedRectangle(cornerRadius: 10).fill(deck.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(deck.line, lineWidth: deck.border))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .task(id: "\(url.path)-\(Int(box))") {
            let pixel = Int(min(1800, box * 2))
            if let cached = PreviewImageCache.shared.image(for: url, pixel: pixel) {
                image = cached
                return
            }
            let data = await Task.detached(priority: .utility) {
                PreviewImageCache.thumbnailData(url, maxPixel: CGFloat(pixel))
            }.value
            guard !Task.isCancelled else { return }
            if let data, let loaded = NSImage(data: data) {
                PreviewImageCache.shared.store(loaded, for: url, pixel: pixel)
                image = loaded
            }
        }
        .onDisappear { image = nil }
    }
}

private final class PreviewImageCache: @unchecked Sendable {
    static let shared = PreviewImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {
        cache.countLimit = 6
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    private func key(_ url: URL, pixel: Int) -> NSString {
        "\(url.path)#\(pixel)" as NSString
    }

    func image(for url: URL, pixel: Int) -> NSImage? {
        cache.object(forKey: key(url, pixel: pixel))
    }

    func store(_ img: NSImage, for url: URL, pixel: Int) {
        let cost = Int(max(1, img.size.width * img.size.height * 4))
        cache.setObject(img, forKey: key(url, pixel: pixel), cost: min(cost, 4_000_000))
    }

    /// Copy the file (do not mmap it). A mapped JPEG that is rewritten while
    /// you scroll is a SIGBUS. Then build a small thumbnail, never the full page.
    static func thumbnailData(_ url: URL, maxPixel: CGFloat = 400) -> Data? {
        autoreleasepool { thumbnailDataLocked(url, maxPixel: maxPixel) }
    }

    private static func thumbnailDataLocked(_ url: URL, maxPixel: CGFloat) -> Data? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 32, size < 8_000_000 else { return nil }
        guard let fileData = try? Data(contentsOf: url, options: [.uncached]), fileData.count > 32 else {
            return nil
        }
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(fileData as CFData, opts) else { return nil }
        let thumb: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
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
            [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary
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
                    get: {
                        let titles = model.askChapterChoices.map(\.title)
                        if model.askChapter != "Entire file",
                           !titles.contains(where: { $0.caseInsensitiveCompare(model.askChapter) == .orderedSame }) {
                            return "Entire file"
                        }
                        return model.askChapter
                    },
                    set: { model.setAskChapter($0) }
                )) {
                    Text("Entire file").tag("Entire file")
                    ForEach(model.askChapterChoices, id: \.title) { choice in
                        Text(String(repeating: "  ", count: max(0, choice.level - 1)) + choice.title)
                            .tag(choice.title)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
                .help("Ask one chapter, or the whole file")
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
                Text(model.askError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
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
            Section("This document") {
                Toggle("Remove headers and footers", isOn: Binding(
                    get: { model.stripChrome },
                    set: {
                        model.stripChrome = $0
                        UserDefaults.standard.set($0, forKey: "stripChrome")
                    }
                ))
                Text("Drops the repeating page title, page number, date, revision line, and header logos. Chapter headings and the real text stay. On by default — manuals look much cleaner.")
                    .foregroundStyle(.secondary)
            }
            Section("Reader") {
                Picker("Font", selection: Binding(
                    get: { model.previewFontName },
                    set: { model.setPreviewFont($0) }
                )) {
                    Text("Rounded (default)").tag("rounded")
                    Text("System").tag("system")
                    if AppModel.installedFontFamilies.contains("Atkinson Hyperlegible") {
                        Text("Atkinson Hyperlegible").tag("Atkinson Hyperlegible")
                    }
                    if AppModel.installedFontFamilies.contains("Atkins") {
                        Text("Atkins").tag("Atkins")
                    }
                    ForEach(AppModel.installedFontFamilies.filter { $0 != "Atkinson Hyperlegible" && $0 != "Atkins" }, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Text("Applies to the Markdown pane. Atkins and Atkinson Hyperlegible appear here if they are installed on this Mac (Font Book). Size is the A / slider / A control on the reader.")
                    .foregroundStyle(.secondary)
            }
            Section("Edit in MarkEdit") {
                Text("yourMark is a reader. To change a converted file, press Edit in the library pane. That opens MarkEdit, a free native Mac editor from the same kind of indie project as this one.")
                    .foregroundStyle(.secondary)
                if AppModel.markEditAppURL() != nil {
                    Text("MarkEdit is installed on this Mac.")
                        .foregroundStyle(.secondary)
                    Button("Open MarkEdit") {
                        if let app = AppModel.markEditAppURL() {
                            NSWorkspace.shared.open(app)
                        }
                    }
                } else {
                    Button("Get MarkEdit (free)") {
                        model.openMarkEditDownload()
                    }
                    Text("Or in Terminal: brew install --cask markedit")
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Crash reports") {
                Toggle("Offer to send crash reports", isOn: Binding(
                    get: { model.offerCrashReports },
                    set: { model.setOfferCrashReports($0) }
                ))
                Text("If yourMark closed unexpectedly, we can copy the macOS report. Paste it in a message — you do not need a GitHub account. Nothing is sent unless you choose.")
                    .foregroundStyle(.secondary)
                if CrashReports.latestAny() != nil {
                    Button("Copy last crash report") { model.sendLastCrash() }
                }
            }
            if Distribution.isAppStore {
                Section("Converter") {
                    LabeledContent("Engine", value: Distribution.converterLabel)
                    Text("Microsoft MarkItDown is included in this copy. Photographed pages use Apple Live Text. This App Store copy does not download extra software.")
                        .foregroundStyle(.secondary)
                    Button("Privacy") {
                        NSWorkspace.shared.open(Distribution.privacyURL)
                    }
                }
            }
            if model.settingsFocus == "ocr", !Distribution.isAppStore {
                Section {
                    Text("Install OCR here — Scanned PDFs, below. IBM Docling handles scans, tables, and figures.")
                        .foregroundStyle(.secondary)
                }
            }
            if !Distribution.isAppStore {
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
                    Text("xAI keys start with xai- (from console.x.ai). OpenAI keys start with sk-. Provider must match the key — yourMark will switch it for you when you press Enter.")
                        .foregroundStyle(.secondary)
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
                        Button(model.askCheckingKey ? "Testing…" : "Enter") { model.lockAskKey() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(model.askCheckingKey)
                            .help("Lock this API key on this Mac")
                    }
                    Text("Paste the key, then press Enter. yourMark sends one short test question so you know the key works before it is locked in. The key stays on this Mac. It is sent only when you ask, to the provider you pick.")
                        .foregroundStyle(.secondary)
                    if !model.askKeyHint.isEmpty {
                        Text(model.askKeyHint)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                    if model.askHasKey {
                        let kind = model.askKeyKind == "openai" ? "OpenAI" : model.askKeyKind == "xai" ? "xAI (Grok)" : "your provider"
                        let tail = model.askKeyTail.isEmpty ? "" : " Ending …\(model.askKeyTail)."
                        Label("Your \(kind) key is locked in.\(tail)", systemImage: "lock.fill")
                            .foregroundStyle(.green)
                        if model.askKeyTestPassed {
                            Label(model.askKeyTestNote.isEmpty ? "Key test passed. Ask is ready." : model.askKeyTestNote, systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("This key has not been tested yet.")
                                .foregroundStyle(.secondary)
                            Button("Test this key") { model.testLockedKey() }
                                .disabled(model.askCheckingKey)
                        }
                        if (model.askKeyKind == "openai" && model.askProvider == "xai")
                            || (model.askKeyKind == "xai" && model.askProvider == "openai") {
                            Text("This key does not match the Provider above. Press Enter after pasting again — yourMark will switch Provider to match the key.")
                                .foregroundStyle(.orange)
                        }
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
                if !Distribution.isAppStore {
                    Toggle("Read text inside pictures with your Ask key", isOn: Binding(
                        get: { model.askReadPictures },
                        set: {
                            model.askReadPictures = $0
                            UserDefaults.standard.set($0, forKey: "askReadPictures")
                        }
                    ))
                    Text("Microsoft’s markitdown-ocr plugin sends pictures to your AI so it can read labels on diagrams. Off unless you tick it. A large PDF can mean many requests and a bill. Needs a saved key. Pictures themselves are always saved locally, with or without this.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Translate") {
                Picker("Engine", selection: Binding(
                    get: { model.translateEngine },
                    set: {
                        model.translateEngine = $0
                        model.persistTranslateSettings()
                    }
                )) {
                    Text("Your Ask key").tag("ask")
                    Text("Google Translate").tag("google")
                }
                Text(model.translateEngine == "google"
                     ? "The open chapter is sent to Google when you press Translate. Convert still stays on this Mac."
                     : "The open chapter is sent to your Ask model when you press Translate. Convert still stays on this Mac.")
                    .foregroundStyle(.secondary)
                if model.translateEngine == "google" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Google Translate API key")
                        Text("Turn on Cloud Translation API in your Google Cloud project, then create an API key.")
                            .foregroundStyle(.secondary)
                        if let help = URL(string: "https://cloud.google.com/docs/authentication/api-keys") {
                            Button {
                                NSWorkspace.shared.open(help)
                            } label: {
                                HStack(spacing: 5) {
                                    Text("How to get a Google Translate key")
                                        .underline()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(deck.cyan)
                            }
                            .buttonStyle(.plain)
                            .onHover { inside in
                                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                            .help("Opens Google’s help in your browser")
                        }
                        HStack {
                            SecureField(
                                model.googleHasKey ? "Key locked in — paste a new one to replace" : "Paste your Google API key here",
                                text: Binding(
                                    get: { model.googleKeyDraft },
                                    set: { model.googleKeyDraft = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.lockGoogleTranslateKey() }
                            Button(model.googleCheckingKey ? "Testing…" : "Enter") {
                                model.lockGoogleTranslateKey()
                            }
                            .disabled(model.googleCheckingKey)
                        }
                        if !model.googleKeyHint.isEmpty {
                            Text(model.googleKeyHint)
                                .foregroundStyle(.orange)
                        }
                        if model.googleHasKey {
                            Label(
                                model.googleKeyTestNote.isEmpty ? "Google Translate key is locked in." : model.googleKeyTestNote,
                                systemImage: "lock.fill"
                            )
                            .foregroundStyle(.green)
                            Button("Clear key", role: .destructive) { model.clearGoogleTranslateKey() }
                        }
                    }
                }
                Picker("In the reader", selection: Binding(
                    get: { model.translateLayout },
                    set: {
                        model.translateLayout = $0
                        model.persistTranslateSettings()
                    }
                )) {
                    Text("Below each paragraph").tag("below")
                    Text("Replace the original").tag("replace")
                }
                Picker("After Translate", selection: Binding(
                    get: { model.translateSaveMode },
                    set: {
                        model.translateSaveMode = $0
                        model.persistTranslateSettings()
                    }
                )) {
                    Text("Keep in the reader until I save a copy").tag("keep")
                    Text("Save a second file next to the original").tag("copy")
                }
                Text("The original Markdown is never overwritten. Save a copy writes Manual.es.md beside it and uses the same pictures folder.")
                    .foregroundStyle(.secondary)
            }
            Section("Scanned PDFs") {
                Toggle("Read photographed pages", isOn: Binding(
                    get: { model.ocrEnabled },
                    set: {
                        model.ocrEnabled = $0
                        UserDefaults.standard.set($0, forKey: "ocrEnabled")
                    }
                ))
                Picker("Scanner", selection: Binding(
                    get: { model.ocrScanner },
                    set: { model.setOcrScanner($0) }
                )) {
                    Text("Apple Live Text — words on this Mac").tag("livetext")
                    Text("IBM Docling — tables and layout").tag("docling")
                }
                Text("Live Text is already on this Mac and reads the words. Docling is better at tables, columns, and pictures. It is a large extra (about 2 GB).")
                    .foregroundStyle(.secondary)
                if !model.ocrScannerHint.isEmpty {
                    Text(model.ocrScannerHint)
                        .foregroundStyle(.orange)
                }
                if Distribution.isAppStore {
                    Text("This App Store copy cannot download Docling. Apple does not allow the app to install new software after you buy it. It stays on Live Text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Layout scanner") {
                        Text(model.doclingPath == nil ? "Not on this Mac yet" : "Ready")
                    }
                    Button(model.doclingPath == nil ? "Get the layout scanner" : "Reinstall the layout scanner") {
                        model.setOcrScanner("docling")
                        Task { await model.installDocling() }
                    }
                    .disabled(model.installingEngine)
                    Text(model.doclingPath == nil
                         ? "One download, from this window. Then photographed pages use tables and columns. Needs the internet."
                         : "Ready on this Mac. Press Reinstall only if scans start failing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(model.ocrmypdfPath == nil ? "Optional backup scanner" : "Reinstall backup scanner") {
                        Task { await model.installOcrmypdf() }
                    }
                    .disabled(model.installingEngine)
                    Text(model.ocrmypdfPath == nil
                         ? "Only if you want a second fallback. Live Text already works without this."
                         : "Backup is ready if the layout scanner cannot run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Text(Distribution.isAppStore
                     ? "The App Store build defaults to the yourMark library folder. Writing next to a PDF needs a folder you choose, because the sandbox cannot always write beside a dropped file."
                     : "Each convert makes a little folder (the Markdown plus a figures folder inside) so Finder stays tidy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.filePlace == "custom", !model.customFolderPath.isEmpty {
                    Text(model.customFolderPath)
                        .font(.caption)
                        .textSelection(.enabled)
                    Button("Change folder") { model.pickOutputFolder() }
                }
            }
            if Distribution.isAppStore {
                Section("Actions") {
                    Button("App Store updates") {
                        if let url = URL(string: "macappstore://showUpdatesPage") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Text("This copy updates from the App Store, not from a disk image.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !Distribution.isAppStore {
            Section("GitHub updates") {
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
                    Text("Pulls the latest Microsoft MarkItDown. Does not change the yourMark app itself.")
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
        .overlay(alignment: .bottomTrailing) {
            VersionStamp()
        }
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
