import AppKit
import XCTest
@testable import YourMarkCore

final class CoreTests: XCTestCase {
    func testConvertJobCreation() {
        let job = ConvertJob(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/test.pdf"),
            outputURL: nil,
            status: .queued,
            detail: "Test"
        )
        
        XCTAssertEqual(job.status, .queued)
        XCTAssertEqual(job.detail, "Test")
    }
    
    func testConvertOptionsDefaults() {
        let options = ConvertOptions()
        
        XCTAssertTrue(options.ocrEnabled)
        XCTAssertEqual(options.ocrLanguage, "auto")
        XCTAssertFalse(options.extractImages)
        XCTAssertTrue(options.stripChrome)
        XCTAssertEqual(options.keepOriginalPDF, .auto)
    }
    
    func testYourMarkErrorDescriptions() {
        let error1 = YourMarkError.invalidInput("test message")
        XCTAssertEqual(error1.localizedDescription, "test message")
        
        let error2 = YourMarkError.processFailed("process error")
        XCTAssertEqual(error2.localizedDescription, "process error")
        
        let error3 = YourMarkError.outputMissing("/path/to/file")
        XCTAssertTrue(error3.localizedDescription.contains("/path/to/file"))
    }
    
    func testBookRecordEmpty() {
        let record = BookRecord()
        XCTAssertTrue(record.isEmpty)
        XCTAssertEqual(record.title, "")
        XCTAssertTrue(record.authors.isEmpty)
    }
    
    func testBookRecordFillEmpty() {
        var record1 = BookRecord()
        record1.title = "Title 1"
        
        var record2 = BookRecord()
        record2.title = "Title 2"
        record2.authors = ["Author"]
        
        record1.fillEmpty(from: record2)
        
        XCTAssertEqual(record1.title, "Title 1")  // Not overwritten
        XCTAssertEqual(record1.authors, ["Author"])  // Filled
    }
    
    func testPipelineTimeoutFires() async {
        do {
            _ = try await ConvertPipeline.withTimeout(seconds: 0) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
            XCTFail("Expected timeout")
        } catch YourMarkError.timedOut {
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testOCRLanguageReachesVision() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = dir.appendingPathComponent("note.png")
        let image = NSImage(size: NSSize(width: 40, height: 20))
        image.lockFocus()
        NSColor.white.set()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 40, height: 20))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Could not make a PNG")
            return
        }
        try data.write(to: png)
        OCRVisionMetrics.reset()
        _ = try await NativeConvert.convert(
            input: png,
            output: dir.appendingPathComponent("out.md"),
            ocr: true,
            ocrLanguage: "nld"
        ) { _ in }
        XCTAssertEqual(OCRVisionMetrics.lastLanguages, ["nl-NL", "nl-BE"])
    }

    func testDistributionChannel() {
        #if APPSTORE
        XCTAssertTrue(Distribution.isAppStore)
        XCTAssertEqual(Distribution.channel, .mas)
        #else
        // In tests, we're not in App Store mode
        #endif
    }
}
