import Foundation

struct TranslateLang: Identifiable, Hashable {
    var id: String
    var label: String

    static let auto = TranslateLang(id: "auto", label: "Auto-detect")

    static let spoken: [TranslateLang] = [
        TranslateLang(id: "en", label: "English"),
        TranslateLang(id: "nl", label: "Dutch"),
        TranslateLang(id: "de", label: "German"),
        TranslateLang(id: "fr", label: "French"),
        TranslateLang(id: "es", label: "Spanish"),
        TranslateLang(id: "pt", label: "Portuguese"),
        TranslateLang(id: "it", label: "Italian"),
        TranslateLang(id: "pl", label: "Polish"),
        TranslateLang(id: "sv", label: "Swedish"),
        TranslateLang(id: "no", label: "Norwegian"),
        TranslateLang(id: "da", label: "Danish"),
        TranslateLang(id: "fi", label: "Finnish"),
        TranslateLang(id: "el", label: "Greek"),
        TranslateLang(id: "tr", label: "Turkish"),
        TranslateLang(id: "ar", label: "Arabic"),
        TranslateLang(id: "he", label: "Hebrew"),
        TranslateLang(id: "hi", label: "Hindi"),
        TranslateLang(id: "zh-CN", label: "Chinese (Simplified)"),
        TranslateLang(id: "zh-TW", label: "Chinese (Traditional)"),
        TranslateLang(id: "ja", label: "Japanese"),
        TranslateLang(id: "ko", label: "Korean"),
        TranslateLang(id: "vi", label: "Vietnamese"),
        TranslateLang(id: "th", label: "Thai"),
        TranslateLang(id: "id", label: "Indonesian"),
        TranslateLang(id: "ro", label: "Romanian"),
        TranslateLang(id: "cs", label: "Czech"),
        TranslateLang(id: "hu", label: "Hungarian"),
        TranslateLang(id: "uk", label: "Ukrainian"),
        TranslateLang(id: "ru", label: "Russian"),
    ]

    static func label(for id: String) -> String {
        if id == auto.id { return auto.label }
        return spoken.first(where: { $0.id == id })?.label ?? id
    }

    static var deviceTo: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        if spoken.contains(where: { $0.id == code }) { return code }
        if code == "zh" { return "zh-CN" }
        return "en"
    }
}

struct TranslateBlock: Sendable {
    enum Kind { case text, keep }
    var kind: Kind
    var raw: String
    var prefix: String
    var body: String
}

enum TranslateService {
    static let marker = "<!--ym-tr-->"

    static func blocks(from markdown: String) -> [TranslateBlock] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [TranslateBlock] = []
        var para: [String] = []

        func flush() {
            let text = para.joined(separator: "\n")
            para.removeAll()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            out.append(makeBlock(text))
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
                out.append(TranslateBlock(kind: .keep, raw: "", prefix: "", body: ""))
                continue
            }
            if shouldKeep(line) && para.isEmpty {
                out.append(TranslateBlock(kind: .keep, raw: line, prefix: "", body: line))
                continue
            }
            if isHeading(line) && para.isEmpty {
                out.append(makeBlock(line))
                continue
            }
            if shouldKeep(line) {
                flush()
                out.append(TranslateBlock(kind: .keep, raw: line, prefix: "", body: line))
                continue
            }
            if isHeading(line) {
                flush()
                out.append(makeBlock(line))
                continue
            }
            para.append(line)
        }
        flush()
        return out
    }

    static func renderLines(blocks: [TranslateBlock], translations: [String], mode: String) -> [String] {
        var lines: [String] = []
        var t = 0
        for block in blocks {
            if block.kind == .keep {
                if block.raw.isEmpty {
                    if lines.last != "" { lines.append("") }
                } else {
                    lines.append(block.raw)
                }
                continue
            }
            let translated = t < translations.count ? translations[t] : block.body
            t += 1
            let rebuilt = rebuild(prefix: block.prefix, body: translated)
            if mode == "replace" {
                if rebuilt.contains("\n") {
                    lines.append(contentsOf: rebuilt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
                } else {
                    lines.append(rebuilt)
                }
            } else {
                lines.append(block.raw)
                lines.append("")
                if rebuilt.contains("\n") {
                    for piece in rebuilt.split(separator: "\n", omittingEmptySubsequences: false) {
                        lines.append(marker + String(piece))
                    }
                } else {
                    lines.append(marker + rebuilt)
                }
            }
        }
        while lines.last == "" { lines.removeLast() }
        return lines
    }

    static func render(blocks: [TranslateBlock], translations: [String], mode: String) -> String {
        renderLines(blocks: blocks, translations: translations, mode: mode).joined(separator: "\n")
    }

    static func translate(
        markdown: String,
        from: String,
        to: String,
        mode: String,
        engine: String,
        ask: AskService.Settings?,
        googleKey: String
    ) async throws -> String {
        let pieces = blocks(from: markdown)
        let payloads = pieces.filter { $0.kind == .text }.map(\.body)
        guard !payloads.isEmpty else { return markdown }
        let translated: [String]
        if engine == "google" {
            translated = try await googleTranslate(payloads, from: from, to: to, key: googleKey)
        } else if let ask {
            translated = try await askTranslate(payloads, from: from, to: to, settings: ask)
        } else {
            throw YourMarkError.invalidInput("Add an Ask key or a Google Translate key in Settings.")
        }
        return render(blocks: pieces, translations: translated, mode: mode)
    }

    static func testGoogleKey(_ key: String) async -> AskService.KeyTest {
        let trimmed = AskService.normalizeKey(key)
        guard !trimmed.isEmpty else {
            return AskService.KeyTest(passed: false, message: "Paste a Google Translate API key first.")
        }
        do {
            let out = try await googleTranslate(["OK"], from: "en", to: "es", key: trimmed)
            let shown = out.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return AskService.KeyTest(
                passed: true,
                message: "Key test passed. Google Translate answered “\(shown.isEmpty ? "OK" : shown)”."
            )
        } catch {
            return AskService.KeyTest(
                passed: false,
                message: "Key test failed. \(error.localizedDescription)"
            )
        }
    }

    private static func makeBlock(_ raw: String) -> TranslateBlock {
        if let heading = headingParts(raw) {
            return TranslateBlock(kind: .text, raw: raw, prefix: heading.prefix, body: heading.body)
        }
        return TranslateBlock(kind: .text, raw: raw, prefix: "", body: raw)
    }

    private static func rebuild(prefix: String, body: String) -> String {
        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.isEmpty { return clean }
        return prefix + clean
    }

    private static func headingParts(_ line: String) -> (prefix: String, body: String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("#") else { return nil }
        var n = 0
        var i = t.startIndex
        while i < t.endIndex, t[i] == "#", n < 6 {
            n += 1
            i = t.index(after: i)
        }
        guard n > 0, i < t.endIndex, t[i].isWhitespace else { return nil }
        let body = t[t.index(after: i)...].trimmingCharacters(in: .whitespaces)
        return (String(repeating: "#", count: n) + " ", body)
    }

    private static func isHeading(_ line: String) -> Bool {
        headingParts(line) != nil
    }

    private static func shouldKeep(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("<!--") { return true }
        if t.contains("](figures/") || t.contains("](./figures/") { return true }
        if t.hasPrefix("![") { return true }
        if t.hasPrefix("|") { return true }
        if t.hasPrefix("---") || t.hasPrefix("***") { return true }
        return false
    }

    private static func googleTranslate(_ texts: [String], from: String, to: String, key: String) async throws -> [String] {
        var out: [String] = []
        out.reserveCapacity(texts.count)
        var i = 0
        while i < texts.count {
            var batch: [String] = []
            var chars = 0
            while i < texts.count, batch.count < 32, chars + texts[i].count < 4500 {
                batch.append(texts[i])
                chars += texts[i].count
                i += 1
            }
            if batch.isEmpty {
                batch.append(texts[i])
                i += 1
            }
            out.append(contentsOf: try await googleBatch(batch, from: from, to: to, key: key))
        }
        return out
    }

    private static func googleBatch(_ texts: [String], from: String, to: String, key: String) async throws -> [String] {
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        guard let url = URL(string: "https://translation.googleapis.com/language/translate/v2?key=\(encodedKey)") else {
            throw YourMarkError.invalidInput("Google Translate URL is not valid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        var payload: [String: Any] = [
            "q": texts,
            "target": to,
            "format": "text",
        ]
        if from != "auto", !from.isEmpty {
            payload["source"] = from
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if !(200...299).contains(code) {
            let err = (json?["error"] as? [String: Any])?["message"] as? String
            throw YourMarkError.processFailed(err ?? "Google Translate failed (\(code)).")
        }
        let list = ((json?["data"] as? [String: Any])?["translations"] as? [[String: Any]]) ?? []
        let translated = list.map { $0["translatedText"] as? String ?? "" }
        if translated.count != texts.count {
            throw YourMarkError.processFailed("Google Translate returned a different number of paragraphs.")
        }
        return translated
    }

    private static func askTranslate(_ texts: [String], from: String, to: String, settings: AskService.Settings) async throws -> [String] {
        let key = AskService.normalizeKey(settings.apiKey)
        if key.isEmpty {
            throw YourMarkError.invalidInput("Add an Ask key in Settings, or switch Translate to Google.")
        }
        let target = TranslateLang.label(for: to)
        let source = from == "auto" ? "the language of the text" : TranslateLang.label(for: from)
        var out: [String] = []
        var i = 0
        while i < texts.count {
            let end = min(i + 5, texts.count)
            let batch = Array(texts[i..<end])
            out.append(contentsOf: try await askBatch(batch, source: source, target: target, settings: settings, key: key))
            i = end
        }
        return out
    }

    private static func askBatch(
        _ texts: [String],
        source: String,
        target: String,
        settings: AskService.Settings,
        key: String
    ) async throws -> [String] {
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
        let numbered = texts.enumerated().map { "<<<\($0.offset + 1)>>>\n\($0.element)" }.joined(separator: "\n\n")
        let body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 3500,
            "temperature": 0.1,
            "messages": [
                [
                    "role": "system",
                    "content": "Translate Markdown from \(source) to \(target). Keep # headings, **bold**, lists, and links. Do not translate file paths or figure links. Do not add commentary. Return one block per input, each starting with the same <<<n>>> tag.",
                ],
                [
                    "role": "user",
                    "content": numbered,
                ],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let auth = AskService.friendlyAuthError(code: code, body: data, key: key, provider: settings.provider) {
            throw YourMarkError.processFailed(auth)
        }
        guard (200...299).contains(code) else {
            throw YourMarkError.processFailed(
                AskService.friendlyHTTPError(code: code, body: data, model: settings.model, provider: settings.provider)
            )
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        let parsed = parseNumbered(text, count: texts.count)
        if parsed.count != texts.count {
            throw YourMarkError.processFailed("The model did not return every paragraph. Try a shorter chapter.")
        }
        return parsed
    }

    private static func parseNumbered(_ text: String, count: Int) -> [String] {
        var map: [Int: String] = [:]
        let parts = text.components(separatedBy: "<<<")
        for part in parts {
            guard let close = part.firstIndex(of: ">") else { continue }
            let tag = String(part[part.startIndex..<close])
                .trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
            guard let n = Int(tag), n >= 1, n <= count else { continue }
            var body = String(part[part.index(after: close)...])
            if body.hasPrefix(">>") { body = String(body.dropFirst(2)) }
            else if body.hasPrefix(">") { body = String(body.dropFirst()) }
            map[n] = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (1...count).compactMap { map[$0] }
    }
}
