import AppKit
import Foundation
import Vision

/// App Store (and fallback) converter. No Python, no downloads.
enum NativeConvert {
    static func convert(
        input: URL,
        output: URL,
        ocr: Bool,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        let ext = input.pathExtension.lowercased()
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        switch ext {
        case "pdf":
            try await OcrService.writeAppleMarkdown(from: input, to: output, ocr: ocr, onStatus: onStatus)
        case "md", "txt":
            onStatus("Copying text…")
            let text = try String(contentsOf: input, encoding: .utf8)
            try text.write(to: output, atomically: true, encoding: .utf8)
        case "html", "htm":
            onStatus("Reading HTML…")
            try stripTags(from: input).write(to: output, atomically: true, encoding: .utf8)
        case "csv":
            onStatus("Reading spreadsheet…")
            try csvToMarkdown(from: input).write(to: output, atomically: true, encoding: .utf8)
        case "json", "xml", "rtf":
            onStatus("Reading \(ext)…")
            let text = (try? String(contentsOf: input, encoding: .utf8)) ?? ""
            try text.write(to: output, atomically: true, encoding: .utf8)
        case "docx":
            onStatus("Reading Word…")
            try officeXML(input, member: "word/document.xml").write(to: output, atomically: true, encoding: .utf8)
        case "pptx":
            onStatus("Reading slides…")
            try slidesMarkdown(input).write(to: output, atomically: true, encoding: .utf8)
        case "xlsx", "xls":
            onStatus("Reading spreadsheet…")
            try officeXML(input, member: "xl/sharedStrings.xml").write(to: output, atomically: true, encoding: .utf8)
        case "jpg", "jpeg", "png", "gif", "tif", "tiff", "webp":
            onStatus("Reading the picture with Live Text…")
            try await imageMarkdown(input).write(to: output, atomically: true, encoding: .utf8)
        default:
            throw YourMarkError.invalidInput(
                "This App Store build converts PDF, Word, slides, Excel, pictures, and text. The GitHub Mac app still uses Microsoft MarkItDown for the rest."
            )
        }
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw YourMarkError.outputMissing(output.path)
        }
        return output
    }

    private static func stripTags(from url: URL) -> String {
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return raw
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func csvToMarkdown(from url: URL) -> String {
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let rows = raw.split(whereSeparator: \.isNewline).map(String.init)
        guard let first = rows.first else { return "" }
        let cells = first.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        var lines = [
            "| " + cells.joined(separator: " | ") + " |",
            "| " + cells.map { _ in "---" }.joined(separator: " | ") + " |",
        ]
        for row in rows.dropFirst() {
            let cols = row.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            lines.append("| " + cols.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func officeXML(_ zip: URL, member: String) throws -> String {
        let xml = try unzip(zip, member: member)
        return xmlToText(xml)
    }

    private static func slidesMarkdown(_ zip: URL) throws -> String {
        var parts: [String] = []
        for i in 1...80 {
            let member = "ppt/slides/slide\(i).xml"
            guard let xml = try? unzip(zip, member: member), !xml.isEmpty else {
                if i == 1 { break }
                continue
            }
            parts.append("## Slide \(i)")
            parts.append("")
            parts.append(xmlToText(xml))
            parts.append("")
        }
        if parts.isEmpty {
            throw YourMarkError.invalidInput("Could not read those slides.")
        }
        return parts.joined(separator: "\n")
    }

    private static func unzip(_ zip: URL, member: String) throws -> String {
        let result = try ProcessRun.run(
            executable: "/usr/bin/unzip",
            arguments: ["-p", zip.path, member],
            captureStdout: true,
            cancellable: true
        )
        if result.status != 0 {
            throw YourMarkError.processFailed(result.stderr.isEmpty ? "Could not open that Office file." : result.stderr)
        }
        return result.stdout
    }

    private static func xmlToText(_ xml: String) -> String {
        xml
            .replacingOccurrences(of: "</w:p>", with: "\n")
            .replacingOccurrences(of: "</a:p>", with: "\n")
            .replacingOccurrences(of: "</si>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func imageMarkdown(_ url: URL) async throws -> String {
        let text = await liveText(imageURL: url)
        let name = url.deletingPathExtension().lastPathComponent
        var parts = ["# \(name)", ""]
        if text.isEmpty {
            parts.append("*No words found in this picture.*")
        } else {
            parts.append(text)
        }
        parts.append("")
        return parts.joined(separator: "\n")
    }

    private static func liveText(imageURL: URL) async -> String {
        guard let img = NSImage(contentsOf: imageURL),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return "" }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US"]
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                let text: String
                do {
                    try handler.perform([request])
                    text = (request.results ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                } catch {
                    text = ""
                }
                cont.resume(returning: text)
            }
        }
    }
}
