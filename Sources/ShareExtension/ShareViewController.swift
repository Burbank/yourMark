import AppKit
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: .zero)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task { @MainActor in
            await send()
        }
    }

    private func send() async {
        var paths: [String] = []
        for item in (extensionContext?.inputItems as? [NSExtensionItem]) ?? [] {
            for provider in item.attachments ?? [] {
                if let path = await Self.path(from: provider) {
                    paths.append(path)
                }
            }
        }
        if !paths.isEmpty {
            let staged = paths.compactMap { Self.stageInAppGroup(URL(fileURLWithPath: $0))?.path }
            let send = staged.isEmpty ? paths : staged
            var comps = URLComponents()
            comps.scheme = "yourmark"
            comps.host = "convert"
            comps.queryItems = send.map { URLQueryItem(name: "file", value: $0) }
            if let url = comps.url {
                NSWorkspace.shared.open(url)
            }
        }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    /// Copy into the shared Inbox so the sandboxed app can read the file.
    private static func stageInAppGroup(_ src: URL) -> URL? {
        _ = src.startAccessingSecurityScopedResource()
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.burbank.yourmark"
        ) else { return src }
        let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let dest = inbox.appendingPathComponent(
                "\(UUID().uuidString.prefix(8))-\(src.lastPathComponent)"
            )
            try FileManager.default.copyItem(at: src, to: dest)
            return dest
        } catch {
            return src
        }
    }

    private static func path(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    cont.resume(returning: url.path)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url.path)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
