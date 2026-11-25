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

    func testMeasuredPDFKeepsWordsWholeAndSidebarAfterBody() throws {
        let url = try makeColumnPDF()
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else {
            XCTFail("PDFKit could not open the fixture")
            return
        }
        let parts = LayoutOrder.fragments(on: page)
        XCTAssertGreaterThanOrEqual(parts.count, 2)
        XCTAssertTrue(parts.contains { $0.text.contains("TOKENIZATION") })
        XCTAssertFalse(parts.contains { $0.text == "TOKENIZAT" || $0.text == "ON" })
        let markdown = LayoutOrder.markdown(from: parts, pageWidth: 612)
        XCTAssertTrue(markdown.contains("TOKENIZATION"))
        XCTAssertFalse(markdown.contains("TOKENIZAT\n"))
        let body = markdown.range(of: "TOKENIZATION")
        let side = markdown.range(of: "> **Sidebar**")
        let about = markdown.range(of: "> About Bitwise")
        XCTAssertNotNil(body)
        XCTAssertNotNil(side)
        XCTAssertNotNil(about)
        XCTAssertLessThan(body!.lowerBound, side!.lowerBound)
        XCTAssertLessThan(side!.lowerBound, about!.lowerBound)
    }

    func testApplyKeepsPageHeadings() throws {
        let pdf = try makeColumnPDF()
        let markdown = FileManager.default.temporaryDirectory
            .appendingPathComponent("layout-\(UUID().uuidString).md")
        try "DOCLING TOKENIZATION\n".write(to: markdown, atomically: true, encoding: .utf8)
        XCTAssertTrue(LayoutOrder.apply(to: markdown, pdf: pdf))
        let text = try String(contentsOf: markdown)
        XCTAssertTrue(text.contains("## Page 1"))
        XCTAssertTrue(text.contains("TOKENIZATION"))
        XCTAssertTrue(text.contains("About Bitwise"))
        XCTAssertFalse(text.contains("TOKENIZAT\n"))
    }

    func testDoclingMarkdownIsNotRewritten() throws {
        let pdf = try makeColumnPDF()
        let markdown = FileManager.default.temporaryDirectory
            .appendingPathComponent("docling-\(UUID().uuidString).md")
        let original = "DOCLING TOKENIZATION\n\nAbout Bitwise\n"
        try original.write(to: markdown, atomically: true, encoding: .utf8)
        XCTAssertFalse(LayoutOrder.apply(to: markdown, pdf: pdf, keepExisting: true))
        XCTAssertEqual(try String(contentsOf: markdown), original)
    }

    private func makeColumnPDF() throws -> URL {
        let stream = """
        BT
        /F1 12 Tf
        72 720 Td
        (TOKENIZATION) Tj
        0 -24 Td
        (Contents of the report) Tj
        ET
        BT
        /F1 12 Tf
        360 720 Td
        (About Bitwise) Tj
        0 -24 Td
        (Important information) Tj
        ET
        """
        let streamData = Data(stream.utf8)
        let objects: [Data] = [
            Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
            Data("<< /Type /Pages /Count 1 /Kids [3 0 R] >>".utf8),
            Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>".utf8),
            Data("<< /Length \(streamData.count) >>\nstream\n".utf8) + streamData + Data("\nendstream".utf8),
            Data("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".utf8)
        ]
        var body = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(body.count)
            body.append(Data("\(index + 1) 0 obj\n".utf8))
            body.append(object)
            body.append(Data("\nendobj\n".utf8))
        }
        let xrefAt = body.count
        var xref = "xref\n0 \(objects.count + 1)\n"
        xref += "0000000000 65535 f \n"
        for offset in offsets.dropFirst() {
            xref += String(format: "%010d 00000 n \n", offset)
        }
        body.append(Data(xref.utf8))
        body.append(Data("trailer << /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefAt)\n%%EOF\n".utf8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("columns-\(UUID().uuidString).pdf")
        try body.write(to: url)
        return url
    }
}
