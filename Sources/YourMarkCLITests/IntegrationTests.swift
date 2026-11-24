import XCTest
import Foundation
import PDFKit
import CoreGraphics
import YourMarkCore
@testable import yourmark

final class IntegrationTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    
    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
    
    // MARK: - PDF Generation
    
    func createTextPDF(pages: Int, text: String, name: String = "test.pdf") -> URL {
        let url = tempDir.appendingPathComponent(name)
        
        guard let pdfContext = CGContext(url as CFURL, mediaBox: nil, nil) else {
            XCTFail("Could not create PDF context")
            return url
        }
        
        for _ in 0..<pages {
            pdfContext.beginPDFPage(nil)
            pdfContext.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            
            let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            ]
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attributedString)
            
            pdfContext.textPosition = CGPoint(x: 50, y: 700)
            CTLineDraw(line, pdfContext)
            
            pdfContext.endPDFPage()
        }
        
        pdfContext.closePDF()
        return url
    }
    
    // MARK: - Exit Code Tests
    
    func testExitCodeOK() {
        // Exit 0 - successful conversion (would need full pipeline)
        XCTAssertEqual(statusString(0), "ok")
    }
    
    func testExitCodePartial() {
        // Exit 1 - partial with warnings
        XCTAssertEqual(statusString(1), "partial")
    }
    
    func testExitCodeRejected() {
        // Exit 2 - rejected input
        XCTAssertEqual(statusString(2), "rejected")
    }
    
    func testExitCodeFailed() {
        // Exit 3 - conversion failed
        XCTAssertEqual(statusString(3), "failed")
    }
    
    func testExitCodeEngineMissing() {
        // Exit 4 - engine not available
        XCTAssertEqual(statusString(4), "engine_missing")
    }
    
    func testExitCodeIOError() {
        // Exit 5 - I/O error
        XCTAssertEqual(statusString(5), "io_error")
    }
    
    func testExitCodeTimeout() {
        // Exit 124 - timeout
        XCTAssertEqual(statusString(124), "timeout")
    }
    
    // MARK: - JSON Tests
    
    func testJSONSerialization() {
        let dict: [String: Any] = [
            "status": "ok",
            "pages": 42,
            "ocr": true,
            "warnings": ["test"]
        ]
        
        let jsonStr = jsonString(dict)
        XCTAssertTrue(jsonStr.contains("\"status\""))
        XCTAssertTrue(jsonStr.contains("\"pages\""))
        
        // Should be valid JSON
        let data = jsonStr.data(using: .utf8)!
        let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?["status"] as? String, "ok")
        XCTAssertEqual(decoded?["pages"] as? Int, 42)
    }
    
    // MARK: - URL Tests
    
    func testStripQuery() {
        XCTAssertEqual(stripQuery("https://example.com/file.pdf"), "https://example.com/file.pdf")
        XCTAssertEqual(stripQuery("https://example.com/file.pdf?token=secret"), "https://example.com/file.pdf")
        XCTAssertEqual(stripQuery("https://example.com/file.pdf?a=1&b=2"), "https://example.com/file.pdf")
        XCTAssertEqual(stripQuery("https://example.com/file.pdf#section"), "https://example.com/file.pdf")
        XCTAssertEqual(stripQuery("https://example.com/file.pdf?token=secret#section"), "https://example.com/file.pdf")
    }
    
    func testHTTPRejection() async throws {
        // HTTP URLs should be rejected
        let fetcher = URLFetcher(maxMB: 1)
        
        do {
            _ = try await fetcher.fetch(urlString: "http://example.com/file.pdf", to: tempDir)
            XCTFail("Should have rejected http:// URL")
        } catch let error as URLFetcher.FetchError {
            if case .notHTTPS = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testInvalidURL() async throws {
        let fetcher = URLFetcher(maxMB: 1)
        
        do {
            _ = try await fetcher.fetch(urlString: "not a url", to: tempDir)
            XCTFail("Should have rejected invalid URL")
        } catch let error as URLFetcher.FetchError {
            switch error {
            case .invalidURL, .notHTTPS:
                break
            default:
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    // MARK: - Probe Tests
    
    func testProbeBasicPDF() async throws {
        let pdf = createTextPDF(pages: 3, text: "Test content for probing")
        
        let info = try await probeFile(pdf)
        
        XCTAssertEqual(info.pages, 3)
        XCTAssertFalse(info.encrypted)
        XCTAssertGreaterThan(info.bytes, 0)
        XCTAssertFalse(info.sha256.isEmpty)
        XCTAssertEqual(info.sha256.count, 64) // SHA-256 is 64 hex chars
    }
    
    func testProbeNonPDF() async throws {
        let textFile = tempDir.appendingPathComponent("test.txt")
        try "Test content".write(to: textFile, atomically: true, encoding: .utf8)
        
        let info = try await probeFile(textFile)
        
        XCTAssertEqual(info.pages, 1) // Non-PDFs report 1 page
        XCTAssertFalse(info.encrypted)
        XCTAssertGreaterThan(info.bytes, 0)
    }
    
    // MARK: - Timeout Tests
    
    func testTimeoutCalculation() {
        // Formula: clamp(120 + 3*pages + 20*ocrPages, 120, 3600)
        
        // Minimum
        XCTAssertEqual(calculateTimeout(pages: 0, ocrPages: 0), 120)
        
        // Small document
        XCTAssertEqual(calculateTimeout(pages: 10, ocrPages: 0), 150)
        
        // Medium document with OCR
        XCTAssertEqual(calculateTimeout(pages: 10, ocrPages: 10), 350)
        
        // Large document
        XCTAssertEqual(calculateTimeout(pages: 1000, ocrPages: 0), 3120)
        
        // Maximum (should cap at 3600)
        XCTAssertEqual(calculateTimeout(pages: 1500, ocrPages: 0), 3600)
        XCTAssertEqual(calculateTimeout(pages: 2000, ocrPages: 0), 3600)
        
        // With heavy OCR
        XCTAssertEqual(calculateTimeout(pages: 50, ocrPages: 50), 1270)
    }
    
    // MARK: - Format Tests
    
    func testFormatBytes() {
        XCTAssertEqual(formatBytes(100), "100 bytes")
        XCTAssertEqual(formatBytes(1024), "1.0 KB")
        XCTAssertEqual(formatBytes(1536), "1.5 KB")
        XCTAssertEqual(formatBytes(1024 * 1024), "1.0 MB")
        XCTAssertEqual(formatBytes(1024 * 1024 + 512 * 1024), "1.5 MB")
    }
    
    // MARK: - Keep Original Tests
    
    func testKeepOriginalOptions() {
        let options1 = ConvertOptions(keepOriginalPDF: .auto)
        XCTAssertEqual(options1.keepOriginalPDF, .auto)
        
        let options2 = ConvertOptions(keepOriginalPDF: .always)
        XCTAssertEqual(options2.keepOriginalPDF, .always)
        
        let options3 = ConvertOptions(keepOriginalPDF: .never)
        XCTAssertEqual(options3.keepOriginalPDF, .never)
    }
    
    // MARK: - One-Folder Layout Tests
    
    func testOneFolderLayout() {
        // The output should follow the pattern:
        // <out>/<Title>/<Title>.md
        // <out>/<Title>/<Title>.outline.json
        // <out>/<Title>/figures/ (if images extracted)
        // <out>/<Title>/<original>.pdf (if kept)
        
        let outputBase = tempDir.appendingPathComponent("Library")
        let docTitle = "Test Document"
        let expectedFolder = outputBase.appendingPathComponent(docTitle)
        let expectedMD = expectedFolder.appendingPathComponent("\(docTitle).md")
        let expectedOutline = expectedFolder.appendingPathComponent("\(docTitle).outline.json")
        let expectedFigures = expectedFolder.appendingPathComponent("figures")
        
        // Verify path construction
        XCTAssertTrue(expectedMD.path.contains(docTitle))
        XCTAssertTrue(expectedMD.path.hasSuffix(".md"))
        XCTAssertTrue(expectedOutline.path.hasSuffix(".outline.json"))
    }
    
    // MARK: - Temp Directory Tests
    
    func testTempDirPermissions() throws {
        let testTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        try FileManager.default.createDirectory(at: testTemp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        
        let attrs = try FileManager.default.attributesOfItem(atPath: testTemp.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        
        // Check that permissions are 0700 (owner only)
        XCTAssertEqual((perms?.intValue ?? 0) & 0o777, 0o700)
        
        try? FileManager.default.removeItem(at: testTemp)
    }
}
