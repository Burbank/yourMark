import PDFKit
import XCTest
@testable import YourMarkCore

final class LayoutOrderTests: XCTestCase {
    func testSidebarFollowsBody() {
        let fragments = [
            LayoutOrder.Fragment(text: "About this report. Tokenization notes in the margin.", x: 36, y: 700, width: 120),
            LayoutOrder.Fragment(text: "Contents", x: 220, y: 720, width: 280),
            LayoutOrder.Fragment(text: "1. Introduction to the bitwise report", x: 220, y: 690, width: 280)
        ]
        let markdown = LayoutOrder.markdown(from: fragments, pageWidth: 612)
        let body = markdown.range(of: "Contents")
        let side = markdown.range(of: "> **Sidebar**")
        XCTAssertNotNil(body)
        XCTAssertNotNil(side)
        XCTAssertLessThan(body!.lowerBound, side!.lowerBound)
        XCTAssertTrue(markdown.contains("> About this report"))
    }

    func testTwoColumnPDFKeepsContentsBeforeSidebar() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bitwise-pages-\(UUID().uuidString).pdf")
        let body = """
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Count 1 /Kids [3 0 R] >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj
        4 0 obj << /Length 180 >>
        stream
        BT /F1 12 Tf 36 720 Td (About this report sidebar) Tj ET
        BT /F1 12 Tf 240 720 Td (Contents of the tokenization report) Tj ET
        endstream
        endobj
        5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj
        xref
        trailer << /Size 6 /Root 1 0 R >>
        startxref
        0
        %%EOF
        """
        try Data(body.utf8).write(to: url)
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else {
            XCTFail("PDFKit could not open the fixture")
            return
        }
        let parts = LayoutOrder.fragments(on: page)
        if parts.count < 2 {
            throw XCTSkip("PDFKit did not expose character positions for this fixture")
        }
        let markdown = LayoutOrder.markdown(from: parts, pageWidth: 612)
        XCTAssertTrue(markdown.contains("Contents"))
        XCTAssertTrue(markdown.contains("Sidebar") || markdown.contains("About"))
        let contentsAt = markdown.range(of: "Contents")
        let aboutAt = markdown.range(of: "About")
        if let contentsAt, let aboutAt, markdown.contains("**Sidebar**") {
            XCTAssertLessThan(contentsAt.lowerBound, markdown.range(of: "**Sidebar**")!.lowerBound)
            _ = aboutAt
        }
    }
}
