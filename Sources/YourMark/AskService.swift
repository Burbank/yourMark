import Foundation

struct AskService {
    struct Settings {
        var provider: String
        var model: String
        var baseURL: String
        var apiKey: String
    }

    func ask(question: String, title: String, excerpt: String, settings: Settings, openKnowledge: Bool = false) async throws -> String {
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if code == 401 {
            throw YourMarkError.processFailed("Key was rejected. Check the provider and key.")
        }
        guard (200...299).contains(code) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
            throw YourMarkError.processFailed("Ask failed (\(code)) \(snippet)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        return text
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
}
