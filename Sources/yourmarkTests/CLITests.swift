import XCTest
@testable import YourMarkCore

final class CLITests: XCTestCase {
    func testCalculateTimeout() {
        // Test timeout calculation formula: clamp(120 + 3*pages + 20*ocrPages, 120, 3600)
        let timeout1 = calculateTimeout(pages: 10, ocrPages: 0)
        XCTAssertEqual(timeout1, 150)  // 120 + 3*10 = 150
        
        let timeout2 = calculateTimeout(pages: 10, ocrPages: 10)
        XCTAssertEqual(timeout2, 350)  // 120 + 3*10 + 20*10 = 350
        
        let timeout3 = calculateTimeout(pages: 1000, ocrPages: 0)
        XCTAssertEqual(timeout3, 3120)  // 120 + 3*1000 = 3120
        
        let timeout4 = calculateTimeout(pages: 1500, ocrPages: 0)
        XCTAssertEqual(timeout4, 3600)  // 120 + 3*1500 = 4620, capped at 3600
        
        let timeout5 = calculateTimeout(pages: 1, ocrPages: 0)
        XCTAssertEqual(timeout5, 123)  // 120 + 3*1 = 123
        
        let timeout6 = calculateTimeout(pages: 0, ocrPages: 0)
        XCTAssertEqual(timeout6, 120)  // Minimum
    }
    
    func testStripQuery() {
        let url1 = "https://example.com/file.pdf"
        XCTAssertEqual(stripQuery(url1), "https://example.com/file.pdf")
        
        let url2 = "https://example.com/file.pdf?token=secret123"
        XCTAssertEqual(stripQuery(url2), "https://example.com/file.pdf")
        
        let url3 = "https://example.com/file.pdf?a=1&b=2#section"
        XCTAssertEqual(stripQuery(url3), "https://example.com/file.pdf")
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
}

// Helper functions from main.swift for testing
func calculateTimeout(pages: Int, ocrPages: Int) -> Int {
    let base = 120 + (3 * pages) + (20 * ocrPages)
    return min(max(base, 120), 3600)
}

func stripQuery(_ urlString: String) -> String {
    guard let url = URL(string: urlString) else { return urlString }
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.query = nil
    components?.fragment = nil
    return components?.url?.absoluteString ?? urlString
}

func formatBytes(_ bytes: Int64) -> String {
    let kb = Double(bytes) / 1024.0
    let mb = kb / 1024.0
    
    if mb >= 1.0 {
        return String(format: "%.1f MB", mb)
    } else if kb >= 1.0 {
        return String(format: "%.1f KB", kb)
    } else {
        return "\(bytes) bytes"
    }
}

func statusString(_ code: Int) -> String {
    switch code {
    case 0: return "ok"
    case 1: return "partial"
    case 2: return "rejected"
    case 3: return "failed"
    case 4: return "engine_missing"
    case 5: return "io_error"
    case 124: return "timeout"
    default: return "failed"
    }
}
