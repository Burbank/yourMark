import Foundation

enum AppUpdates {
    static let githubRepo = "Burbank/yourMark"
    static let latestAPI = URL(string: "https://api.github.com/repos/Burbank/yourMark/releases/latest")!
    static let pypiAPI = URL(string: "https://pypi.org/pypi/markitdown/json")!
    static let releasesPage = URL(string: "https://github.com/Burbank/yourMark/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String?
    }

    struct PyPI: Decodable {
        struct Info: Decodable { let version: String }
        let info: Info
    }

    static func fetchLatestApp() async -> (tag: String, url: URL)? {
        var req = URLRequest(url: latestAPI)
        req.setValue("yourMark/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let rel = try? JSONDecoder().decode(GitHubRelease.self, from: data)
        else { return nil }
        let tag = rel.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard isNewer(tag, than: currentVersion) else { return nil }
        let url = rel.html_url.flatMap(URL.init(string:)) ?? releasesPage
        return (tag, url)
    }

    static func fetchPyPIVersion() async -> String? {
        var req = URLRequest(url: pypiAPI)
        req.setValue("yourMark/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let pypi = try? JSONDecoder().decode(PyPI.self, from: data)
        else { return nil }
        return pypi.info.version
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate)
        let b = numbers(current)
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func engineVersionToken(_ raw: String) -> String {
        raw.split(whereSeparator: { $0 == " " || $0 == "\n" }).last.map(String.init) ?? raw
    }

    private static func numbers(_ s: String) -> [Int] {
        s.split(separator: ".").compactMap { Int($0.filter(\.isNumber)) }
    }
}
