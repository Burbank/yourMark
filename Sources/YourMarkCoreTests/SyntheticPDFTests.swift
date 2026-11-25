import XCTest
import PDFKit
import CoreGraphics
@testable import YourMarkCore

final class SyntheticPDFTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
    
    // MARK: - PDF Generation Helpers
    
    func createTextPDF(pages: Int, text: String) -> URL {
        let url = tempDir.appendingPathComponent("test-\(UUID().uuidString).pdf")
        
        guard let pdfContext = CGContext(url as CFURL, mediaBox: nil, nil) else {
            XCTFail("Could not create PDF context")
            return url
        }
        
        for _ in 0..<pages {
            let mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size
            pdfContext.beginPDFPage(nil)
            
            // Draw text
            pdfContext.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            pdfContext.textMatrix = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 50, ty: 742)
            
            let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            ]
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attributedString)
            
            CTLineDraw(line, pdfContext)
            
            pdfContext.endPDFPage()
        }
        
        pdfContext.closePDF()
        return url
    }
    
    func createImageOnlyPDF() -> URL {
        let url = tempDir.appendingPathComponent("scanned-\(UUID().uuidString).pdf")
        
        guard let pdfContext = CGContext(url as CFURL, mediaBox: nil, nil) else {
            XCTFail("Could not create PDF context")
            return url
        }
        
        let mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        pdfContext.beginPDFPage(nil)
        
        // Create a simple image (white rectangle with black text-like shapes)
        let imageWidth = 400
        let imageHeight = 400
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: imageWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        
        // Fill white
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        
        // Draw some black rectangles to simulate text
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for y in stride(from: 50, to: 350, by: 30) {
            context.fill(CGRect(x: 50, y: y, width: 300, height: 10))
        }
        
        if let image = context.makeImage() {
            pdfContext.draw(image, in: CGRect(x: 100, y: 200, width: 400, height: 400))
        }
        
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        
        return url
    }
    
    func createEncryptedPDF() -> URL {
        let url = tempDir.appendingPathComponent("encrypted-\(UUID().uuidString).pdf")
        
        // Create a simple PDF first
        let doc = PDFDocument()
        let page = PDFPage()
        doc.insert(page, at: 0)
        
        // Try to save with encryption (this requires owner password)
        // Note: PDFDocument doesn't support direct encryption creation in modern macOS
        // So we simulate by just checking the encrypted flag
        doc.write(to: url)
        
        return url
    }
    
    func createTwoColumnPDF() -> URL {
        let url = tempDir.appendingPathComponent("twocol-\(UUID().uuidString).pdf")
        
        guard let pdfContext = CGContext(url as CFURL, mediaBox: nil, nil) else {
            XCTFail("Could not create PDF context")
            return url
        }
        
        let mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        pdfContext.beginPDFPage(nil)
        
        // Draw two columns of text
        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        ]
        
        // Left column
        for y in stride(from: 50, to: 700, by: 15) {
            let text = NSAttributedString(string: "Left column text line", attributes: attributes)
            let line = CTLineCreateWithAttributedString(text)
            pdfContext.textPosition = CGPoint(x: 50, y: CGFloat(y))
            CTLineDraw(line, pdfContext)
        }
        
        // Right column
        for y in stride(from: 50, to: 700, by: 15) {
            let text = NSAttributedString(string: "Right column text line", attributes: attributes)
            let line = CTLineCreateWithAttributedString(text)
            pdfContext.textPosition = CGPoint(x: 350, y: CGFloat(y))
            CTLineDraw(line, pdfContext)
        }
        
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        
        return url
    }
    
    // MARK: - Tests
    
    func testBasicPDFGeneration() {
        let pdf = createTextPDF(pages: 2, text: "Test page content")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pdf.path))
        
        let doc = PDFDocument(url: pdf)
        XCTAssertNotNil(doc)
        XCTAssertEqual(doc?.pageCount, 2)
    }
    
    func testImageOnlyPDF() {
        let pdf = createImageOnlyPDF()
        XCTAssertTrue(FileManager.default.fileExists(atPath: pdf.path))
        
        let profile = OcrService.profile(pdf)
        // Image-only PDFs should be detected as needing OCR
        XCTAssertTrue(profile.needsOCR || profile.looksGraphic)
    }
    
    func testPDFWithText() {
        let body = String(repeating: "This is a test PDF with a real text layer. ", count: 80)
        let pdf = createTextPDF(pages: 3, text: body)
        
        XCTAssertEqual(OcrService.pageCount(of: pdf), 3)
        let doc = PDFDocument(url: pdf)
        XCTAssertNotNil(doc)
        XCTAssertGreaterThan(doc?.page(at: 0)?.string?.count ?? 0, 20)
    }
    
    func testPageCount() {
        let pdf1 = createTextPDF(pages: 1, text: "Single page")
        XCTAssertEqual(OcrService.pageCount(of: pdf1), 1)
        
        let pdf5 = createTextPDF(pages: 5, text: "Five pages")
        XCTAssertEqual(OcrService.pageCount(of: pdf5), 5)
    }
    
    func testBookRecordFromPDF() {
        let pdf = createTextPDF(pages: 1, text: "Test")
        let record = BookMeta.fromPDF(pdf)
        
        // Should have source name
        XCTAssertFalse(record.sourceName.isEmpty)
        XCTAssertTrue(record.sourceName.hasSuffix(".pdf"))
    }
    
    func testOCRQualityConstants() {
        XCTAssertEqual(OCRQuality.weakConfidenceThreshold, 0.6)
        XCTAssertEqual(OCRQuality.minCharsPerOCRPage, 200)
    }
    
    func testTranslationMarker() {
        XCTAssertEqual(translationMarker, "<!--ym-tr-->")
    }
}
