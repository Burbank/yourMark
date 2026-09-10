import Foundation

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
