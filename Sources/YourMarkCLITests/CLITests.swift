import XCTest
import YourMarkCore

final class CLITests: XCTestCase {
    func testCalculateTimeout() {
        XCTAssertEqual(calculateTimeout(pages: 10, ocrPages: 0), 150)
        XCTAssertEqual(calculateTimeout(pages: 10, ocrPages: 10), 350)
        XCTAssertEqual(calculateTimeout(pages: 1000, ocrPages: 0), 3120)
        XCTAssertEqual(calculateTimeout(pages: 1500, ocrPages: 0), 3600)
        XCTAssertEqual(calculateTimeout(pages: 1, ocrPages: 0), 123)
        XCTAssertEqual(calculateTimeout(pages: 0, ocrPages: 0), 120)
    }
    
    func testStripQuery() {
        XCTAssertEqual(stripQuery("https://example.com/file.pdf"), "https://example.com/file.pdf")
        XCTAssertEqual(stripQuery("https://example.com/file.pdf?token=secret123"), "https://example.com/file.pdf")
        XCTAssertEqual(stripQuery("https://example.com/file.pdf?a=1&b=2#section"), "https://example.com/file.pdf")
    }
    
    func testFormatBytes() {
        XCTAssertEqual(formatBytes(100), "100 bytes")
        XCTAssertEqual(formatBytes(1024), "1.0 KB")
        XCTAssertEqual(formatBytes(1024 * 1024), "1.0 MB")
        XCTAssertEqual(formatBytes(1500 * 1024), "1.5 MB")
    }
    
    func testStatusString() {
        XCTAssertEqual(statusString(0), "ok")
        XCTAssertEqual(statusString(1), "partial")
        XCTAssertEqual(statusString(2), "rejected")
        XCTAssertEqual(statusString(3), "failed")
        XCTAssertEqual(statusString(4), "engine_missing")
        XCTAssertEqual(statusString(5), "io_error")
        XCTAssertEqual(statusString(124), "timeout")
    }
    
    func testVisionLanguageMapping() {
        XCTAssertEqual(visionRecognitionLanguages(for: "nld"), ["nl-NL", "nl-BE"])
        XCTAssertEqual(visionRecognitionLanguages(for: "eng"), ["en-US", "en-GB"])
        XCTAssertFalse(visionRecognitionLanguages(for: "auto").isEmpty)
    }
}