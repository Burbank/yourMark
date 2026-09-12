import AppKit
import ImageIO
import SwiftUI

/// Library button height — every toolbar control matches this.
private enum BarFit {
    static let h: CGFloat = 36
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    private var deck: DeckTheme {
        DeckTheme.resolve(model.appearance, macIsDark: DeckTheme.macSystemIsDark(), brightLook: model.brightLook)
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            TopBar()
            if !Distribution.isAppStore, model.engineChecked, model.installingEngine || model.enginePath == nil {
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
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { model.noteWindowSize(g.size) }
                    .onChange(of: g.size) { _, size in model.noteWindowSize(size) }
            }
        }
        .foregroundStyle(deck.ink)
        .environment(\.deck, deck)
        .preferredColorScheme(model.colorScheme)
        .background(FileDropCatcher(
            onHover: { model.draggingFiles = $0 },
            onURLs: { model.openIncoming($0) }
        ))
        .overlay {
            if model.draggingFiles {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(deck.cyan, lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .task { await model.bootstrap() }
        .onAppear {
            InterfaceStore.markHealthy()
            model.applyWindowAppearance()
            if model.interfaceFellBack {
                model.statusText = model.L("Interface set back to US English after a problem.")
                model.interfaceFellBack = false
            }
        }
        .sheet(isPresented: Binding(
            get: { model.showFolderSheet },
            set: { _ in }
        )) {
            FirstRunFolderSheet()
                .environment(model)
                .environment(\.deck, deck)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: Binding(
            get: { model.showReadySheet },
            set: { _ in }
        )) {
            FirstRunReadySheet()
                .environment(model)
                .environment(\.deck, deck)
                .interactiveDismissDisabled()
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
            get: { model.showHunterSaved },
            set: { if !$0 { model.dismissHunterSaved() } }
        )) {
            HunterSavedSheet()
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
        .alert("SAVE OCR PDF", isPresented: Binding(
            get: { model.ocrPdfNotice != nil },
            set: { if !$0 { model.ocrPdfNotice = nil } }
        )) {
            Button("OK", role: .cancel) { model.ocrPdfNotice = nil }
        } message: {
            Text(model.ocrPdfNotice ?? "")
        }
    }

}

private struct StatusBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        HStack {
            Spacer()
            if model.selectedTool == .convert, model.enginePath != nil, !model.showSettings, !model.showHelp {
                Button(model.L("Convert")) {
                    Task { await model.convertQueued() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy || model.jobs.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(deck.btn)
                Button(model.L("Clear Recent List")) {
                    model.clearRecentConvertJobs()
                }
                .disabled(!model.hasRecentConvertJobs)
                Button(model.L("Stop Processing Current")) {
                    model.stopCurrentConvert()
                }
                .disabled(!model.isConvertRunning)
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

private struct HunterSavedSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.L("Saved your gathered notes"))
                .font(.title2.weight(.bold))
            Text(model.hunterSavedPath.isEmpty
                 ? model.L("The notes are also on the system clipboard.")
                 : "\(model.L("The notes are also on the system clipboard."))\n\n\(model.hunterSavedPath)")
                .foregroundStyle(deck.muted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button(model.L("Go to File")) { model.openHunterSavedFile() }
                Button(model.L("OK")) { model.dismissHunterSaved() }
                    .buttonStyle(.borderedProminent)
                    .tint(deck.btn)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460)
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
            if Distribution.isAppStore {
                Button(model.L("Email report")) { model.sendPendingCrash() }
                    .buttonStyle(.plain)
                    .foregroundStyle(deck.muted)
            } else {
                Button("I have a GitHub account") { model.sendPendingCrash() }
                    .buttonStyle(.plain)
                    .foregroundStyle(deck.muted)
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(deck.page)
    }
}

private struct FirstRunFolderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.L("Where should yourMark keep your files?"))
                .font(.title2.weight(.bold))
            Text(model.L("Converted Markdown and forage notes go in the folder you pick.\nThat can be on this Mac, in iCloud, or anywhere you like.\niCloud or another cloud folder is safer — if this Mac fails, you still have a copy.\nThe author is not responsible for lost data."))
                .foregroundStyle(deck.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button(model.L("Choose a folder…")) {
                    model.pickOutputFolder(firstRun: true)
                }
                .buttonStyle(.borderedProminent)
                .tint(deck.btn)
                .keyboardShortcut(.defaultAction)
                .fixedSize()
            }
        }
        .padding(28)
        .frame(minWidth: 320, idealWidth: 480, maxWidth: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background(deck.page)
    }
}

private struct FirstRunReadySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.L("You’re ready"))
                .font(.title2.weight(.bold))
            Text(model.L("Ask AI keys and extra tools are in Settings when you need them."))
                .foregroundStyle(deck.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(model.L("Done")) {
                    model.finishSetupWizard()
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

private struct ToolbarIsland<Content: View>: View {
    @Environment(\.deck) private var deck
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(deck.field)
                .shadow(color: Color.black.opacity(scheme == .dark ? 0.32 : 0.10), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(deck.line.opacity(0.65), lineWidth: 0.6)
        )
    }
}

private struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    private var showReaderChrome: Bool {
        model.selectedTool == .library && !model.showSettings && !model.showHelp
    }

    /// Stack only after the window size is known, so launch does not reflow.
    private var stackIslands: Bool {
        let width = model.windowSize.width
        guard width >= 200 else { return false }
        return width < 1280
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            brand
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 10) {
                if stackIslands {
                    if !bannerText.isEmpty { toastChip }
                    ToolbarIsland { chromeTools }
                    ToolbarIsland {
                        navTools
                        if showReaderChrome { ReaderWorkTools() }
                    }
                    if showReaderChrome {
                        HStack(alignment: .center, spacing: 10) {
                            ToolbarIsland { HunterGathererTools() }
                            if model.canTranslate {
                                ToolbarIsland { ReaderTranslateTools() }
                            }
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        if !bannerText.isEmpty { toastChip }
                        ToolbarIsland {
                            navTools
                            if showReaderChrome { ReaderWorkTools() }
                        }
                        ToolbarIsland { chromeTools }
                    }
                    .fixedSize()
                    if showReaderChrome {
                        HStack(alignment: .center, spacing: 10) {
                            ToolbarIsland { HunterGathererTools() }
                            if model.canTranslate {
                                ToolbarIsland { ReaderTranslateTools() }
                            }
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(deck.panel)
        .overlay(Rectangle().frame(height: deck.border).foregroundStyle(deck.line), alignment: .bottom)
        .animation(.easeInOut(duration: 0.2), value: bannerText)
    }

    private var toastChip: some View {
        HStack(spacing: 8) {
            if bannerLive {
                ProgressView().controlSize(.small)
            }
            Text(bannerText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(deck.cyan)
                .lineLimit(1)
                .truncationMode(.tail)
            if model.awaitingPairPick {
                Button {
                    model.cancelPairPick()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(deck.muted)
                }
                .buttonStyle(.plain)
                .help(model.L("Cancel SIDE BY SIDE"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(deck.field))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
        .fixedSize()
        .help(bannerText)
        .transition(.opacity)
    }

    @ViewBuilder
    private var navTools: some View {
        ForEach(AppTool.allCases) { tool in
            Button(model.L(tool.rawValue)) { model.selectTool(tool) }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: BarFit.h)
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
    }

    @ViewBuilder
    private var chromeTools: some View {
        HStack(spacing: 0) {
            ForEach(["system", "bright", "dim"], id: \.self) { mode in
                Button(mode.uppercased()) { model.setAppearance(mode) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .frame(height: BarFit.h)
                    .background(model.appearance == mode ? deck.btn : deck.panel)
                    .foregroundStyle(model.appearance == mode ? deck.btnText : deck.muted)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        Button {
            model.toggleSettings()
        } label: {
            Label(model.L("Settings"), systemImage: "gearshape")
                .font(.body.weight(.bold))
                .padding(.horizontal, 12)
                .frame(height: BarFit.h)
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
                .frame(width: BarFit.h, height: BarFit.h)
                .background(RoundedRectangle(cornerRadius: 8).fill(model.showHelp ? deck.btn : deck.panel))
                .foregroundStyle(model.showHelp ? deck.btnText : deck.ink)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: model.showHelp ? 0 : deck.border))
        }
        .buttonStyle(.plain)
        .help("Guide")
    }

    private var brand: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 0) {
                Text("yourMark")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("PDFs → Markdown")
                    .font(.caption)
                    .foregroundStyle(deck.muted)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
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

private struct PulseSaveCopyButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck
    @State private var dim = false

    var body: some View {
        Button("Save a copy") { model.saveTranslationCopy() }
            .buttonStyle(.plain)
            .font(.body.weight(.bold))
            .frame(height: BarFit.h)
            .padding(.horizontal, 10)
            .foregroundStyle(model.pulseSaveCopy ? deck.cyan : deck.ink)
            .opacity(model.pulseSaveCopy && dim ? 0.38 : 1)
            .animation(
                model.pulseSaveCopy
                    ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                    : .default,
                value: dim
            )
            .help("Write a second file. The original Markdown stays as it is.")
            .onAppear { startPulseIfNeeded() }
            .onChange(of: model.pulseSaveCopy) { _, _ in startPulseIfNeeded() }
    }

    private func startPulseIfNeeded() {
        if model.pulseSaveCopy {
            dim = false
            DispatchQueue.main.async { dim = true }
        } else {
            dim = false
        }
    }
}

/// Simple arrow with a slightly heavier head. Left is the right arrow, mirrored.
private struct SyncArrow: View {
    enum Face { case left, right }
    var face: Face
    var color: Color

    var body: some View {
        Canvas { context, size in
            let h = size.height
            let headW = h * 0.72
            let shaftH = max(3, h * 0.34)
            let shaftW = size.width - headW * 0.72
            var path = Path()
            path.addRect(CGRect(x: 0, y: (h - shaftH) / 2, width: shaftW, height: shaftH))
            path.move(to: CGPoint(x: shaftW - 1.2, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: h / 2))
            path.addLine(to: CGPoint(x: shaftW - 1.2, y: h))
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }
        .frame(width: 14, height: 9)
        .scaleEffect(x: face == .left ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }
}

private struct ReaderTranslateTools: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    private var selected: LibraryItem? {
        model.library.first(where: { $0.id == model.selectedLibraryID })
    }

    private var sideBySideLit: Bool {
        model.sideBySide || model.sideBySidePairReady || model.awaitingPairPick
    }

    private var syncScrollLit: Bool {
        model.linkingScroll && model.linkScroll
    }

    private var syncRightPane: LinkPane {
        model.forageLinkActive ? .harvest : .translate
    }

    var body: some View {
        langBits
        actionBits
    }

    @ViewBuilder
    private var langBits: some View {
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
        .frame(width: 132, height: BarFit.h)
        .help("Below each paragraph keeps the original. Replace shows only the translation.")
        Menu {
            Button("This chapter") {
                model.requestTranslate(entireFile: false)
            }
            Button("Entire file") {
                model.requestTranslate(entireFile: true)
            }
        } label: {
            Text(model.translateBusy ? "Translating…" : "Translate")
                .font(.body.weight(.bold))
                .frame(height: BarFit.h)
                .padding(.horizontal, 12)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.translateBusy || selected == nil)
        .help(model.translateEntireFileIsCostly
              ? model.L("Entire file on a large manual can cost a lot on your AI. Prefer This chapter.")
              : model.translateReadyHint)
    }

    @ViewBuilder
    private var actionBits: some View {
        if model.translateMarkdown != nil {
            PulseSaveCopyButton()
            Button("Clear") { model.clearTranslation() }
                .buttonStyle(.plain)
                .font(.body.weight(.bold))
                .frame(height: BarFit.h)
                .padding(.horizontal, 10)
        }
        Button {
            model.toggleSideBySide()
        } label: {
            Text("SIDE BY SIDE")
                .font(.body.weight(.bold))
                .tracking(0.4)
                .foregroundStyle(sideBySideLit ? deck.btnText : deck.ink)
                .padding(.horizontal, 12)
                .frame(height: BarFit.h)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(model.sideBySide ? deck.btn : model.sideBySidePairReady ? deck.cyan : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(sideBySideLit ? Color.clear : deck.line, lineWidth: deck.border)
                )
        }
        .buttonStyle(.plain)
        .help(model.L("Press SIDE BY SIDE. A translation under the card opens beside it. Several languages: click one. A toast tells you."))
        Button {
            model.pressSyncScroll()
        } label: {
            VStack(spacing: 1) {
                Text("SyncScroll")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(syncScrollLit ? deck.btnText : deck.ink)
                HStack(spacing: 0) {
                    if !model.linkingScroll || model.linkMaster == nil || model.linkMaster == .main {
                        SyncArrow(face: .left, color: syncScrollLit ? deck.btnText : deck.ink)
                    } else {
                        Color.clear.frame(width: 14, height: 9)
                    }
                    Spacer(minLength: 6)
                    if !model.linkingScroll || model.linkMaster == nil || model.linkMaster == syncRightPane {
                        SyncArrow(face: .right, color: syncScrollLit ? deck.btnText : deck.ink)
                    } else {
                        Color.clear.frame(width: 14, height: 9)
                    }
                }
                .frame(width: 42)
            }
            .padding(.horizontal, 8)
            .frame(width: 78, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(syncScrollLit ? deck.cyan : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(syncScrollLit ? Color.clear : deck.line, lineWidth: deck.border)
            )
        }
        .buttonStyle(.plain)
        .help(model.hunterOn
              ? model.L("Turn Hunter-Gatherer off to SyncScroll FORAGE with the source.")
              : model.forageLinkActive
                ? (model.linkScroll ? model.L("Scroll the reader and FORAGE together") : model.L("Scroll each pane on its own"))
                : model.sideBySide
                  ? (model.linkScroll ? model.L("Scroll both files together") : model.L("Scroll each file on its own"))
                  : model.L("Open a pair with SIDE BY SIDE first."))
    }
}

private struct ReaderWorkTools: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck
    @AppStorage("previewPointSize") private var previewPointSize = 16.0
    @AppStorage("figurePreviewSize") private var figurePreviewSize = 600.0
    @AppStorage("previewRendered") private var previewRendered = true

    private var selected: LibraryItem? {
        model.library.first(where: { $0.id == model.selectedLibraryID })
    }

    var body: some View {
        ocrBits
        sizeAndRender
        searchAndEdit
    }

    @ViewBuilder
    private var ocrBits: some View {
        if !Distribution.isAppStore, model.saveOcrPdf {
            SweepActionButton(
                title: "SAVE OCR PDF",
                sweeping: model.ocrPdfBusy,
                disabled: false
            ) {
                if let item = selected {
                    Task { await model.saveOcrPdf(for: item) }
                } else {
                    model.ocrPdfNotice = "Open a converted PDF in the library first."
                }
            }
        }
        if model.canOpenInOcrApp(selected) {
            Button(model.ocrAppButtonTitle) {
                if let item = selected {
                    model.openInOcrApp(item)
                }
            }
            .buttonStyle(.plain)
            .font(.body.weight(.bold))
            .padding(.horizontal, 10)
            .frame(height: BarFit.h)
            .background(RoundedRectangle(cornerRadius: 8).fill(deck.field))
            .foregroundStyle(deck.ink)
            .help(model.L("Open the original PDF in the OCR app you chose. yourMark does not write Manual.searchable.pdf."))
        }
    }

    @ViewBuilder
    private var sizeAndRender: some View {
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
        Button(previewRendered ? model.L("Rendered") : model.L("Plain")) {
            previewRendered.toggle()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 8)
        .frame(height: BarFit.h)
        .background(RoundedRectangle(cornerRadius: 8).fill(previewRendered ? deck.btn : deck.field))
        .foregroundStyle(previewRendered ? deck.btnText : deck.ink)
        .help("Rendered shows headings. Plain shows the raw Markdown.")
    }

    @ViewBuilder
    private var searchAndEdit: some View {
        fileSearchColumn
        if selected != nil || model.forageEditURL != nil {
            Button(model.L("Edit")) {
                model.openInEditor(selected)
            }
            .buttonStyle(.plain)
            .font(.body.weight(.bold))
            .padding(.horizontal, 12)
            .frame(height: BarFit.h)
            .background(RoundedRectangle(cornerRadius: 8).fill(deck.btn))
            .foregroundStyle(deck.btnText)
            .help(model.editorButtonHelp)
            Button("Finder") {
                if let item = selected {
                    model.revealLibrary(item)
                } else if let url = model.forageEditURL {
                    model.reveal(url)
                }
            }
            .buttonStyle(.plain)
            .font(.body.weight(.bold))
            .padding(.horizontal, 12)
            .frame(height: BarFit.h)
            .background(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
            .help("Show this file in Finder")
        }
    }

    private var fileSearchColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                DeckSearchField(
                    prompt: model.L("Search in files"),
                    text: Binding(
                        get: { model.fileSearch },
                        set: { model.setFileSearch($0) }
                    )
                )
                if !model.fileSearch.isEmpty {
                    Button {
                        model.clearFileSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(deck.muted)
                    }
                    .buttonStyle(.plain)
                    .help(model.L("Clear"))
                }
            }
            if !model.fileSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SearchNavBits(
                    summary: model.fileSearchSummary,
                    onPrev: { model.prevFileHit() },
                    onNext: { model.nextFileHit() }
                )
            }
        }
        .frame(width: 196)
        .help(model.L("Find words in Markdown already on a library card. AND, OR, NOT, and quoted phrases. Boolean words must sit in the same sentence or paragraph. Stays on this Mac."))
    }
}

private struct HunterGathererTools: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        HStack(spacing: 8) {
            Button("HUNTER-GATHERER") {
                model.toggleHunterGatherer()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .frame(height: BarFit.h)
            .background(RoundedRectangle(cornerRadius: 8).fill(model.hunterOn ? deck.btn : deck.field))
            .foregroundStyle(model.hunterOn ? deck.btnText : deck.ink)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.hunterOn ? Color.clear : deck.line, lineWidth: deck.border))
            .help(model.L("HUNTER-GATHERER is on. Click and drag to select, then press Enter."))
            if model.hunterOn {
                Button {
                    _ = model.gatherSelectedText()
                } label: {
                    HStack(spacing: 8) {
                        Text(model.L("Add"))
                            .font(.system(size: 13, weight: .semibold))
                        Text("⏎")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(deck.field))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(deck.line, lineWidth: deck.border))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: BarFit.h)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
                }
                .buttonStyle(.plain)
                .help(model.L("Add the selected text to the board. Enter does the same."))
            }
            Button(model.L("FORAGE")) {
                model.toggleHarvest()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .frame(height: BarFit.h)
            .background(RoundedRectangle(cornerRadius: 8).fill(model.harvestOpen ? deck.btn : deck.field))
            .foregroundStyle(model.harvestOpen ? deck.btnText : deck.ink)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.harvestOpen ? Color.clear : deck.line, lineWidth: deck.border))
            .help(model.L("Open the gathered notes beside the reader. Stays open when you change files or turn Hunter-Gatherer off."))
        }
    }
}

private struct DeckSearchField: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck
    var prompt: String
    @Binding var text: String

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(deck.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(deck.field))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(deck.line, lineWidth: deck.border))
            .id(model.appearance + "/" + model.brightLook)
    }
}

private struct SearchNavBits: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck
    let summary: String
    let onPrev: () -> Void
    let onNext: () -> Void
    var large: Bool = false

    var body: some View {
        HStack(spacing: large ? 8 : 6) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: large ? 17 : 10, weight: .semibold))
                    .frame(width: large ? 28 : 16, height: large ? 28 : 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.L("Previous"))
            Text(summary)
                .font(.system(size: large ? 12 : 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(deck.muted)
                .lineLimit(1)
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: large ? 17 : 10, weight: .semibold))
                    .frame(width: large ? 28 : 16, height: large ? 28 : 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.L("Next"))
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
                        ForEach(model.recentConvertJobs) { job in
                            HStack(alignment: .top) {
                                Image(systemName: icon(for: job.status))
                                    .foregroundStyle(color(for: job.status))
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.sourceURL.lastPathComponent)
                                        .font(.body.weight(.bold))
                                    if job.status == .running {
                                        convertProgress(for: job)
                                    }
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

    @ViewBuilder
    private func convertProgress(for job: ConvertJob) -> some View {
        let fileBit: String = {
            guard job.fileCount > 1, job.fileIndex > 0 else { return "" }
            return "File \(job.fileIndex) of \(job.fileCount)"
        }()
        let phase = job.phase.isEmpty ? "Markdown" : job.phase
        if let progress = job.progress, job.pageCount > 0 {
            let pageBit = "\(phase) · \(job.page) of \(job.pageCount)"
            let etaBit: String = {
                guard let eta = job.etaSeconds, eta > 0 else { return "" }
                return " · about \(convertClock(TimeInterval(eta))) left"
            }()
            VStack(alignment: .leading, spacing: 4) {
                Text([fileBit, pageBit].filter { !$0.isEmpty }.joined(separator: " · ") + etaBit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(deck.cyan)
                ProgressView(value: min(1, max(0, progress)))
                    .tint(deck.cyan)
            }
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = convertClock(context.date.timeIntervalSince(job.startedAt ?? context.date))
                VStack(alignment: .leading, spacing: 4) {
                    Text([fileBit, "\(phase) · \(elapsed)"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(deck.cyan)
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private func convertClock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
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
    @AppStorage("splitSide") private var sideFrac = 0.50
    @AppStorage("splitHarvest") private var harvestFrac = 0.28
    @AppStorage("previewPointSize") private var previewPointSize = 16.0
    @AppStorage("figurePreviewSize") private var figurePreviewSize = 600.0
    @AppStorage("previewRendered") private var previewRendered = true
    @State private var figureHover: FigureHover?

    var body: some View {
        VStack(spacing: 0) {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let libW = model.libraryCollapsed ? 36 : max(160, w * libFrac)
            let harvestW = model.harvestOpen ? max(220, w * harvestFrac) : 0
            let harvestGap: CGFloat = model.harvestOpen ? 1 : 0
            if model.sideBySide {
                let rest = max(400, w - libW - harvestW - (model.libraryCollapsed ? 0 : 1) - harvestGap)
                let leftW = max(220, rest * sideFrac)
                let rightW = max(220, rest - leftW)
                HStack(spacing: 0) {
                    libraryColumn
                        .frame(width: libW, height: h, alignment: .top)
                    if !model.libraryCollapsed {
                        SplitDrag(fraction: $libFrac, min: 0.12, max: 0.28, total: w, color: deck.line)
                    }
                    documentPane(
                        title: selected?.title ?? "Original",
                        rail: "Bookmarks",
                        fromPdf: outlineFromPdf,
                        lines: model.previewLines,
                        outline: outline,
                        scroll: model.scrollToLine,
                        pane: .main
                    )
                    .frame(width: leftW, height: h, alignment: .top)
                    SplitDrag(fraction: $sideFrac, min: 0.36, max: 0.64, total: rest, color: deck.line)
                    documentPane(
                        title: translationTitle,
                        rail: "Bookmarks · translation",
                        fromPdf: false,
                        lines: model.translateLines,
                        outline: model.translateHeadings,
                        scroll: model.translateScrollLine,
                        pane: .translate
                    )
                    .frame(width: rightW, height: h, alignment: .top)
                    if model.harvestOpen {
                        SplitDrag(fraction: $harvestFrac, min: 0.18, max: 0.42, total: w, color: deck.line)
                        harvestColumn
                            .frame(width: harvestW, height: h, alignment: .top)
                    }
                }
            } else {
                let marksW = max(120, w * marksFrac)
                let readW = max(240, w - libW - marksW - harvestW - (model.libraryCollapsed ? 1 : 2) - harvestGap)
                HStack(spacing: 0) {
                    libraryColumn
                        .frame(width: libW, height: h, alignment: .top)
                    if !model.libraryCollapsed {
                        SplitDrag(fraction: $libFrac, min: 0.14, max: 0.36, total: w, color: deck.line)
                    }
                    bookmarksColumn
                        .frame(width: marksW, height: h, alignment: .top)
                    SplitDrag(fraction: $marksFrac, min: 0.10, max: 0.32, total: w, color: deck.line)
                    markdownColumn
                        .frame(width: readW, height: h, alignment: .top)
                    if model.harvestOpen {
                        SplitDrag(fraction: $harvestFrac, min: 0.16, max: 0.46, total: w, color: deck.line)
                        harvestColumn
                            .frame(width: harvestW, height: h, alignment: .top)
                    }
                }
            }
        }
        .background(deck.page)
        AskStrip()
        }
        .alert("This file is large", isPresented: Binding(
            get: { model.showTranslateCostWarning },
            set: { if !$0 { model.showTranslateCostWarning = false } }
        )) {
            Button("Cancel", role: .cancel) { model.showTranslateCostWarning = false }
            Button("Translate entire file") { model.confirmCostlyTranslate() }
        } message: {
            Text("Translating this whole file sends a large amount of text to your AI and can cost a lot. Prefer This chapter. The reader can show a long file. Entire file still sends a lot of text to the AI.")
        }
    }

    private var translationTitle: String {
        let lang = TranslateLang.label(for: model.translateTo)
        if let title = selected?.title { return "\(title) · \(lang)" }
        return lang
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

    @ViewBuilder
    private var libraryColumn: some View {
        if model.libraryCollapsed {
            collapsedLibraryStrip
        } else {
            expandedLibraryColumn
        }
    }

    private var collapsedLibraryStrip: some View {
        Button {
            model.libraryCollapsed = false
        } label: {
            ZStack(alignment: .trailing) {
                VStack(spacing: 18) {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(deck.cyan)
                        .padding(.top, 12)
                    Text(model.L("open Library."))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(deck.muted)
                        .fixedSize()
                        .rotationEffect(.degrees(-90))
                        .frame(width: 14, height: 88)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(deck.line)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(deck.page)
        .help(model.L("Show Library"))
    }

    private var expandedLibraryColumn: some View {
        VStack(spacing: 0) {
            librarySortBar
            titleSearchField
            List {
                forageVaultRow
                    .dropDestination(for: String.self) { items, _ in
                        guard let src = items.first else { return false }
                        model.reorderLibraryGroup(moving: src, onto: nil)
                        return true
                    } isTargeted: { over in
                        model.libraryDropTargetID = over ? "vault" : nil
                    }
                ForEach(model.visibleLibraryGroups) { group in
                    Group {
                        libraryCardRow(group.master, indent: 0, groupID: group.id)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(model.libraryDropTargetID == group.id ? deck.cyan : Color.clear, lineWidth: 2)
                            )
                            .dropDestination(for: String.self) { items, _ in
                                guard let src = items.first else { return false }
                                model.reorderLibraryGroup(moving: src, onto: group.id)
                                return true
                            } isTargeted: { over in
                                model.libraryDropTargetID = over ? group.id : nil
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        ForEach(group.children) { child in
                            libraryCardRow(
                                child,
                                indent: 20 + (showLibraryGrip ? libraryGripWidth : 0),
                                groupID: nil
                            )
                            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 6, trailing: 10))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(deck.page)
        .alert(model.deleteConfirmDisplayTitle, isPresented: Binding(
            get: { model.showDeleteConfirm },
            set: { if !$0 { model.cancelPendingDelete() } }
        )) {
            Button(model.L("Cancel"), role: .cancel) { model.cancelPendingDelete() }
            if model.pendingDeleteOffersGroup {
                Button(model.L("This card only"), role: .destructive) {
                    model.confirmPendingDelete(dontAskAgain: false)
                }
                Button(model.L("This card and translations"), role: .destructive) {
                    model.confirmDeleteWithTranslations()
                }
            } else {
                Button(model.L("Delete"), role: .destructive) {
                    model.confirmPendingDelete(dontAskAgain: false)
                }
                if model.pendingDeleteItems.count == 1 {
                    Button(model.L("Delete and don't ask next time")) {
                        model.confirmPendingDelete(dontAskAgain: true)
                    }
                }
            }
        } message: {
            Text(model.deleteConfirmDisplayMessage)
        }
    }

    private var librarySortBar: some View {
        HStack(spacing: 6) {
            sortChip(model.L("Manual"), on: model.librarySort == .manual) {
                model.setLibrarySort(.manual)
            }
            sortChip(model.L(model.librarySort == .nameDesc ? "Name Z–A" : "Name A–Z"),
                     on: model.librarySort == .nameAsc || model.librarySort == .nameDesc) {
                model.setLibrarySort(model.librarySort == .nameAsc ? .nameDesc : .nameAsc)
            }
            sortChip(model.L(model.librarySort == .dateOld ? "Date oldest" : "Date newest"),
                     on: model.librarySort == .dateNew || model.librarySort == .dateOld) {
                model.setLibrarySort(model.librarySort == .dateNew ? .dateOld : .dateNew)
            }
            sortChip(model.L(model.librarySort == .tagDesc ? "Tag Z–A" : "Tag"),
                     on: model.librarySort == .tagAsc || model.librarySort == .tagDesc) {
                model.setLibrarySort(model.librarySort == .tagAsc ? .tagDesc : .tagAsc)
            }
            Button {
                model.showTagBrowser.toggle()
            } label: {
                Image(systemName: "tag")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.libraryTagFilter.isEmpty && !model.showTagBrowser ? deck.ink : deck.btnText)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 8).fill(
                        model.libraryTagFilter.isEmpty && !model.showTagBrowser ? deck.panel : deck.btn
                    ))
            }
            .buttonStyle(.plain)
            .help(model.L("Tags"))
            .popover(isPresented: Binding(
                get: { model.showTagBrowser },
                set: { model.showTagBrowser = $0 }
            ), arrowEdge: .bottom) {
                TagBrowserPopover()
            }
            Spacer(minLength: 4)
            Text(model.libraryCountLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(deck.muted)
            Button {
                model.libraryCollapsed = true
            } label: {
                Image(systemName: "chevron.left.2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(deck.ink)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(model.L("Hide Library"))
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func sortChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? deck.btn : deck.panel))
            .foregroundStyle(on ? deck.btnText : deck.ink)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.clear : deck.line, lineWidth: deck.border))
    }

    private var titleSearchField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                DeckSearchField(
                    prompt: model.L(model.askHasKey ? "Search title or #tag" : "Search title or #tag"),
                    text: Binding(
                        get: { model.titleSearch },
                        set: { model.setTitleSearch($0) }
                    )
                )
                if !model.titleSearch.isEmpty {
                    Button {
                        model.clearTitleSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(deck.muted)
                    }
                    .buttonStyle(.plain)
                    .help(model.L("Clear"))
                }
            }
            if !model.titleSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SearchNavBits(
                    summary: model.titleSearchSummary,
                    onPrev: { model.prevTitleHit() },
                    onNext: { model.nextTitleHit() }
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var forageVaultRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.forageVaultOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.forageVaultOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(deck.muted)
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.L("bolted here"))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(deck.muted)
                        Text(model.L("Forage Vault"))
                            .font(.body.weight(.bold))
                            .foregroundStyle(deck.ink)
                        Text(model.forageVaultItems.isEmpty
                             ? model.L("No forage notes yet.")
                             : "\(model.forageVaultItems.count)")
                            .font(.caption)
                            .foregroundStyle(deck.muted)
                    }
                    Spacer(minLength: 8)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(deck.panel)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(deck.line, lineWidth: deck.border))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            if model.forageVaultOpen {
                if model.forageVaultItems.isEmpty {
                    Text(model.L("Turn Hunter-Gatherer off to save a note here."))
                        .font(.caption)
                        .foregroundStyle(deck.muted)
                        .padding(.leading, 16)
                } else {
                    ForEach(model.forageVaultItems) { item in
                        forageVaultChildRow(item)
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func forageVaultChildRow(_ item: LibraryItem) -> some View {
        Button {
            model.openForageInPanel(item)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FORAGE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(deck.cyan)
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(deck.ink)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(deck.field)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(item.markdownPath == model.hunterSavedPath && model.harvestOpen ? deck.cyan : deck.line, lineWidth: deck.border)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .contextMenu {
            Button(model.L("Open in FORAGE")) { model.openForageInPanel(item) }
            Button("Show in Finder") { model.revealLibraryItems([item]) }
            Divider()
            Button(model.L("Delete"), role: .destructive) { model.requestDelete([item]) }
        }
    }

    private var showLibraryGrip: Bool {
        model.librarySort == .manual
            && model.titleSearch.isEmpty
            && model.fileSearch.isEmpty
    }

    private var libraryGripWidth: CGFloat { 18 }

    private func libraryCardRow(_ item: LibraryItem, indent: CGFloat, groupID: String?) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if let groupID, showLibraryGrip {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(deck.muted)
                    .frame(width: 14, height: 28)
                    .padding(.top, 18)
                    .help(model.L("Drag to rearrange this group. Translations stay under the original."))
                    .draggable(groupID)
            }
            LibraryCard(item: item)
        }
            .padding(.leading, indent)
            .popover(isPresented: Binding(
                get: { model.tagEditorItemID == item.id },
                set: { if !$0 { model.tagEditorItemID = nil } }
            ), arrowEdge: .trailing) {
                TagEditorPopover(item: item)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    model.requestDelete(model.contextTargets(for: item))
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                let targets = model.contextTargets(for: item)
                Button("Open") { model.selectLibrary(item, force: true) }
                Button(targets.count > 1 ? "Show in Finder (\(targets.count))" : "Show in Finder") {
                    model.revealLibraryItems(targets)
                }
                Button(targets.count > 1 ? "Move to… (\(targets.count))" : "Move to…") {
                    model.moveLibraryItems(targets)
                }
                Button(model.L("Add tag…")) {
                    model.beginTagEditor(for: item)
                }
                if let groupID, showLibraryGrip {
                    Divider()
                    Button(model.L("Move group up")) { model.nudgeLibraryGroup(groupID, by: -1) }
                    Button(model.L("Move group down")) { model.nudgeLibraryGroup(groupID, by: 1) }
                }
                Divider()
                Button(targets.count > 1 ? "Delete \(targets.count) cards" : "Delete", role: .destructive) {
                    model.requestDelete(targets)
                }
            }
    }

    private var bookmarksColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.L(outlineFromPdf ? "Bookmarks · from the PDF" : "Bookmarks"))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(deck.cyan)
                .padding(.horizontal, 12)
                .padding(.top, 16)
            BookmarkRail(
                outline: outline,
                current: model.activeHeading(for: .main),
                emptyText: "No outline. Scanned PDFs need OCR first, or the source had no bookmarks/headings.",
                onPick: { model.jumpToBookmark($0) }
            )
        }
        .background(deck.panel)
    }

    private func documentPane(
        title: String,
        rail: String,
        fromPdf: Bool,
        lines: [PreviewLine],
        outline: [ManualBookmark],
        scroll: Int?,
        pane: LinkPane
    ) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(fromPdf ? "\(rail) · from the PDF" : rail)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(deck.cyan)
                    .padding(.horizontal, 10)
                    .padding(.top, 16)
                BookmarkRail(
                    outline: outline,
                    current: model.activeHeading(for: pane),
                    emptyText: "No outline on this side yet.",
                    onPick: { item in
                        if pane == .translate {
                            model.jumpToTranslatedBookmark(item)
                        } else {
                            model.jumpToBookmark(item)
                        }
                    }
                )
            }
            .frame(minWidth: 110, idealWidth: 140, maxWidth: 170)
            .background(deck.panel)
            Rectangle().fill(deck.line).frame(width: 1)
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(deck.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(deck.panel)
                    .overlay(Rectangle().frame(height: deck.border).foregroundStyle(deck.line), alignment: .bottom)
                markdownList(lines: lines, scroll: scroll, pane: pane)
            }
        }
        .background(PaneLeadCatcher { model.adoptLinkMaster(pane) })
        .simultaneousGesture(TapGesture().onEnded { model.adoptLinkMaster(pane) })
    }

    private var markdownColumn: some View {
        VStack(spacing: 0) {
            markdownTitleBar
            markdownList(lines: model.previewLines, scroll: model.scrollToLine, pane: .main)
        }
        .background(PaneLeadCatcher { model.adoptLinkMaster(.main) })
        .simultaneousGesture(TapGesture().onEnded { model.adoptLinkMaster(.main) })
    }

    private var harvestColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(model.harvestTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(deck.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if model.hasLastForage, !model.hunterOn {
                    Button(model.L("Add more")) {
                        model.continueForageGather()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(deck.field))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
                    .foregroundStyle(deck.ink)
                    .help(model.L("Turn Hunter-Gatherer on and keep adding to this FORAGE file."))
                }
                Button(model.L("Open last")) {
                    model.openLastForage()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(deck.field))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
                .foregroundStyle(model.hasLastForage ? deck.ink : deck.muted)
                .disabled(!model.hasLastForage)
                .help(model.L("Show the last saved FORAGE file in this panel."))
                Button(model.L("Close")) {
                    model.closeForagePanel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(deck.field))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
                .foregroundStyle(deck.ink)
                .help(model.L("Close FORAGE. Writes the note and turns off the FORAGE button."))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(deck.panel)
            .overlay(Rectangle().frame(height: deck.border).foregroundStyle(deck.line), alignment: .bottom)
            markdownList(
                lines: model.harvestLines,
                scroll: model.harvestScrollLine,
                pane: .harvest,
                allowHunter: false
            )
        }
        .background(deck.field)
        .background(PaneLeadCatcher { model.adoptLinkMaster(.harvest) })
        .simultaneousGesture(TapGesture().onEnded { model.adoptLinkMaster(.harvest) })
    }

    @ViewBuilder
    private func markdownList(lines: [PreviewLine], scroll: Int?, pane: LinkPane, allowHunter: Bool = true) -> some View {
        if model.hunterOn && allowHunter {
            let plan = model.hunterHighlightPlan(in: lines)
            HunterSelectView(
                text: model.hunterReaderText(from: lines),
                pointSize: previewPointSize,
                ink: NSColor(deck.ink),
                paper: NSColor(deck.field),
                gathered: model.hunterGatheredRanges,
                markStamp: model.hunterMarkStamp,
                searchMarks: plan.all,
                currentMarks: plan.current,
                searchStamp: model.hunterHighlightStamp,
                scrollChar: model.hunterScrollChar,
                scrollStamp: model.hunterScrollStamp,
                lineMap: model.hunterLineMap(from: lines),
                onTopLine: { model.noteVisibleLine($0, headingTitle: "", from: pane) },
                selectChar: model.hunterSelectChar,
                selectLength: model.hunterSelectLength,
                selectStamp: model.hunterSelectStamp
            )
        } else {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { row in
                        markdownLine(row.text, pane: pane, lineID: row.id)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(pane != .harvest && (model.isCurrentFileHit(lineID: row.id) || model.isAskHitLine(row.id))
                                ? Color(red: 1, green: 0.93, blue: 0.2).opacity(model.isCurrentFileHit(lineID: row.id) ? 0.22 : 0.12)
                                : deck.field)
                            .id(row.id)
                    }
                    if pane == .harvest {
                        Color.clear.frame(height: 28)
                    }
                }
            }
            .background(deck.field)
            .coordinateSpace(name: "reader-\(pane)")
            .onChange(of: scroll) { _, line in
                guard let line else { return }
                proxy.scrollTo(line, anchor: pane == .harvest && !model.forageLinkActive ? UnitPoint.bottom : UnitPoint.top)
            }
            .onPreferenceChange(VisibleHeadingPref.self) { hits in
                guard let hit = hits[pane] else { return }
                model.noteVisibleLine(hit.lineIndex, headingTitle: hit.title, from: pane)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let figureHover {
                HoverThumb(
                    url: figureHover.url,
                    caption: figureHover.alt,
                    previewSize: figurePreviewSize,
                    stamp: model.figureStamp
                )
                .padding(16)
                .allowsHitTesting(false)
            }
        }
        }
    }

    private var markdownTitleBar: some View {
        Text(selected?.title ?? "Markdown")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(deck.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(deck.panel)
            .overlay(Rectangle().frame(height: deck.border).foregroundStyle(deck.line), alignment: .bottom)
    }

    @ViewBuilder
    private func markdownLine(_ line: String, pane: LinkPane, lineID: Int) -> some View {
        let size = CGFloat(previewPointSize)
        let searching = pane != .harvest && (
            !model.fileSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !model.askHitsInReader.isEmpty
        )
        if line.hasPrefix(TranslateService.marker) {
            let rest = String(line.dropFirst(TranslateService.marker.count))
            translatedMarkdownLine(rest, size: size, pane: pane, lineID: lineID)
        } else if let img = markdownImage(line, base: model.previewBaseURL) {
            FigureLink(url: img.url, alt: img.alt, hover: $figureHover)
        } else if !previewRendered {
            highlightedReaderText(line, font: .system(size: size, design: .monospaced), lineID: lineID)
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
            highlightedReaderText(
                heading.text,
                font: model.readerFont(size: headingSize(heading.level, base: size), weight: heading.level <= 2 ? .bold : .semibold),
                lineID: lineID
            )
                .textSelection(.enabled)
                .padding(.top, heading.level <= 2 ? 14 : 8)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    headingProbe(heading.text, pane: pane, lineID: lineID)
                }
            }
        } else if let callout = wholeLineBold(line) {
            highlightedReaderText(
                callout,
                font: model.readerFont(size: size, weight: .semibold),
                lineID: lineID
            )
                .textSelection(.enabled)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if searching {
            highlightedReaderText(line, font: model.readerFont(size: size), lineID: lineID)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            inlineMarkdown(line, size: size)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func highlightedReaderText(_ string: String, font: Font, lineID: Int) -> Text {
        let shown = string.isEmpty ? " " : string
        let needles = model.readerHighlightNeedles
        guard !needles.isEmpty else {
            return Text(shown).font(font).foregroundStyle(deck.ink)
        }
        var attr = AttributedString(shown)
        attr.font = font
        attr.foregroundColor = deck.ink
        let current = model.isCurrentFileHit(lineID: lineID)
        var marks = 0
        for needle in needles {
            var search = shown.startIndex
            while marks < 8, search < shown.endIndex,
                  let r = shown.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: search..<shown.endIndex) {
                if let ar = Range(r, in: attr) {
                    attr[ar].backgroundColor = Color(red: 1, green: 0.93, blue: 0.2).opacity(current ? 0.72 : 0.45)
                    attr[ar].foregroundColor = Color.black.opacity(0.88)
                }
                marks += 1
                search = r.upperBound
            }
            if marks >= 8 { break }
        }
        return Text(attr)
    }

    @ViewBuilder
    private func translatedMarkdownLine(_ line: String, size: CGFloat, pane: LinkPane, lineID: Int) -> some View {
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
                .background {
                    headingProbe(heading.text, pane: pane, lineID: lineID)
                }
        } else {
            inlineMarkdown(line, size: size)
                .foregroundStyle(deck.muted)
                .textSelection(.enabled)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func headingProbe(_ title: String, pane: LinkPane, lineID: Int) -> some View {
        GeometryReader { g in
            Color.clear.preference(
                key: VisibleHeadingPref.self,
                value: [pane: VisibleHit(
                    title: title,
                    y: g.frame(in: .named("reader-\(pane)")).minY,
                    pane: pane,
                    lineIndex: lineID
                )]
            )
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
        var pairs = 0
        while pairs < 24, let start = rest.range(of: "**") {
            pairs += 1
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
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck
    var title: String
    var includeAuto: Bool
    @Binding var code: String
    @State private var open = false

    private var recents: [TranslateLang] { model.recentSpokenLangs }

    private var rest: [TranslateLang] {
        let used = Set(recents.map(\.id))
        return TranslateLang.spoken
            .filter { !used.contains($0.id) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    var body: some View {
        Button {
            open.toggle()
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: BarFit.h)
                .background(RoundedRectangle(cornerRadius: 8).stroke(deck.line, lineWidth: deck.border))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if includeAuto {
                        langRow(TranslateLang.auto)
                    }
                    ForEach(recents) { lang in
                        langRow(lang)
                    }
                    if !recents.isEmpty, !rest.isEmpty {
                        Rectangle()
                            .fill(deck.line.opacity(0.7))
                            .frame(height: 1)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 6)
                    }
                    ForEach(rest) { lang in
                        langRow(lang)
                    }
                }
                .padding(8)
            }
            .frame(width: 240, height: 360)
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

private struct VisibleHit: Equatable {
    var title: String
    var y: CGFloat
    var pane: LinkPane
    var lineIndex: Int
}

private struct VisibleHeadingPref: PreferenceKey {
    static let defaultValue: [LinkPane: VisibleHit] = [:]

    static func reduce(value: inout [LinkPane: VisibleHit], nextValue: () -> [LinkPane: VisibleHit]) {
        let topBand: CGFloat = 48
        for (pane, hit) in nextValue() {
            if let old = value[pane] {
                let oldAbove = old.y <= topBand
                let newAbove = hit.y <= topBand
                if newAbove && oldAbove {
                    value[pane] = hit.lineIndex >= old.lineIndex ? hit : old
                } else if newAbove {
                    value[pane] = hit
                } else if !oldAbove {
                    value[pane] = abs(hit.y) < abs(old.y) ? hit : old
                }
            } else {
                value[pane] = hit
            }
        }
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

private func figureMTime(_ url: URL) -> TimeInterval {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
        .flatMap(\.contentModificationDate)?.timeIntervalSince1970 ?? 0
}

private func openFigureInPreview(_ url: URL) {
    let candidates = [
        URL(fileURLWithPath: "/System/Applications/Preview.app"),
        URL(fileURLWithPath: "/Applications/Preview.app"),
    ]
    if let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        return
    }
    NSWorkspace.shared.open(url)
}

private struct FigureHover: Equatable {
    let url: URL
    let alt: String
}

/// A hyperlink in the reader. The picture is drawn in the reader overlay, not
/// in a system popover — those ignore our size and hug a tiny NSImage.
private struct FigureLink: View {
    @Environment(AppModel.self) private var model
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
            .contextMenu {
                Button(model.L("Open in Preview")) { openFigureInPreview(url) }
                Button(model.L("Show in Finder")) {
                    hover = nil
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
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
    var stamp: Int
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
        .task(id: "\(url.path)-\(figureMTime(url))-\(stamp)-\(Int(box))") {
            let pixel = Int(min(720, box * 1.2))
            let mtime = figureMTime(url)
            if let cached = PreviewImageCache.shared.image(for: url, pixel: pixel, mtime: mtime) {
                image = cached
                return
            }
            let loaded = await Task.detached(priority: .utility) {
                PreviewImageCache.thumbnailImage(url, maxPixel: CGFloat(pixel))
            }.value
            guard !Task.isCancelled else { return }
            if let loaded {
                PreviewImageCache.shared.store(loaded, for: url, pixel: pixel, mtime: mtime)
                image = loaded
            }
        }
        .onDisappear { image = nil }
    }
}

final class PreviewImageCache: @unchecked Sendable {
    static let shared = PreviewImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {
        cache.countLimit = 8
        cache.totalCostLimit = 4 * 1024 * 1024
    }

    private func key(_ url: URL, pixel: Int, mtime: TimeInterval) -> NSString {
        "\(url.path)#\(pixel)#\(mtime)" as NSString
    }

    func image(for url: URL, pixel: Int, mtime: TimeInterval) -> NSImage? {
        cache.object(forKey: key(url, pixel: pixel, mtime: mtime))
    }

    func store(_ img: NSImage, for url: URL, pixel: Int, mtime: TimeInterval) {
        let cost = Int(max(1, img.size.width * img.size.height * 4))
        cache.setObject(img, forKey: key(url, pixel: pixel, mtime: mtime), cost: min(cost, 4_000_000))
    }

    func dropAll() {
        cache.removeAllObjects()
    }

    /// Small ImageIO thumbnail only. Small files are copied so a rewrite cannot
    /// SIGBUS. Larger figures use a URL source so PNG/TIFF still preview.
    static func thumbnailImage(_ url: URL, maxPixel: CGFloat = 400) -> NSImage? {
        autoreleasepool { thumbnailImageLocked(url, maxPixel: maxPixel) }
    }

    private static func thumbnailImageLocked(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 32, size < 40_000_000 else { return nil }
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        let thumb: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        let source: CGImageSource?
        if size <= 1_500_000, let handle = FileHandle(forReadingAtPath: url.path) {
            defer { try? handle.close() }
            let fileData = handle.readData(ofLength: 1_500_000)
            source = fileData.count > 32 ? CGImageSourceCreateWithData(fileData as CFData, opts) : nil
        } else {
            source = CGImageSourceCreateWithURL(url as CFURL, opts)
        }
        let cg = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, thumb as CFDictionary) }
            ?? CGImageSourceCreateWithURL(url as CFURL, opts)
                .flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, thumb as CFDictionary) }
        guard let cg else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

private struct BookmarkNode: Identifiable {
    var item: ManualBookmark
    var children: [BookmarkNode]
    var id: UUID { item.id }
}

private struct BookmarkRail: View {
    @Environment(\.deck) private var deck
    let outline: [ManualBookmark]
    let current: String
    var emptyText: String
    let onPick: (ManualBookmark) -> Void
    @State private var expanded: Set<UUID> = []
    @State private var seededIDs: [UUID] = []

    private var tree: [BookmarkNode] { Self.makeTree(outline) }

    private var visibleRows: [(node: BookmarkNode, depth: Int)] {
        var rows: [(BookmarkNode, Int)] = []
        func walk(_ nodes: [BookmarkNode], depth: Int) {
            for node in nodes {
                rows.append((node, depth))
                if !node.children.isEmpty, expanded.contains(node.id) {
                    walk(node.children, depth: depth + 1)
                }
            }
        }
        walk(tree, depth: 0)
        return rows
    }

    var body: some View {
        if outline.isEmpty {
            Text(emptyText)
                .font(.caption)
                .foregroundStyle(deck.muted)
                .padding(12)
        } else {
            ScrollViewReader { proxy in
                List(visibleRows, id: \.node.id) { row in
                    let node = row.node
                    let on = !current.isEmpty
                        && node.item.title.caseInsensitiveCompare(current) == .orderedSame
                    Button {
                        if !node.children.isEmpty {
                            if expanded.contains(node.id) {
                                expanded.remove(node.id)
                            } else {
                                expanded.insert(node.id)
                            }
                        }
                        onPick(node.item)
                    } label: {
                        HStack(spacing: 4) {
                            if node.children.isEmpty {
                                Color.clear.frame(width: 12, height: 12)
                            } else {
                                Image(systemName: expanded.contains(node.id) ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(on ? deck.btnText : deck.muted)
                                    .frame(width: 12, height: 12)
                            }
                            Text(node.item.title)
                                .font(.body.weight(on ? .bold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, CGFloat(max(0, node.item.level - 1) * 10))
                    .listRowBackground(on ? deck.btn : Color.clear)
                    .foregroundStyle(on ? deck.btnText : deck.ink)
                    .id(node.id)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: current) { _, title in
                    expandPath(to: title)
                    reveal(title, proxy: proxy)
                }
                .onAppear {
                    seedExpandedIfNeeded()
                    expandPath(to: current)
                    reveal(current, proxy: proxy)
                }
                .onChange(of: outline.map(\.id)) { _, _ in
                    seedExpandedIfNeeded(force: true)
                    expandPath(to: current)
                }
            }
        }
    }

    private func seedExpandedIfNeeded(force: Bool = false) {
        let ids = outline.map(\.id)
        guard force || ids != seededIDs else { return }
        seededIDs = ids
        if outline.count > 100 {
            expanded = []
        } else {
            expanded = Set(parentIDs(in: tree))
        }
    }

    private func expandPath(to title: String) {
        guard !title.isEmpty, let trail = Self.ancestors(of: title, in: tree) else { return }
        expanded.formUnion(trail)
    }

    private func reveal(_ title: String, proxy: ScrollViewProxy) {
        guard let id = outline.first(where: {
            $0.title.caseInsensitiveCompare(title) == .orderedSame
        })?.id else { return }
        proxy.scrollTo(id, anchor: .center)
    }

    private func parentIDs(in nodes: [BookmarkNode]) -> [UUID] {
        nodes.flatMap { node in
            node.children.isEmpty ? [] : [node.id] + parentIDs(in: node.children)
        }
    }

    private static func makeTree(_ marks: [ManualBookmark]) -> [BookmarkNode] {
        var i = 0
        func take(minLevel: Int) -> [BookmarkNode] {
            var out: [BookmarkNode] = []
            while i < marks.count {
                let mark = marks[i]
                if mark.level < minLevel { break }
                i += 1
                out.append(BookmarkNode(item: mark, children: take(minLevel: mark.level + 1)))
            }
            return out
        }
        return take(minLevel: 1)
    }

    private static func ancestors(of title: String, in nodes: [BookmarkNode], trail: [UUID] = []) -> [UUID]? {
        for node in nodes {
            if node.item.title.caseInsensitiveCompare(title) == .orderedSame {
                return trail
            }
            if let hit = ancestors(of: title, in: node.children, trail: trail + [node.id]) {
                return hit
            }
        }
        return nil
    }
}

private struct TagEditorPopover: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem

    private var live: LibraryItem {
        model.library.first(where: { $0.id == item.id }) ?? item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(model.L("Add tag…"), text: Binding(
                get: { model.tagDraft },
                set: { model.tagDraft = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                model.applyTag(model.tagDraft, to: live.id)
            }
            .frame(width: 200)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.allLibraryTags, id: \.self) { tag in
                        Button {
                            model.applyTag(tag, to: live.id)
                        } label: {
                            HStack {
                                Text(model.displayTag(tag))
                                Spacer()
                                if live.tags.contains(tag) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
        .padding(10)
    }
}

private struct TagBrowserPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.L("Tags"))
                .font(.caption.weight(.semibold))
            if model.allLibraryTags.isEmpty {
                Text(model.L("Add tag…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.allLibraryTags, id: \.self) { tag in
                HStack {
                    Button {
                        model.toggleLibraryTagFilter(tag)
                    } label: {
                        HStack {
                            Text(model.displayTag(tag))
                            Text("\(model.library.filter { $0.tags.contains(tag) }.count)")
                                .foregroundStyle(.secondary)
                            if model.libraryTagFilter.contains(tag) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(model.L("Rename tag")) {
                        model.tagRenameFrom = tag
                        model.tagRenameDraft = tag
                    }
                    .font(.caption)
                    Button(model.L("Delete tag"), role: .destructive) {
                        model.deleteLibraryTag(tag)
                    }
                    .font(.caption)
                }
            }
            if !model.tagRenameFrom.isEmpty {
                HStack {
                    TextField(model.L("Rename tag"), text: Binding(
                        get: { model.tagRenameDraft },
                        set: { model.tagRenameDraft = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.renameLibraryTag(from: model.tagRenameFrom, to: model.tagRenameDraft)
                    }
                    Button(model.L("Rename tag")) {
                        model.renameLibraryTag(from: model.tagRenameFrom, to: model.tagRenameDraft)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}

private struct LibraryCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck
    let item: LibraryItem

    var body: some View {
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
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                let shown = Array(item.tags.prefix(2))
                ForEach(shown, id: \.self) { tag in
                    Text(model.displayTag(tag))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(deck.cyan)
                }
                if item.tags.count > 2 {
                    Text("+\(item.tags.count - 2)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(deck.cyan)
                }
                if model.isNewestLibraryCard(item) {
                    Text(model.L("new"))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(deck.cyan)
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    model.isPairPickCandidate(item) || model.isLibrarySelected(item) ? deck.cyan : deck.line,
                    lineWidth: model.isPairPickCandidate(item) ? 2.5 : deck.border
                )
        )
        .opacity(model.awaitingPairPick && !model.isPairPickCandidate(item) && !model.isPairPickLead(item) ? 0.42 : 1)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { model.clickLibrary(item) }
    }
}

private struct AskStrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck
    @AppStorage("askHeight") private var askHeight = 260.0
    @AppStorage("askCollapsed") private var askCollapsed = false
    @State private var showRecent = false
    @State private var dragOrigin: Double?

    private var hasResult: Bool { !model.askAnswer.isEmpty || !model.askError.isEmpty }

    private var maxAskHeight: Double {
        let window = model.windowSize.height
        return window > 80 ? min(560, max(220, window * 0.55)) : 420
    }

    var body: some View {
        Group {
            if askCollapsed {
                collapsedBar
            } else {
                expandedAsk
            }
        }
        .background(deck.field)
        .overlay(Rectangle().frame(height: deck.border).foregroundStyle(deck.line), alignment: .top)
    }

    private var collapsedBar: some View {
        Button {
            askCollapsed = false
        } label: {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(model.L("open ASK"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(deck.muted)
                Image(systemName: "chevron.up.2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(deck.cyan)
                    .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.L("Show Ask"))
    }

    private var expandedAsk: some View {
        VStack(alignment: .leading, spacing: 8) {
            askHeader
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
                .help(model.L("AND, OR, NOT must be capitals. Words must sit in the same sentence or paragraph. Quotes keep a phrase together. Same as Search in files."))
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
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !model.askError.isEmpty {
                        Text(model.askError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !model.askAnswer.isEmpty {
                        Text(model.askAnswer)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if model.canRevealAskSource {
                                Button(model.L("Show in file")) { model.revealAskSource() }
                            }
                            if model.askHitsInReader.count > 1 {
                                SearchNavBits(
                                    summary: model.askHitSummary,
                                    onPrev: { model.prevAskHit() },
                                    onNext: { model.nextAskHit() },
                                    large: true
                                )
                            }
                            if model.canRevealAskSource {
                                Button(model.L("Add displayed Search Result to Forage")) { model.forageAskHit() }
                            }
                            if AskService.chapterWasSilent(model.askAnswer) {
                                Button("Search the web") { model.searchAskOnWeb() }
                            }
                        }
                        .font(.caption.weight(.semibold))
                        if !model.askOpenAnswer.isEmpty {
                            Text("From the model — not in this file")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(deck.muted)
                            Text(model.askOpenAnswer)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .frame(height: askHeight, alignment: .top)
    }

    private var askHeader: some View {
        HStack(spacing: 8) {
            Text(model.askHasKey ? "Your model · \(model.askModel)" : "Ask this chapter · this file only")
                .font(.caption.weight(.semibold))
                .foregroundStyle(deck.cyan)
                .lineLimit(1)
            Button {
                showRecent = true
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 8).fill(showRecent ? deck.btn : deck.panel))
                    .foregroundStyle(showRecent ? deck.btnText : deck.ink)
            }
            .buttonStyle(.plain)
            .disabled(model.askHistory.isEmpty)
            .help(model.L("Recent searches"))
            .popover(isPresented: $showRecent, arrowEdge: .top) {
                recentSearchesPopover
            }
            Button {
                model.clearAskHistory()
                showRecent = false
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(deck.ink)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(model.askHistory.isEmpty)
            .help(model.L("Clear Recent Searches"))
            Spacer(minLength: 8)
            if !model.allLibraryTags.isEmpty {
                Menu {
                    Button(model.L("This file")) {
                        model.askScopeTags = []
                    }
                    ForEach(model.allLibraryTags, id: \.self) { tag in
                        Button {
                            model.toggleAskScopeTag(tag)
                        } label: {
                            HStack {
                                Text(model.displayTag(tag))
                                if model.askScopeTags.contains(tag) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(model.askScopeTags.isEmpty
                         ? model.L("This file")
                         : model.askScopeTags.sorted().map { "#\($0)" }.joined(separator: " "))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 140)
            }
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
            .frame(maxWidth: 220)
            .help("Ask one chapter, or the whole file")
            Button {
                askCollapsed = true
            } label: {
                Image(systemName: "chevron.down.2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(deck.ink)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(model.L("Hide Ask"))
        }
        .padding(.top, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if dragOrigin == nil { dragOrigin = askHeight }
                    let next = (dragOrigin ?? askHeight) - Double(value.translation.height)
                    askHeight = min(maxAskHeight, max(150, next))
                }
                .onEnded { _ in dragOrigin = nil }
        )
        .help(model.L("Drag to change Ask height"))
    }

    private var recentSearchesPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.L("Recent searches"))
                .font(.caption.weight(.semibold))
            if model.askHistory.isEmpty {
                Text(model.L("No matches"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.askHistory) { record in
                            Button {
                                model.restoreAsk(record)
                                showRecent = false
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(record.question)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(deck.ink)
                                        .lineLimit(2)
                                    if !record.fileTitle.isEmpty {
                                        Text(record.fileTitle)
                                            .font(.system(size: 10))
                                            .foregroundStyle(deck.muted)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(10)
        .frame(width: 280)
    }
}

struct EnginePanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    var body: some View {
        Form {
            Section(model.L("Interface")) {
                Picker(model.L("Language"), selection: Binding(
                    get: { InterfaceStore.code },
                    set: { model.setInterfaceLang($0) }
                )) {
                    Text("US English").tag("en")
                    Text("Spanish").tag("es")
                    Text("Dutch").tag("nl")
                    ForEach(InterfaceStore.extraCodes, id: \.self) { code in
                        Text(TranslateLang.spoken.first(where: { $0.id == code })?.label ?? code).tag(code)
                    }
                }
                Text(model.L("If a translation causes a problem, yourMark opens in US English next time. A language that works stays after updates."))
                    .foregroundStyle(.secondary)
                if model.askHasKey {
                    Picker(model.L("Add a language"), selection: Binding(
                        get: { model.interfaceAddCode },
                        set: { model.interfaceAddCode = $0 }
                    )) {
                        ForEach(TranslateLang.spoken.filter { $0.id != "en" && $0.id != "es" && $0.id != "nl" }) { lang in
                            Text(lang.label).tag(lang.id)
                        }
                    }
                    Button(model.interfaceAddBusy ? model.L("Translating the interface…") : model.L("Add this language")) {
                        model.addInterfaceLanguage()
                    }
                    .disabled(model.interfaceAddBusy)
                    if !model.interfaceAddHint.isEmpty {
                        Text(model.interfaceAddHint)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(model.L("Lock an Ask AI key to add more interface languages."))
                        .foregroundStyle(.secondary)
                }
            }
            Section(model.L("Converted files")) {
                Picker(model.L("Save Markdown"), selection: Binding(
                    get: { model.filePlace },
                    set: {
                        if $0 == "custom" {
                            model.filePlace = $0
                            model.pickOutputFolder()
                        } else {
                            model.setFilePlace($0)
                        }
                    }
                )) {
                    if !Distribution.isAppStore {
                        Text(model.L("Next to the original PDF")).tag("beside")
                    }
                    Text(model.L("On this Mac only")).tag("library")
                    Text(model.L("Choose a folder…")).tag("custom")
                }
                Text(model.L(Distribution.isAppStore
                     ? "The App Store build defaults to On this Mac only — a hidden folder. Writing next to a PDF needs a folder you choose, because the sandbox cannot always write beside a dropped file."
                     : "Each convert makes a little folder (the Markdown plus a figures folder inside) so Finder stays tidy."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.L("On this Mac only is a hidden folder inside Application Support — not the folder you chose. Prefer Choose a folder for iCloud."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.L("iCloud or another cloud folder is safer. The author is not responsible for lost data."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.filePlace == "custom", !model.customFolderPath.isEmpty {
                    Text(model.customFolderPath)
                        .font(.caption)
                        .textSelection(.enabled)
                    Button(model.L("Change folder")) { model.pickOutputFolder() }
                } else if model.filePlace == "library" {
                    Text(model.convertedDir.path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
            Section(model.L("Library")) {
                Toggle(model.L("Ask before deleting one card"), isOn: Binding(
                    get: { !model.skipSingleDeleteConfirm },
                    set: { model.setSkipSingleDeleteConfirm(!$0) }
                ))
                Text(model.L("Several cards always ask."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(model.L("Also delete files and folders"), isOn: Binding(
                    get: { model.deleteFilesWithCard },
                    set: { model.setDeleteFilesWithCard($0) }
                ))
                Text(model.L("Off unless you tick it. Delete then removes that convert’s Markdown, figures, and its little folder. The original PDF stays. Forage notes stay on disk — delete those yourself in Finder."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(model.L("Rebuild Library from Default Folder.")) {
                    model.rebuildLibraryFromDefaultFolder()
                }
                Text(model.L("Adds cards for Markdown already in the folder you chose (or On this Mac only). Does not delete cards. New .md files in that folder are added automatically. File → Open or a drop also adds them without converting."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(model.L("This document")) {
                Toggle(model.L("Remove headers and footers"), isOn: Binding(
                    get: { model.stripChrome },
                    set: {
                        model.stripChrome = $0
                        UserDefaults.standard.set($0, forKey: "stripChrome")
                    }
                ))
                Text(model.L("Drops the repeating page title, page number, date, revision line, and header logos. Chapter headings and the real text stay. On by default — manuals look much cleaner."))
                    .foregroundStyle(.secondary)
            }
            Section(model.L("Reader")) {
                Picker(model.L("Font"), selection: Binding(
                    get: { model.previewFontName },
                    set: { model.setPreviewFont($0) }
                )) {
                    Text(model.L("Rounded (default)")).tag("rounded")
                    Text(model.L("System")).tag("system")
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
                Text(model.L("Applies to the Markdown pane.\nWe recommend Atkinson Hyperlegible for this app. Use Apple Font Book to install this free font."))
                    .foregroundStyle(.secondary)
                Picker(model.L("Bright look"), selection: Binding(
                    get: { model.brightLook },
                    set: { model.setBrightLook($0) }
                )) {
                    Text(model.L("Paper")).tag("paper")
                    Text(model.L("Plain white")).tag("white")
                }
                Text(model.L("Paper is the warm bright look. Plain white is for people who want a white page. The BRIGHT button in the top bar uses this. SYSTEM still follows the Mac."))
                    .foregroundStyle(.secondary)
            }
            Section(model.L("Editor")) {
                Text(model.L("yourMark is a reader. Press Edit to open the file beside this window. MarkEdit is the Mac default. MarkText is what we recommend on Windows — you can try it on this Mac too."))
                    .foregroundStyle(.secondary)
                Picker(model.L("Edit opens"), selection: Binding(
                    get: { model.editorChoice },
                    set: { model.setEditorChoice($0) }
                )) {
                    Text(model.L("MarkEdit (default)")).tag("markedit")
                    Text("MarkText").tag("marktext")
                    Text(model.L("An app I choose")).tag("custom")
                }
                if model.editorChoice == "markedit" {
                    if AppModel.markEditAppURL() != nil {
                        Text(model.L("MarkEdit is installed on this Mac."))
                            .foregroundStyle(.secondary)
                        Button(model.L("Open MarkEdit")) {
                            if let app = AppModel.markEditAppURL() {
                                NSWorkspace.shared.open(app)
                            }
                        }
                    } else {
                        Button(model.L("Get MarkEdit (free)")) {
                            model.openMarkEditDownload()
                        }
                        Text(model.L("Or in Terminal: brew install --cask markedit"))
                            .font(.caption)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                } else if model.editorChoice == "marktext" {
                    if AppModel.markTextAppURL() != nil {
                        Text(model.L("MarkText is installed on this Mac. Windows users use this same editor."))
                            .foregroundStyle(.secondary)
                        Button(model.L("Open MarkText")) {
                            if let app = AppModel.markTextAppURL() {
                                NSWorkspace.shared.open(app)
                            }
                        }
                    } else {
                        Button(model.L("Get MarkText (free)")) {
                            model.openMarkTextDownload()
                        }
                        Text(model.L("GitHub: marktext/marktext — Homebrew’s MarkText cask is disabled."))
                            .font(.caption)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(model.L("We open Applications. Click the editor you want (for example Typora, iA Writer, or MacDown). If that app can open Markdown, Edit sends the file there immediately."))
                        .foregroundStyle(.secondary)
                    if !model.customEditorName.isEmpty {
                        LabeledContent(model.L("This Mac will use"), value: model.customEditorName)
                        if !model.customEditorScheme.isEmpty {
                            Text("That app also has a link (\(model.customEditorScheme)://). Edit still opens the file in the app, not a blank window.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button(model.customEditorName.isEmpty ? model.L("Choose an editor…") : model.L("Choose a different editor…")) {
                        model.pickCustomEditor()
                    }
                }
                Text(model.L("Edit is one language at a time — never both. SIDE BY SIDE turns off. yourMark shows the file you picked so you can edit it beside the reader. Translate never overwrites the original; that is a second file."))
                    .foregroundStyle(.secondary)
                Picker(model.L("When I press Edit"), selection: Binding(
                    get: { model.editTarget },
                    set: { model.setEditTarget($0) }
                )) {
                    Text(model.L("Ask each time")).tag("ask")
                    Text(model.L("The original Markdown")).tag("original")
                    Text(model.L("The translation")).tag("translation")
                }
            }
            if Distribution.isAppStore {
                Section(model.L("Converter")) {
                    LabeledContent(model.L("Engine"), value: Distribution.converterLabel)
                    Text(model.L("This copy includes a converter that turns PDFs into Markdown.\nThat makes the words easier to read, search, and edit in a Markdown editor.\nWord and PowerPoint convert the same way.\nPhotographed pages use Apple Live Text, already on this Mac.\nNothing extra is downloaded.\nKeep the original file."))
                        .foregroundStyle(.secondary)
                    Button(model.L("Privacy")) {
                        NSWorkspace.shared.open(Distribution.privacyURL)
                    }
                    Button(model.L("Support")) {
                        NSWorkspace.shared.open(Distribution.supportURL)
                    }
                }
            }
            if model.settingsFocus == "ocr", !Distribution.isAppStore {
                Section {
                    Text(model.L("Install OCR here — Scanned PDFs, below. IBM Docling handles scans, tables, and figures."))
                        .foregroundStyle(.secondary)
                }
            }
            if !Distribution.isAppStore {
            Section(model.L("Microsoft MarkItDown")) {
                LabeledContent(model.L("Version"), value: model.engineVersion)
                LabeledContent(model.L("Path")) {
                    Text(model.enginePath ?? model.L("Not found"))
                        .textSelection(.enabled)
                }
                Text(model.L("The GUI does not pin or vendor the converter. About once a day it checks PyPI and upgrades if Microsoft shipped a newer package. Install / Upgrade does that immediately."))
                    .foregroundStyle(.secondary)
                Button(model.L("Install or reinstall")) { Task { await model.installEngine() } }
                    .disabled(model.installingEngine)
                Text(model.L("Installs Microsoft MarkItDown, the converter for ordinary PDFs and Office files."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }
            Section(model.L("Ask AI")) {
                Picker(model.L("Provider"), selection: Binding(
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
                    Text(model.L("Custom")).tag("custom")
                }
                if model.askProvider == "custom" {
                    TextField(model.L("Model"), text: Binding(
                        get: { model.askModel },
                        set: { model.askModel = $0 }
                    ))
                    TextField("Base URL", text: Binding(
                        get: { model.askBaseURL },
                        set: { model.askBaseURL = $0 }
                    ))
                } else {
                    Picker(model.L("Model"), selection: Binding(
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
                    Text(model.L("API key"))
                    Text(model.L("xAI keys start with xai- (from console.x.ai). OpenAI keys start with sk-. Provider must match the key — yourMark will switch it for you when you press Enter."))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .center, spacing: 10) {
                        SecureField(
                            model.L(model.askHasKey ? "Key locked in — paste a new one to replace" : "Paste your API key here"),
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
                        Button(model.askCheckingKey ? model.L("Testing…") : model.L("Enter")) { model.lockAskKey() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(model.askCheckingKey)
                            .help(model.L("Lock this API key on this Mac"))
                    }
                    Text(model.L("Paste the key, then press Enter. yourMark sends one short test question so you know the key works before it is locked in. The key stays on this Mac. It is sent only when you ask, to the provider you pick."))
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
                            Label(model.askKeyTestNote.isEmpty ? model.L("Key test passed. Ask is ready.") : model.askKeyTestNote, systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text(model.L("This key has not been tested yet."))
                                .foregroundStyle(.secondary)
                            Button(model.L("Test this key")) { model.testLockedKey() }
                                .disabled(model.askCheckingKey)
                        }
                        if (model.askKeyKind == "openai" && model.askProvider == "xai")
                            || (model.askKeyKind == "xai" && model.askProvider == "openai") {
                            Text(model.L("This key does not match the Provider above. Press Enter after pasting again — yourMark will switch Provider to match the key."))
                                .foregroundStyle(.orange)
                        }
                        Button(model.L("Clear key"), role: .destructive) { model.clearAskKey() }
                    }
                }
                Toggle(model.L("If the chapter does not provide an answer, also show a model summary"), isOn: Binding(
                    get: { model.askWebFallback },
                    set: {
                        model.askWebFallback = $0
                        UserDefaults.standard.set($0, forKey: "askWebFallback")
                    }
                ))
                Toggle(model.L("Automatically add chapters with AI when the file has no outline"), isOn: Binding(
                    get: { model.aiChaptersEnabled },
                    set: {
                        model.aiChaptersEnabled = $0
                        UserDefaults.standard.set($0, forKey: "aiChaptersEnabled")
                    }
                ))
                Text(model.L("Uses your Ask AI key after conversion. Inserts ## headings where chapters clearly start. Off unless you tick it. Needs a saved key."))
                    .foregroundStyle(.secondary)
                if !Distribution.isAppStore {
                    Toggle(model.L("Read text inside pictures with your Ask AI key"), isOn: Binding(
                        get: { model.askReadPictures },
                        set: {
                            model.askReadPictures = $0
                            UserDefaults.standard.set($0, forKey: "askReadPictures")
                        }
                    ))
                    Text(model.L("Microsoft’s markitdown-ocr plugin sends pictures to your AI so it can read labels on diagrams. Off unless you tick it. A large PDF can mean many requests and a bill. Needs a saved key. Pictures themselves are always saved locally, with or without this."))
                        .foregroundStyle(.secondary)
                }
            }
            Section(model.L("Translate")) {
                Picker(model.L("Engine"), selection: Binding(
                    get: { model.translateEngine },
                    set: {
                        model.translateEngine = $0
                        model.persistTranslateSettings()
                    }
                )) {
                    Text(model.L("Your Ask AI key")).tag("ask")
                    Text(model.L("Google Translate (optional)")).tag("google")
                }
                Text(model.L(model.canTranslate
                     ? (model.translateEngine == "google"
                        ? "The open chapter is sent to Google when you press Translate. Convert still stays on this Mac."
                        : "The open chapter is sent to your Ask model when you press Translate. Convert still stays on this Mac.")
                     : "Lock an Ask AI key or a Google Translate key. The Translate tools then appear in the reader."))
                    .foregroundStyle(.secondary)
                Text(model.L("Entire file on a large manual can cost a lot on your Ask AI key or Google bill. Prefer This chapter. The reader can show a long file. Entire file still sends a lot of text to the AI."))
                    .foregroundStyle(.secondary)
                if model.translateEngine == "google" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.L("Google Translate API key"))
                        Text(model.L("Turn on Cloud Translation API in your Google Cloud project, then create an API key."))
                            .foregroundStyle(.secondary)
                        if let help = URL(string: "https://cloud.google.com/docs/authentication/api-keys") {
                            Button {
                                NSWorkspace.shared.open(help)
                            } label: {
                                HStack(spacing: 5) {
                                    Text(model.L("How to get a Google Translate key"))
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
                            .help(model.L("Opens Google’s help in your browser"))
                        }
                        HStack {
                            SecureField(
                                model.L(model.googleHasKey ? "Key locked in — paste a new one to replace" : "Paste your Google API key here"),
                                text: Binding(
                                    get: { model.googleKeyDraft },
                                    set: { model.googleKeyDraft = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.lockGoogleTranslateKey() }
                            Button(model.googleCheckingKey ? model.L("Testing…") : model.L("Enter")) {
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
                                model.googleKeyTestNote.isEmpty ? model.L("Google Translate key is locked in.") : model.googleKeyTestNote,
                                systemImage: "lock.fill"
                            )
                            .foregroundStyle(.green)
                            Button(model.L("Clear key"), role: .destructive) { model.clearGoogleTranslateKey() }
                        }
                    }
                }
                Picker(model.L("In the reader"), selection: Binding(
                    get: { model.translateLayout },
                    set: {
                        model.translateLayout = $0
                        model.persistTranslateSettings()
                    }
                )) {
                    Text(model.L("Below each paragraph")).tag("below")
                    Text(model.L("Replace the original (recommended for SIDE BY SIDE)")).tag("replace")
                }
                Picker(model.L("After Translate"), selection: Binding(
                    get: { model.translateSaveMode },
                    set: {
                        model.translateSaveMode = $0
                        model.persistTranslateSettings()
                    }
                )) {
                    Text(model.L("Keep in the reader until I save a copy")).tag("keep")
                    Text(model.L("Save a second file next to the original")).tag("copy")
                }
                Text(model.L("The original Markdown is never overwritten. Save a copy writes Manual.es.md beside it and uses the same pictures folder."))
                    .foregroundStyle(.secondary)
            }
            Section(model.L("Scanned PDFs")) {
                Toggle(model.L("Read photographed pages"), isOn: Binding(
                    get: { model.ocrEnabled },
                    set: {
                        model.ocrEnabled = $0
                        UserDefaults.standard.set($0, forKey: "ocrEnabled")
                    }
                ))
                if Distribution.isAppStore {
                    LabeledContent(model.L("Scanner"), value: model.L("Apple Live Text — words on this Mac"))
                    Text(model.L("This App Store copy cannot download Docling. Apple does not allow the app to install new software after you buy it. It stays on Live Text."))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(model.L("Scanner"), selection: Binding(
                        get: { model.ocrScanner },
                        set: { model.setOcrScanner($0) }
                    )) {
                        Text(model.L("Apple Live Text — words on this Mac")).tag("livetext")
                        Text(model.L("IBM Docling — tables and layout")).tag("docling")
                    }
                    Text(model.L("Live Text is already on this Mac and reads the words. Docling is better at tables, columns, and pictures. It is a large extra (about 2 GB)."))
                        .foregroundStyle(.secondary)
                }
                Picker(model.L("OCR app"), selection: Binding(
                    get: { model.ocrAppChoice },
                    set: { model.setOcrAppChoice($0) }
                )) {
                    Text(model.L("None")).tag("none")
                    Text(model.L("An app I choose")).tag("custom")
                }
                if model.ocrAppChoice == "custom" {
                    Text(model.L("We open Applications. Click the app you use to make a PDF searchable. yourMark opens the original PDF there and does not write Manual.searchable.pdf."))
                        .foregroundStyle(.secondary)
                    if !model.customOcrAppName.isEmpty {
                        LabeledContent(model.L("This Mac will use"), value: model.customOcrAppName)
                    }
                    Button(model.customOcrAppName.isEmpty ? model.L("Choose an OCR app…") : model.L("Choose a different OCR app…")) {
                        model.pickCustomOcrApp()
                    }
                }
                if !Distribution.isAppStore {
                    Text(model.L("Recommended: OCRmyPDF — searchable pages and tables as text. There is no notarized Mac app on GitHub; Mac install is Homebrew (brew install ocrmypdf)."))
                        .foregroundStyle(.secondary)
                    Button(model.L("Get OCRmyPDF")) {
                        model.openOcrmypdfSite()
                    }
                    Toggle(model.L("Keep a searchable PDF"), isOn: Binding(
                        get: { model.saveOcrPdf },
                        set: {
                            model.saveOcrPdf = $0
                            UserDefaults.standard.set($0, forKey: "saveOcrPdf")
                        }
                    ))
                    Text(model.L("Extra time. Writes Manual.searchable.pdf next to the Markdown when OCRmyPDF runs — or when you press SAVE OCR PDF in the top bar. A long scan can take minutes. Off unless you tick it. Needs the optional backup scanner below. This is a searchable copy of the original PDF only. It cannot turn edited Markdown, or a translation, into a new PDF."))
                        .foregroundStyle(.secondary)
                }
                if !model.ocrScannerHint.isEmpty {
                    Text(model.ocrScannerHint)
                        .foregroundStyle(.orange)
                }
                if !Distribution.isAppStore {
                    LabeledContent(model.L("Layout scanner")) {
                        Text(model.doclingPath == nil ? model.L("Not on this Mac yet") : model.L("Ready"))
                    }
                    Button(model.doclingPath == nil ? model.L("Get the layout scanner") : model.L("Reinstall the layout scanner")) {
                        model.setOcrScanner("docling")
                        Task { await model.installDocling() }
                    }
                    .disabled(model.installingEngine)
                    Text(model.L(model.doclingPath == nil
                         ? "One download, from this window. Then photographed pages use tables and columns. Needs the internet."
                         : "Ready on this Mac. Press Reinstall only if scans start failing."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(model.ocrmypdfPath == nil ? model.L("Optional backup scanner") : model.L("Reinstall backup scanner")) {
                        Task { await model.installOcrmypdf() }
                    }
                    .disabled(model.installingEngine)
                    Text(model.L(model.ocrmypdfPath == nil
                         ? "Only if you want a second fallback. Live Text already works without this."
                         : "Backup is ready if the layout scanner cannot run."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if Distribution.isAppStore {
                Section(model.L("Updates")) {
                    Button(model.L("App Store updates")) {
                        if let url = URL(string: "macappstore://showUpdatesPage") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Text(model.L("This copy updates from the App Store. There is no GitHub download in this build."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !Distribution.isAppStore {
            Section(model.L("GitHub updates")) {
                VStack(alignment: .leading, spacing: 4) {
                    Button(model.L("Check for update of the main app")) {
                        Task { await model.checkUpdates(force: true) }
                    }
                    Text(model.L("Looks on GitHub for a newer yourMark and offers the download."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Button(model.L("Check for update of the processing engine")) {
                        Task { await model.upgradeEngine() }
                    }
                    .disabled(model.isBusy)
                    Text(model.L("Pulls the latest Microsoft MarkItDown. Does not change the yourMark app itself."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Button(model.L("Recheck converter")) { Task { await model.bootstrap() } }
                    Text(model.L("Confirms MarkItDown is on this Mac after an install or a failed launch."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            }
            if !Distribution.isAppStore, !model.lastUpgradeLog.isEmpty {
                Section(model.L("Last upgrade")) {
                    Text(model.lastUpgradeLog)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            if Distribution.isAppStore {
                Section(model.L("Crash reports")) {
                    Text(model.L("Apple already collects crashes for this App Store copy. You do not need to send anything. If you want to add a note, email a report — Mail opens with the log on the clipboard."))
                        .foregroundStyle(.secondary)
                    if CrashReports.latestAny() != nil {
                        Button(model.L("Email last crash report")) { model.emailLastCrash() }
                    }
                }
            } else {
                Section(model.L("Crash reports")) {
                    Toggle(model.L("Offer to copy crash reports"), isOn: Binding(
                        get: { model.offerCrashReports },
                        set: { model.setOfferCrashReports($0) }
                    ))
                    Text(model.L("If yourMark closed unexpectedly, we can copy the macOS report. Paste it in a message if you want. Nothing is sent unless you choose. You do not need a GitHub account."))
                        .foregroundStyle(.secondary)
                    if CrashReports.latestAny() != nil {
                        Button(model.L("Copy last crash report")) { model.sendLastCrash() }
                    }
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

/// GearUp-style wipe while SAVE OCR PDF is running.
private struct SweepActionButton: View {
    let title: String
    var sweeping: Bool
    var disabled: Bool
    let action: () -> Void
    @Environment(\.deck) private var deck

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.bold))
                .tracking(0.4)
                .foregroundStyle(deck.btnText)
                .padding(.horizontal, 12)
                .frame(height: BarFit.h)
                .background {
                    if sweeping {
                        SweepFill(fill: deck.btn, wash: deck.field, looping: true)
                            .id(sweeping)
                    } else {
                        deck.btn
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(disabled || sweeping)
        .allowsHitTesting(!sweeping)
        .help(sweeping
              ? "Writing the searchable PDF…"
              : "Writes Manual.searchable.pdf from the original scan. Extra time. Cannot make a PDF from edited or translated Markdown.")
    }
}

private struct SweepFill: View {
    var fill: Color
    var wash: Color
    var looping: Bool = false
    @State private var phase = false

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                fill.frame(width: g.size.width)
                wash.frame(width: g.size.width)
            }
            .frame(width: g.size.width * 2, alignment: .leading)
            .offset(x: phase ? 0 : -g.size.width)
        }
        .clipped()
        .onAppear {
            phase = false
            let curve = Animation.timingCurve(0.4, 0, 0.15, 1, duration: 1.65)
            DispatchQueue.main.async {
                if looping {
                    withAnimation(curve.repeatForever(autoreverses: false)) { phase = true }
                } else {
                    withAnimation(curve) { phase = true }
                }
            }
        }
        .id(looping)
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
            IncomingURLs.collect(from: providers, then: onDrop)
        }
    }
}

/// Clicks in a reader pane set SyncScroll lead without stealing scroll or text selection.
private struct PaneLeadCatcher: NSViewRepresentable {
    var onLead: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onLead = onLead
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onLead = onLead
    }

    final class MonitorView: NSView {
        var onLead: (() -> Void)?
        nonisolated(unsafe) private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                dropMonitor()
                return
            }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.consider(event)
                return event
            }
        }

        private func dropMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func consider(_ event: NSEvent) {
            guard let window, event.window === window else { return }
            let loc = convert(event.locationInWindow, from: nil)
            if bounds.contains(loc) { onLead?() }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
