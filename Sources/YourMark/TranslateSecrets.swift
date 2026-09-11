import Foundation

enum TranslateSecrets {
    private static var fileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = root.appendingPathComponent("yourMark", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("google-translate-key")
    }

    static func load() -> String {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete()
            return
        }
        do {
            try trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: fileURL.path
            )
        } catch {
            return
        }
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
