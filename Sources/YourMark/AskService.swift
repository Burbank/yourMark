import Foundation

struct AskService {
    struct Settings {
        var provider: String
        var model: String
        var baseURL: String
        var apiKey: String
    }

    enum KeyKind: String {
        case xai, openai, other, empty
    }

    static func normalizeKey(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let eq = s.firstIndex(of: "="), s[..<eq].uppercased().contains("KEY") {
            s = String(s[s.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let bearer = "bearer "
        if s.lowercased().hasPrefix(bearer) {
            s = String(s.dropFirst(bearer.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    static func keyKind(_ raw: String) -> KeyKind {
        let s = normalizeKey(raw).lowercased()
        if s.isEmpty { return .empty }
        if s.hasPrefix("xai-") { return .xai }
        if s.hasPrefix("sk-ant-") { return .other }
        if s.hasPrefix("sk-") { return .openai }
        return .other
    }

    static func keyTail(_ raw: String) -> String {
        let s = normalizeKey(raw)
        guard s.count >= 8 else { return "" }
        return String(s.suffix(4))
    }

    static func kindLabel(_ kind: KeyKind) -> String {
        switch kind {
        case .xai: return "xAI (Grok)"
        case .openai: return "OpenAI"
        case .other: return "custom"
        case .empty: return ""
        }
    }

    func ask(question: String, title: String, excerpt: String, settings: Settings, openKnowledge: Bool = false) async throws -> String {
        let key = Self.normalizeKey(settings.apiKey)
        if key.isEmpty {
            return Self.localAsk(question: question, excerpt: excerpt)
        }
        let base = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw YourMarkError.invalidInput("Ask base URL is not valid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90

        let body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 1200,
            "temperature": 0.2,
            "messages": [
                [
                    "role": "system",
                    "content": openKnowledge
                        ? "The student's file did not contain this. Give a short study summary from general knowledge. Do not pretend it came from their notes. Flag uncertainty. Two to four short paragraphs."
                        : "You are a careful study assistant. Answer only from the provided excerpt. Quote short phrases when they help. If the excerpt is silent, say so clearly. Do not invent facts, citations, or numbers. Use short paragraphs.",
                ],
                [
                    "role": "user",
                    "content": openKnowledge
                        ? "The chapter was silent.\nDocument: \(title)\nQuestion: \(question)\n\n(The file said: \(excerpt.prefix(800)))"
                        : "Document: \(title)\n\nExcerpt:\n\(excerpt)\n\nQuestion: \(question)",
                ],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let auth = Self.friendlyAuthError(code: code, body: data, key: key, provider: settings.provider) {
            throw YourMarkError.processFailed(auth)
        }
        guard (200...299).contains(code) else {
            throw YourMarkError.processFailed(Self.friendlyHTTPError(code: code, body: data, model: settings.model, provider: settings.provider))
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        return text
    }

    /// Cheap check used when locking a key in. GET /models — no chat charge.
    func verify(_ settings: Settings) async -> String? {
        let key = Self.normalizeKey(settings.apiKey)
        guard !key.isEmpty else { return "Paste an API key first." }
        let base = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/models") else {
            return "Ask base URL is not valid."
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let auth = Self.friendlyAuthError(code: code, body: data, key: key, provider: settings.provider) {
                return auth
            }
            if (200...299).contains(code) { return nil }
            return Self.friendlyHTTPError(code: code, body: data, model: settings.model, provider: settings.provider)
        } catch {
            return "Could not reach \(settings.provider == "xai" ? "xAI" : settings.provider == "openai" ? "OpenAI" : "the API"). Check the internet and try Enter again."
        }
    }

    static func friendlyAuthError(code: Int, body: Data, key: String, provider: String) -> String? {
        let snippet = String(data: body, encoding: .utf8)?.lowercased() ?? ""
        let looksBadKey = snippet.contains("incorrect api key")
            || snippet.contains("invalid api key")
            || snippet.contains("invalid_api_key")
            || snippet.contains("unauthorized")
            || snippet.contains("authentication")
            || snippet.contains("invalid x-api-key")
            || code == 401
            || (code == 400 && snippet.contains("incorrect"))
        guard looksBadKey else { return nil }

        let kind = keyKind(key)
        if kind == .openai && provider == "xai" {
            return "This key looks like OpenAI (it starts with sk-), but Ask is set to Grok. Open Settings → Provider → OpenAI, paste the key again, press Enter. Or paste an xAI key from console.x.ai."
        }
        if kind == .xai && provider == "openai" {
            return "This key looks like xAI (it starts with xai-), but Ask is set to OpenAI. Open Settings → Provider → xAI (Grok), paste the key again, press Enter."
        }
        let host = provider == "xai" ? "xAI" : provider == "openai" ? "OpenAI" : "The API"
        let whereFrom = provider == "xai"
            ? "https://console.x.ai"
            : provider == "openai" ? "https://platform.openai.com/api-keys" : "your API host"
        let tail = keyTail(key)
        let tailBit = tail.isEmpty ? "" : " The locked-in key ends with …\(tail)."
        return "\(host) rejected this key.\(tailBit) A partial paste can lock in a broken key. Open Settings → Clear key → paste it once more from \(whereFrom) → press Enter."
    }

    static func friendlyHTTPError(code: Int, body: Data, model: String, provider: String) -> String {
        let snippet = String(data: body, encoding: .utf8) ?? ""
        let low = snippet.lowercased()
        if low.contains("model") && (low.contains("not found") || low.contains("does not exist") || low.contains("invalid")) {
            return "The model “\(model)” is not available on this key. Pick another model in Settings."
        }
        if code == 429 {
            return "The API said too many requests. Wait a moment and try Ask again."
        }
        if code == 402 || low.contains("credit") || low.contains("quota") || low.contains("billing") {
            return "This key has no credit / quota left on \(provider == "xai" ? "xAI" : "the provider")."
        }
        return "Ask failed (\(code)). \(snippet.prefix(120))"
    }

    static func chapterWasSilent(_ text: String) -> Bool {
        let t = text.lowercased()
        let needles = [
            "excerpt does not", "excerpt is silent", "not in the excerpt",
            "not in this chapter", "not in this file", "does not define",
            "does not provide an answer",
            "does not mention", "not mentioned", "not defined in",
        ]
        return needles.contains { t.contains($0) }
    }

    static func searchQuery(question: String, title: String, chapter: String, note: String) -> String {
        [question, title, chapter, note].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    static func excerpt(markdown: String, heading: String, max: Int = 12000) -> String {
        if heading.isEmpty || heading == "Entire file" {
            return String(markdown.prefix(max))
        }
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let needle = heading.lowercased()
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased().contains(needle)
        }) else {
            return String(markdown.prefix(max))
        }
        let startLevel = lines[start].prefix(while: { $0 == "#" }).count
        var collected: [String] = []
        for i in start..<lines.count {
            if i > start {
                let lvl = lines[i].prefix(while: { $0 == "#" }).count
                if lines[i].hasPrefix("#"), lvl > 0, lvl <= startLevel { break }
            }
            collected.append(lines[i])
            if collected.joined(separator: "\n").count > max { break }
        }
        return String(collected.joined(separator: "\n").prefix(max))
    }

    static func localAsk(question: String, excerpt: String) -> String {
        let stop: Set<String> = [
            "the", "and", "for", "that", "this", "with", "from", "what", "when",
            "where", "which", "about", "does", "into", "have", "been",
        ]
        let words = question.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 && !stop.contains($0) }
        let paras = excerpt
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 40 && !$0.hasPrefix(">") }
        let scored = paras.map { p -> (String, Int) in
            let low = p.lowercased()
            return (p, words.reduce(0) { $0 + (low.contains($1) ? 1 : 0) })
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
        if scored.isEmpty {
            return "The chapter does not provide an answer to this. Nothing in this excerpt matches the question closely enough."
        }
        return scored.prefix(3).map { $0.0 }.joined(separator: "\n\n")
    }

    /// Insert ## / ### headings where chapters clearly start. Does not rewrite body text.
    func inferChapters(markdown: String, settings: Settings) async throws -> String {
        let sample = String(markdown.prefix(18_000))
        let prompt = """
        This Markdown is missing a usable chapter outline. Propose headings only.

        Return JSON only, an array of objects:
        [{"level":2,"title":"Chapter title","needle":"exact phrase copied from the text that starts that section"}]

        Rules:
        - needle MUST be a verbatim substring of the document (at least 12 characters).
        - Do not invent content. 4–20 headings.
        - Skip a heading named Outline.
        - If the file already has a good outline, return [].

        Document:
        \(sample)
        """
        let raw = try await ask(
            question: prompt,
            title: "chapters",
            excerpt: sample,
            settings: settings,
            openKnowledge: false
        )
        guard let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]") else {
            return markdown
        }
        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8),
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return markdown }

        var text = markdown
        for row in rows.reversed() {
            let title = (row["title"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let needle = (row["needle"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let level = min(3, max(2, row["level"] as? Int ?? 2))
            guard title.count >= 2, needle.count >= 12,
                  let range = text.range(of: needle, options: .caseInsensitive)
            else { continue }
            let before = text[..<range.lowerBound]
            if before.suffix(80).contains("# \(title)") || before.suffix(80).contains("#\(title)") {
                continue
            }
            let hashes = String(repeating: "#", count: level)
            text.replaceSubrange(range, with: "\n\(hashes) \(title)\n\n\(needle)")
        }
        return text
    }
}
