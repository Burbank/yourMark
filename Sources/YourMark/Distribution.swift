import Foundation

/// Two ship channels, one codebase.
/// Direct (GitHub DMG): Microsoft MarkItDown + optional Docling, notarized Developer ID.
/// Mac App Store: sandboxed, no downloaded code — Apple PDFKit + Live Text.
enum Distribution {
    enum Channel: String {
        case direct
        case mas
    }

    static var channel: Channel {
        #if APPSTORE
        return .mas
        #else
        let raw = (Bundle.main.object(forInfoDictionaryKey: "YourMarkDistribution") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return raw == "mas" ? .mas : .direct
        #endif
    }

    static var isAppStore: Bool { channel == .mas }

    static var allowsEngineInstall: Bool { !isAppStore }
    static var allowsSelfMove: Bool { !isAppStore }
    static var allowsGitHubUpdates: Bool { !isAppStore }

    static var converterLabel: String {
        isAppStore ? "Microsoft MarkItDown (included)" : "Microsoft MarkItDown"
    }

    /// Python shipped inside the .app (Store build). Scripts run with this only.
    static var bundledPython: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("python/bin/python3", isDirectory: false)
    }

    static var bundledPythonPath: String? {
        guard let url = bundledPython,
              FileManager.default.isExecutableFile(atPath: url.path)
        else { return nil }
        return url.path
    }

    static var privacyURL: URL {
        URL(string: "https://burbank.github.io/yourMark/privacy.html")!
    }
}
