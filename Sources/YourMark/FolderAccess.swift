import Foundation

/// Remembers folders the user picked so a sandboxed App Store build can write there again.
enum FolderAccess {
    private static let customKey = "customFolderBookmark"
    nonisolated(unsafe) private static var held: [URL] = []

    static func saveCustomFolder(_ url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: customKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: customKey)
        }
    }

    @discardableResult
    static func restoreCustomFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: customKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale { saveCustomFolder(url) }
        return access(url)
    }

    @discardableResult
    static func access(_ url: URL) -> URL? {
        guard url.startAccessingSecurityScopedResource() else { return url }
        held.append(url)
        return url
    }

    static func accessPath(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        if let existing = held.first(where: { $0.path == path }) { return existing }
        if let restored = restoreCustomFolder(), restored.path == path { return restored }
        return access(URL(fileURLWithPath: path))
    }

    /// App Group used by the Share extension so a sandboxed convert can read the file.
    static let appGroupID = "group.com.burbank.yourmark"

    static var appGroupInbox: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }
}
