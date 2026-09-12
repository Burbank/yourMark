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
                        : "You are a careful study assistant. Answer only from the provided excerpt. When a fact is from the excerpt, include one short verbatim phrase in straight double quotes. If the excerpt is silent, say so clearly. Do not invent facts, citations, or numbers. Use short paragraphs.",
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

    /// Interface catalogs only — not the chapter-study prompt (that one often says “silent”).
    func translateInterface(
        keys: [String],
        languageLabel: String,
        languageCode: String,
        settings: Settings,
        onBatch: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [String: String] {
        let key = Self.normalizeKey(settings.apiKey)
        guard !key.isEmpty else {
            throw YourMarkError.processFailed("Lock an Ask AI key to add more interface languages.")
        }
        let batches = Self.interfaceBatches(keys)
        guard !batches.isEmpty else { return [:] }
        var merged: [String: String] = [:]
        for (i, batch) in batches.enumerated() {
            onBatch?(i + 1, batches.count)
            var piece = try await translateInterfaceBatch(
                batch,
                languageLabel: languageLabel,
                languageCode: languageCode,
                settings: settings
            )
            if piece.isEmpty {
                piece = try await translateInterfaceBatch(
                    batch,
                    languageLabel: languageLabel,
                    languageCode: languageCode,
                    settings: settings
                )
            }
            for (english, hit) in piece {
                merged[english] = hit
            }
        }
        return merged
    }

    private func translateInterfaceBatch(
        _ keys: [String],
        languageLabel: String,
        languageCode: String,
        settings: Settings
    ) async throws -> [String: String] {
        let key = Self.normalizeKey(settings.apiKey)
        let base = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw YourMarkError.invalidInput("Ask base URL is not valid.")
        }
        let payload = try JSONSerialization.data(withJSONObject: keys)
        guard let list = String(data: payload, encoding: .utf8) else {
            throw YourMarkError.processFailed("Could not prepare the interface lines.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        let body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 4000,
            "temperature": 0.2,
            "messages": [
                [
                    "role": "system",
                    "content": "You translate yourMark interface phrases. Reply with one JSON object only. Copy each English key exactly. Values are the \(languageLabel) translations. Keep product names (yourMark, Markdown, MarkEdit, SIDE BY SIDE). Language names stay in English. No markdown fences.",
                ],
                [
                    "role": "user",
                    "content": "Translate each string in this JSON array into \(languageLabel) (\(languageCode)).\n\n\(list)",
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
        return Self.parseInterfaceTable(text, keys: keys)
    }

    static func interfaceBatches(_ keys: [String], budget: Int = 2800) -> [[String]] {
        var out: [[String]] = []
        var cur: [String] = []
        var size = 0
        for key in keys {
            let extra = key.count + 8
            if !cur.isEmpty, size + extra > budget {
                out.append(cur)
                cur = []
                size = 0
            }
            cur.append(key)
            size += extra
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    static func parseInterfaceTable(_ raw: String, keys: [String]) -> [String: String] {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if let nl = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: nl)...])
            }
            if let fence = trimmed.range(of: "```", options: .backwards) {
                trimmed = String(trimmed[..<fence.lowerBound])
            }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end
        else { return [:] }
        var blob = String(trimmed[start...end])
        var obj = (try? JSONSerialization.jsonObject(with: Data(blob.utf8))) as? [String: Any]
        if obj == nil {
            blob = Self.repairInterfaceJSON(blob)
            obj = (try? JSONSerialization.jsonObject(with: Data(blob.utf8))) as? [String: Any]
        }
        guard let obj else { return [:] }
        let wanted = Set(keys)
        var out: [String: String] = [:]
        for (key, rawVal) in obj {
            guard wanted.contains(key) else { continue }
            let value: String
            if let s = rawVal as? String {
                value = s
            } else {
                value = String(describing: rawVal)
            }
            let hit = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hit.isEmpty { out[key] = hit }
        }
        return out
    }

    private static func repairInterfaceJSON(_ raw: String) -> String {
        var s = raw
        if let last = s.last, last != "}" {
            if let cut = s.lastIndex(of: "\"") {
                s = String(s[...cut])
            }
            s += "}"
        }
        return s
    }

    /// Title matching only — not the chapter-study prompt (that one often says “silent”).
    func matchLibraryTitles(query: String, titles: [String], settings: Settings) async throws -> [String] {
        let key = Self.normalizeKey(settings.apiKey)
        guard !key.isEmpty else { return [] }
        let base = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 40
        let list = titles.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 400,
            "temperature": 0,
            "messages": [
                [
                    "role": "system",
                    "content": "You match a search phrase to library titles. Reply with a JSON array of exact titles from the list. Match meaning, not only spelling. If none match, []. No other text.",
                ],
                [
                    "role": "user",
                    "content": "Search: \(query)\n\nTitles:\n\(list)",
                ],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else { return [] }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        return Self.parseTitleMatches(text, known: titles)
    }

    static func parseTitleMatches(_ raw: String, known: [String]) -> [String] {
        var names: [String] = []
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]"), start < end,
           let data = String(trimmed[start...end]).data(using: .utf8) {
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                names = arr
            } else if let objs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                names = objs.compactMap { $0["title"] as? String ?? $0["name"] as? String }
            }
        }
        var hits: [String] = []
        for name in names {
            let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if let match = known.first(where: {
                $0.caseInsensitiveCompare(t) == .orderedSame
                    || $0.localizedCaseInsensitiveContains(t)
                    || t.localizedCaseInsensitiveContains($0)
            }) {
                if !hits.contains(match) { hits.append(match) }
            }
        }
        if hits.isEmpty {
            for title in known where title.count >= 4 && trimmed.localizedCaseInsensitiveContains(title) {
                hits.append(title)
            }
        }
        return hits
    }

    struct KeyTest {
        var passed: Bool
        var message: String
    }

    /// One short chat to prove the key, the model, and billing all work.
    func testKey(_ settings: Settings) async -> KeyTest {
        let key = Self.normalizeKey(settings.apiKey)
        let host = settings.provider == "xai" ? "xAI" : settings.provider == "openai" ? "OpenAI" : "The API"
        let modelName = settings.model.isEmpty ? "the model" : settings.model
        guard !key.isEmpty else {
            return KeyTest(passed: false, message: "Paste an API key first.")
        }
        let base = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            return KeyTest(passed: false, message: "Ask base URL is not valid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25
        let body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 16,
            "temperature": 0,
            "messages": [
                ["role": "user", "content": "Reply with the single word OK."],
            ],
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let auth = Self.friendlyAuthError(code: code, body: data, key: key, provider: settings.provider) {
                return KeyTest(passed: false, message: "Key test failed. " + auth)
            }
            if (200...299).contains(code) {
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let choices = json?["choices"] as? [[String: Any]]
                let message = choices?.first?["message"] as? [String: Any]
                let text = (message?["content"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                let shown = text.isEmpty ? "OK" : String(text.prefix(40))
                return KeyTest(
                    passed: true,
                    message: "Key test passed. \(host) answered “\(shown)” using \(modelName). Ask is ready."
                )
            }
            return KeyTest(
                passed: false,
                message: "Key test failed. " + Self.friendlyHTTPError(code: code, body: data, model: settings.model, provider: settings.provider)
            )
        } catch {
            return KeyTest(passed: false, message: "Key test failed. Could not reach \(host). Check the internet and press Enter again.")
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

    static func excerpt(markdown: String, heading: String, startLine: Int? = nil, max: Int = 12000) -> String {
        if heading.isEmpty || heading == "Entire file" {
            return String(markdown.prefix(max))
        }
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let start: Int
        if let idx = startLine, lines.indices.contains(idx) {
            start = idx
        } else {
            let needle = heading.lowercased()
            guard let found = lines.firstIndex(where: {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased().contains(needle)
            }) else {
                return String(markdown.prefix(max))
            }
            start = found
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
