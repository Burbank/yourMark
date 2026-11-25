import CoreGraphics
import CoreText
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

    func testPipelineAutoDoesNotFragmentTokenOrAbout() async throws {
        let pdf = try makeColumnPDF()
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("layout-auto-\(UUID().uuidString)", isDirectory: true)
        let pipeline = ConvertPipeline(options: ConvertOptions(ocrEnabled: false, layoutMode: "auto"))
        let result = try await pipeline.convert(input: pdf, outputFolder: out)
        let markdown = try String(contentsOf: result.markdownURL)
        XCTAssertTrue(markdown.contains("## Page 1"))
        XCTAssertTrue(markdown.contains("TOKENIZATION"))
        XCTAssertFalse(markdown.contains("TOKENIZAT\n"))
        let contents = try XCTUnwrap(markdown.range(of: "Contents"))
        let about = try XCTUnwrap(markdown.range(of: "About Bitwise"))
        XCTAssertLessThan(contents.lowerBound, about.lowerBound)
        XCTAssertTrue(markdown.contains("> **Sidebar**"))
        XCTAssertLessThan(markdown.range(of: "> **Sidebar**")!.lowerBound, about.lowerBound)
    }

    func testPipelineDoclingKeepsDoclingMarkdown() async throws {
        let pdf = try makeColumnPDF()
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("layout-docling-\(UUID().uuidString)", isDirectory: true)
        let pipeline = ConvertPipeline(options: ConvertOptions(
            ocrEnabled: false,
            prefersDocling: true,
            layoutMode: "docling"
        ))
        let result = try await pipeline.convert(input: pdf, outputFolder: out)
        let markdown = try String(contentsOf: result.markdownURL)
        XCTAssertFalse(markdown.contains("> **Sidebar**"), "PDFKit rewrite must not replace Docling or MarkItDown")
        XCTAssertTrue(markdown.localizedCaseInsensitiveContains("tokenization"))
        XCTAssertTrue(markdown.localizedCaseInsensitiveContains("about bitwise"))
    }

    /// Two columns drawn with Core Text so PDFKit can measure line bounds.
    private func makeColumnPDF() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("columns-\(UUID().uuidString).pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        ctx.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func draw(_ text: String, _ x: CGFloat, _ y: CGFloat) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, ctx)
        }
        draw("TOKENIZATION", 72, 720)
        draw("Contents of the report", 72, 696)
        draw("About Bitwise", 360, 720)
        draw("Important information", 360, 696)
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }
}
