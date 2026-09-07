import Foundation

struct AskService {
    struct Settings {
        var provider: String
        var model: String
        var baseURL: String
        var apiKey: String
    }

    func ask(question: String, title: String, excerpt: String, settings: Settings) async throws -> String {
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw YourMarkError.invalidInput("Add an Ask API key under Engine.")
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
                    "content": "You are a careful study assistant. Answer only from the provided excerpt. Quote short phrases when they help. If the excerpt is silent, say so clearly. Do not invent facts, citations, or numbers. Use short paragraphs.",
                ],
                [
                    "role": "user",
                    "content": "Document: \(title)\n\nExcerpt:\n\(excerpt)\n\nQuestion: \(question)",
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
}
