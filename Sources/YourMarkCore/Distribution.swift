import Foundation

/// Two ship channels, one codebase.
/// Direct (GitHub DMG): Microsoft MarkItDown + optional Docling, notarized Developer ID.
/// Mac App Store: sandboxed, no downloaded code — Apple PDFKit + Live Text.
public enum Distribution {
    public enum Channel: String {
        case direct
        case mas
    }

    public static var channel: Channel {
        #if APPSTORE
        return .mas
        #else
        let raw = (Bundle.main.object(forInfoDictionaryKey: "YourMarkDistribution") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return raw == "mas" ? .mas : .direct
        #endif
    }

    public static var isAppStore: Bool { channel == .mas }

    public static var allowsEngineInstall: Bool { !isAppStore }
    public static var allowsSelfMove: Bool { !isAppStore }
    public static var allowsGitHubUpdates: Bool { !isAppStore }

    public static var converterLabel: String {
        isAppStore ? "Microsoft MarkItDown (included)" : "Microsoft MarkItDown"
    }

    /// Python shipped inside the .app (Store build). Scripts run with this only.
    public static var bundledPython: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("python/bin/python3", isDirectory: false)
    }

    public static var bundledPythonPath: String? {
        guard let url = bundledPython,
              FileManager.default.isExecutableFile(atPath: url.path)
        else { return nil }
        return url.path
    }

    public static var privacyURL: URL {
        URL(string: "https://burbank.github.io/yourMark/privacy.html")!
    }

    /// App Store listing Support URL. Do not open this from the GitHub disk.
    public static var supportURL: URL {
        URL(string: "https://burbank.github.io/yourMark/support.html")!
    }

    /// App Store crash / support mail. Same inbox as the listing Support page.
    public static var supportMail: String { "dunia@tutamail.com" }
}
