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

/// Window-level file drop. Hits only while a file drag is in progress, so clicks
/// still reach SwiftUI. Stops Finder from treating the drop as “open a new window”.
struct FileDropCatcher: NSViewRepresentable {
    var onURLs: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onURLs: onURLs) }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onURLs = onURLs
    }

    final class Coordinator {
        var onURLs: ([URL]) -> Void
        let probe = ProbeView()

        init(onURLs: @escaping ([URL]) -> Void) {
            self.onURLs = onURLs
            probe.owner = self
        }
    }

    final class ProbeView: NSView {
        weak var owner: Coordinator?
        private weak var overlay: DropOverlay?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let content = window?.contentView else { return }
            window?.tabbingMode = .disallowed
            if overlay == nil || overlay?.superview !== content {
                overlay?.removeFromSuperview()
                let view = DropOverlay(frame: content.bounds)
                view.autoresizingMask = [.width, .height]
                view.onURLs = { [weak self] urls in self?.owner?.onURLs(urls) }
                content.addSubview(view, positioned: .above, relativeTo: nil)
                overlay = view
            }
        }
    }

    final class DropOverlay: NSView {
        var onURLs: (([URL]) -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL])
            wantsLayer = false
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            registerForDraggedTypes([.fileURL])
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            fileDragPasteboard() == nil ? nil : self
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            droppable(sender) ? .copy : []
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            droppable(sender) ? .copy : []
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            droppable(sender)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let urls = readURLs(from: sender)
            guard !urls.isEmpty else { return false }
            DispatchQueue.main.async { self.onURLs?(urls) }
            return true
        }

        override func wantsPeriodicDraggingUpdates() -> Bool { false }

        private func droppable(_ sender: NSDraggingInfo) -> Bool {
            !readURLs(from: sender).isEmpty
        }

        private func readURLs(from sender: NSDraggingInfo) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true,
            ]
            let urls = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: options
            ) as? [URL] ?? []
            return urls.filter { ConvertibleKind.allows($0) }
        }

        private func fileDragPasteboard() -> NSPasteboard? {
            let pb = NSPasteboard(name: .drag)
            if pb.availableType(from: [.fileURL]) != nil { return pb }
            return nil
        }
    }
}
