import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ConvertibleKind {
    static let extensions: Set<String> = [
        "pdf", "docx", "pptx", "xlsx", "xls", "html", "htm", "md", "txt", "epub",
    ]

    static func allows(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

/// Full-window file drop. Stays above SwiftUI so a PDF dropped on Library,
/// Bookmarks, Settings, or the header still converts.
@MainActor
struct FileDropCatcher: NSViewRepresentable {
    var onHover: (Bool) -> Void
    var onURLs: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHover: onHover, onURLs: onURLs)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onHover = onHover
        context.coordinator.onURLs = onURLs
    }

    @MainActor
    final class Coordinator {
        var onHover: (Bool) -> Void
        var onURLs: ([URL]) -> Void
        let probe: ProbeView

        init(onHover: @escaping (Bool) -> Void, onURLs: @escaping ([URL]) -> Void) {
            self.onHover = onHover
            self.onURLs = onURLs
            let probe = ProbeView()
            self.probe = probe
            probe.owner = self
        }
    }

    final class ProbeView: NSView {
        weak var owner: Coordinator?
        private weak var overlay: DropOverlay?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            install()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            install()
        }

        private func install() {
            guard let content = window?.contentView else { return }
            window?.tabbingMode = .disallowed
            if overlay == nil || overlay?.superview !== content {
                overlay?.removeFromSuperview()
                let view = DropOverlay(frame: content.bounds)
                view.autoresizingMask = [.width, .height]
                view.onHover = { [weak self] flag in self?.owner?.onHover(flag) }
                view.onURLs = { [weak self] urls in self?.owner?.onURLs(urls) }
                content.addSubview(view, positioned: .above, relativeTo: nil)
                overlay = view
            } else {
                overlay?.frame = content.bounds
                content.addSubview(overlay!, positioned: .above, relativeTo: nil)
            }
        }
    }

    final class DropOverlay: NSView {
        var onHover: ((Bool) -> Void)?
        var onURLs: (([URL]) -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([
                .fileURL,
                .URL,
                NSPasteboard.PasteboardType("NSFilenamesPboardType"),
                NSPasteboard.PasteboardType("public.file-url"),
            ])
            wantsLayer = true
            layer?.zPosition = 10_000
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            fileDragActive() ? self : nil
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            superview?.addSubview(self, positioned: .above, relativeTo: nil)
            let ok = !readURLs(from: sender).isEmpty
            if ok { onHover?(true) }
            return ok ? .copy : []
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            !readURLs(from: sender).isEmpty ? .copy : []
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            onHover?(false)
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            !readURLs(from: sender).isEmpty
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            onHover?(false)
            let urls = readURLs(from: sender)
            guard !urls.isEmpty else { return false }
            for url in urls { _ = url.startAccessingSecurityScopedResource() }
            DispatchQueue.main.async { self.onURLs?(urls) }
            return true
        }

        override func concludeDragOperation(_ sender: NSDraggingInfo?) {
            onHover?(false)
        }

        override func wantsPeriodicDraggingUpdates() -> Bool { false }

        private func readURLs(from sender: NSDraggingInfo) -> [URL] {
            var urls: [URL] = []
            let pb = sender.draggingPasteboard
            if let objs = pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: true,
            ]) as? [URL] {
                urls.append(contentsOf: objs)
            }
            if let paths = pb.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
                urls.append(contentsOf: paths.map { URL(fileURLWithPath: $0) })
            }
            return urls.filter { ConvertibleKind.allows($0) }
        }

        private func fileDragActive() -> Bool {
            let pb = NSPasteboard(name: .drag)
            let types = pb.types ?? []
            if types.isEmpty { return false }
            if pb.availableType(from: [.fileURL, .URL]) != nil { return true }
            return types.contains { t in
                let r = t.rawValue.lowercased()
                return r.contains("file") || r.contains("filename") || r.contains("url")
            }
        }
    }
}
