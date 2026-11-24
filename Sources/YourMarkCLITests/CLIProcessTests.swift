import Foundation
import PDFKit
import XCTest

#if !APPSTORE
final class CLIProcessTests: XCTestCase {
    private var temp: URL!

    override func setUp() {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let temp { try? FileManager.default.removeItem(at: temp) }
    }

    func testHelpExitsZero() throws {
        let run = try launch(["--help"])
        XCTAssertEqual(run.status, 0)
        XCTAssertTrue(run.stdout.contains("convert"))
    }

    func testConvertJSONOneFolder() throws {
        let pdf = try writeTextPDF(named: "Notes.pdf", text: "Hello from the CLI test.")
        let library = temp.appendingPathComponent("library", isDirectory: true)
        let run = try launch([
            "convert", pdf.path,
            "--out", library.path,
            "--ocr", "off",
            "--images", "off",
            "--keep-original", "never",
            "--json"
        ])
        XCTAssertEqual(run.status, 0, run.stdout + "\n" + run.stderr)
        let json = try jsonObject(run.stdout)
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["pages"] as? Int, 1)
        XCTAssertNotNil(json["sha256"] as? String)
        let md = try XCTUnwrap(json["md_path"] as? String)
        let folder = try XCTUnwrap(json["folder"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: md))
        XCTAssertTrue(folder.hasSuffix("/Notes"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent("Notes.pdf")))
    }

    func testKeepOriginalAlways() throws {
        let pdf = try writeTextPDF(named: "Keep.pdf", text: "Keep the original.")
        let library = temp.appendingPathComponent("library", isDirectory: true)
        let run = try launch([
            "convert", pdf.path,
            "--out", library.path,
            "--ocr", "off",
            "--keep-original", "always",
            "--json"
        ])
        XCTAssertEqual(run.status, 0, run.stdout + "\n" + run.stderr)
        let json = try jsonObject(run.stdout)
        XCTAssertEqual(json["original_kept"] as? Bool, true)
        let folder = try XCTUnwrap(json["folder"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent("Keep.pdf")))
    }

    func testMissingFileExits2() throws {
        let run = try launch([
            "convert", temp.appendingPathComponent("missing.pdf").path,
            "--out", temp.path
        ])
        XCTAssertEqual(run.status, 2)
    }

    func testUnwritableOutputExits5() throws {
        let pdf = try writeTextPDF(named: "IO.pdf", text: "IO failure.")
        let blocker = temp.appendingPathComponent("not-a-dir")
        try Data("x".utf8).write(to: blocker)
        let run = try launch([
            "convert", pdf.path,
            "--out", blocker.appendingPathComponent("nested").path
        ])
        XCTAssertEqual(run.status, 5, run.stderr)
    }

    func testTimeoutExits124() throws {
        let pdf = try writeTextPDF(named: "Slow.pdf", text: "Should time out immediately.")
        let run = try launch([
            "convert", pdf.path,
            "--out", temp.appendingPathComponent("out", isDirectory: true).path,
            "--ocr", "off",
            "--timeout", "0"
        ])
        XCTAssertEqual(run.status, 124, run.stderr)
    }

    func testEncryptedProbe() throws {
        let pdf = temp.appendingPathComponent("secret.pdf")
        let doc = PDFDocument()
        let page = PDFPage()
        doc.insert(page, at: 0)
        doc.write(to: pdf, withOptions: [
            PDFDocumentWriteOption.userPasswordOption: "secret",
            PDFDocumentWriteOption.ownerPasswordOption: "secret"
        ])
        let run = try launch(["probe", pdf.path, "--json"])
        XCTAssertEqual(run.status, 0, run.stdout + "\n" + run.stderr)
        let json = try jsonObject(run.stdout)
        XCTAssertEqual(json["encrypted"] as? Bool, true)
        let convert = try launch(["convert", pdf.path, "--out", temp.path, "--ocr", "off"])
        XCTAssertEqual(convert.status, 2, convert.stderr)
    }

    private func writeTextPDF(named name: String, text: String) throws -> URL {
        let sentence = String(repeating: text + " ", count: 12)
        let escaped = sentence
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        let stream = "BT /F1 12 Tf 48 720 Td (\(escaped)) Tj ET\n"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)endstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
        ]
        var body = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(body.utf8.count)
            body += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xrefAt = body.utf8.count
        body += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            body += String(format: "%010d 00000 n \n", offset)
        }
        body += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefAt)\n%%EOF\n"
        let url = temp.appendingPathComponent(name)
        try Data(body.utf8).write(to: url)
        return url
    }

    private func launch(_ args: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let binary = try cliBinary()
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        // GitHub's `uv tool install markitdown[...]` can resolve an unrelated
        // package whose CLI rejects the script's flags. Exercise the native path.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    private func cliBinary() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let names = ["yourmark-cli"]
        let dirs = [
            root.appendingPathComponent(".build/debug"),
            root.appendingPathComponent(".build/arm64-apple-macosx/debug"),
            root.appendingPathComponent(".build/out/Products/Debug")
        ]
        for dir in dirs {
            for name in names {
                let url = dir.appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
        }
        throw XCTSkip("yourmark-cli has not been built")
    }

    private func jsonObject(_ text: String) throws -> [String: Any] {
        let data = Data(text.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
#endif
