import AppKit
import Foundation
import UniformTypeIdentifiers

enum IncomingURLs {
    /// File drops, `open -a`, and `yourmark://convert?file=/path/to.pdf`.
    static func files(from url: URL) -> [URL] {
        if url.isFileURL { return [url] }
        guard url.scheme?.lowercased() == "yourmark" else { return [] }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return []
        }
        return items.compactMap { item -> URL? in
            guard ["file", "path", "url"].contains(item.name.lowercased()),
                  let raw = item.value, !raw.isEmpty
            else { return nil }
            return fileURL(fromParameter: raw)
        }
    }

    /// Shared SwiftUI drop loader. FileDropCatcher is the main window path.
    static func collect(from providers: [NSItemProvider], convertiblesOnly: Bool = false, then deliver: @escaping ([URL]) -> Void) -> Bool {
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
                if convertiblesOnly, !ConvertibleKind.allows(url) { return }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { deliver(urls) }
        }
        return true
    }

    private static func fileURL(fromParameter raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file:"), let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        let path = (trimmed as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }
}
