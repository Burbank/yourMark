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
    
    func testWeakOCRUsesLowConfidenceEvenWhenTextIsLong() {
        XCTAssertTrue(isWeakOCR(charsPerPage: 4000, meanConfidence: 0.2))
        XCTAssertFalse(isWeakOCR(charsPerPage: 4000, meanConfidence: 0.9))
        XCTAssertTrue(isWeakOCR(charsPerPage: 40, meanConfidence: 0.95))
    }

    func testTesseractHOCRConfidenceIsRecorded() {
        OCRVisionMetrics.reset()
        let hocr = "<span class='ocrx_word' title='bbox 0 0 10 10; x_wconf 22'>blackletter</span>"
        OcrService.recordTesseractConfidences(in: hocr)
        XCTAssertEqual(OCRVisionMetrics.meanConfidence ?? 0, 0.22, accuracy: 0.001)
        XCTAssertTrue(isWeakOCR(charsPerPage: 4000, meanConfidence: OCRVisionMetrics.meanConfidence))
    }

    func testVisionLanguageMapping() {
        XCTAssertEqual(visionRecognitionLanguages(for: "nld"), ["nl-NL", "nl-BE"])
        XCTAssertEqual(visionRecognitionLanguages(for: "eng"), ["en-US", "en-GB"])
        XCTAssertFalse(visionRecognitionLanguages(for: "auto").isEmpty)
    }
}