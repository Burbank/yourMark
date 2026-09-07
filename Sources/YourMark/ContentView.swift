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
                    title: "Drop FCOM, QRH, AIP, company briefs",
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

                Text("Study aid only — not for operations. Keep the official PDF as source of truth.")
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

    private var outline: [(id: String, level: Int, title: String)] {
        var used = Set<String>()
        var items: [(id: String, level: Int, title: String)] = []
        for line in model.previewMarkdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            guard s.hasPrefix("#") else { continue }
            var level = 0
            for ch in s {
                if ch == "#" { level += 1 } else { break }
            }
            guard (1...3).contains(level) else { continue }
            let title = s.drop(while: { $0 == "#" || $0 == " " }).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            var id = title.lowercased().replacingOccurrences(of: " ", with: "-")
            if used.contains(id) { id += "-\(items.count)" }
            used.insert(id)
            items.append((id, level, title))
        }
        return items
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline)
                    Text(item.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(item.id)
            }
            .frame(minWidth: 200)

            HSplitView {
                List {
                    Section("Bookmarks") {
                        if outline.isEmpty {
                            Text("No headings. Scanned PDFs need OCR first.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(outline, id: \.id) { item in
                            Text(item.title)
                                .font(.callout)
                                .padding(.leading, CGFloat((item.level - 1) * 10))
                        }
                    }
                }
                .frame(minWidth: 180, idealWidth: 220)

                ScrollView {
                    Text(model.previewMarkdown.isEmpty ? "Select a converted manual." : model.previewMarkdown)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
        }
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
            Section("What you get") {
                Text("Tables become Markdown tables when the PDF has a real table. Figures appear in reading order (not the original page layout). The bookmark pane is built from headings — the PDF outline, if MarkItDown found one.")
                    .foregroundStyle(.secondary)
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
    let onPick: () -> Void
    let onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose files…", action: onPick)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isTargeted ? DeckTheme.accent.opacity(0.10) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isTargeted ? DeckTheme.accent : Color.primary.opacity(0.14),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await loadURL(from: provider) {
                        urls.append(url)
                    }
                }
                if !urls.isEmpty {
                    await MainActor.run { onDrop(urls) }
                }
            }
            return true
        }
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

enum DeckTheme {
    static let bg = Color(red: 0.10, green: 0.14, blue: 0.20)
    static let accent = Color(red: 0.00, green: 0.63, blue: 0.89)
}

#Preview {
    ContentView()
        .environment(AppModel())
        .frame(width: 980, height: 640)
}
