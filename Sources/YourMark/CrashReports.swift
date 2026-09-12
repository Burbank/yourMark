import AppKit
import Foundation

struct CrashReport: Identifiable {
    var id: String
    var date: Date
    var summary: String
    var log: String
}

enum CrashReports {
    private static let sentKey = "sentCrashIDs"
    private static let bundleName = "yourMark"

    static func installHandler() {
        NSSetUncaughtExceptionHandler { exception in
            CrashReports.writeUncaught(exception)
        }
    }

    static func writeUncaught(_ exception: NSException) {
        let dir = supportDir.appendingPathComponent("crashes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let stack = exception.callStackSymbols.joined(separator: "\n")
        let text = """
        Uncaught \(exception.name.rawValue)
        \(exception.reason ?? "")

        \(stack)
        """
        let url = dir.appendingPathComponent("uncaught-\(stamp).txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        let lang = UserDefaults.standard.string(forKey: "interfaceLang") ?? "en"
        if lang != "en", lang != "es", lang != "nl" {
            UserDefaults.standard.set(true, forKey: "interfaceLangUnhealthy")
        }
    }

    static func latestUnsent() -> CrashReport? {
        let sent = Set(UserDefaults.standard.stringArray(forKey: sentKey) ?? [])
        return allReports().first { !sent.contains($0.id) }
    }

    static func latestAny() -> CrashReport? {
        allReports().first
    }

    static func markSent(_ id: String) {
        var sent = UserDefaults.standard.stringArray(forKey: sentKey) ?? []
        if !sent.contains(id) {
            sent.append(id)
            if sent.count > 40 { sent = Array(sent.suffix(40)) }
            UserDefaults.standard.set(sent, forKey: sentKey)
        }
    }

    static func githubURL(for report: CrashReport) -> URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let clipped = String(report.log.prefix(3500))
        let body = """
        ## Crash (sent from the app, with the user's OK)

        - yourMark \(version) (\(build))
        - \(os)
        - \(report.summary)

        The full report is also on the clipboard.

        ```
        \(clipped)
        ```

        No API keys or documents are included.
        """
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "github.com"
        parts.path = "/Burbank/yourMark/issues/new"
        parts.queryItems = [
            URLQueryItem(name: "title", value: "Crash: \(report.summary)"),
            URLQueryItem(name: "labels", value: "crash"),
            URLQueryItem(name: "body", value: body),
        ]
        return parts.url
    }

    static func copyLog(_ report: CrashReport) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.log, forType: .string)
    }

    static func openMail(for report: CrashReport) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let clipped = String(report.log.prefix(3500))
        let body = """
        yourMark \(version) (\(build))
        \(os)
        \(report.summary)

        The full report is also on the clipboard.

        \(clipped)
        """
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = Distribution.supportMail
        parts.queryItems = [
            URLQueryItem(name: "subject", value: "yourMark crash: \(report.summary)"),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = parts.url {
            NSWorkspace.shared.open(url)
        }
    }

    private static var supportDir: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return root.appendingPathComponent("yourMark", isDirectory: true)
    }

    private static func allReports() -> [CrashReport] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let folders = [
            home.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true),
            home.appendingPathComponent("Library/Logs/DiagnosticReports/Retired", isDirectory: true),
            supportDir.appendingPathComponent("crashes", isDirectory: true),
        ]
        var found: [CrashReport] = []
        for folder in folders {
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names {
                let lower = name.lowercased()
                guard lower.hasPrefix("yourmark") || lower.hasPrefix("uncaught-") else { continue }
                guard lower.hasSuffix(".ips") || lower.hasSuffix(".crash") || lower.hasSuffix(".txt") else { continue }
                let url = folder.appendingPathComponent(name)
                guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                      let date = attrs[.modificationDate] as? Date else { continue }
                guard date > Date().addingTimeInterval(-60 * 60 * 24 * 21) else { continue }
                guard let raw = try? String(contentsOf: url, encoding: .utf8), raw.count > 40 else { continue }
                found.append(CrashReport(
                    id: name,
                    date: date,
                    summary: summarize(raw),
                    log: scrub(raw)
                ))
            }
        }
        return found.sorted { $0.date > $1.date }
    }

    private static func summarize(_ raw: String) -> String {
        if let exc = firstMatch("\"type\"\\s*:\\s*\"([^\"]+)\"", in: raw) {
            let sig = firstMatch("\"signal\"\\s*:\\s*\"([^\"]+)\"", in: raw)
            if let sig, !sig.isEmpty { return "\(exc) (\(sig))" }
            return exc
        }
        if let line = raw.split(separator: "\n").first(where: { $0.contains("Exception Type") }) {
            return line.replacingOccurrences(of: "Exception Type:", with: "").trimmingCharacters(in: .whitespaces)
        }
        if raw.contains("Uncaught") {
            return raw.split(separator: "\n").first.map(String.init) ?? "Uncaught exception"
        }
        return "yourMark closed unexpectedly"
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func scrub(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "/Users/[^/]+") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "/Users/<user>")
    }
}
