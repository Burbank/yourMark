import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// MarkItDown/pdfminer keeps words, not pictures. One pass after convert:
/// pull embedded images, and rasterize only pages that actually look like figures.
enum PdfFigures {
    static let folderSuffix = "-figures"

    /// Returns how many picture files were written. 0 = nothing to add.
    @discardableResult
    static func embed(
        markdownURL: URL,
        sourcePDF: URL,
        onStatus: @escaping @Sendable (String) -> Void
    ) async -> Int {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let n = run(markdownURL: markdownURL, sourcePDF: sourcePDF, onStatus: onStatus)
                cont.resume(returning: n)
            }
        }
    }

    private static func run(
        markdownURL: URL,
        sourcePDF: URL,
        onStatus: @escaping @Sendable (String) -> Void
    ) -> Int {
        guard sourcePDF.pathExtension.lowercased() == "pdf" else { return 0 }
        guard let existing = try? String(contentsOf: markdownURL, encoding: .utf8) else { return 0 }
        if existing.contains("data:image/") || existing.contains(folderSuffix + "/") {
            return 0
        }
        guard let cgDoc = CGPDFDocument(sourcePDF as CFURL), cgDoc.numberOfPages > 0 else { return 0 }

        onStatus("Looking for pictures in the PDF…")

        let stem = markdownURL.deletingPathExtension().lastPathComponent
        let folderName = stem + folderSuffix
        let figDir = markdownURL.deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: figDir, withIntermediateDirectories: true)

        let pdfDoc = PDFDocument(url: sourcePDF)
        let pageCount = cgDoc.numberOfPages
        var pageFiles: [Int: [String]] = [:]
        var fingerprintCount: [Int: Int] = [:]
        var rasters = 0
        let rasterCap = 160

        for i in 1...pageCount {
            guard let page = cgDoc.page(at: i) else { continue }
            let sink = XSink()
            if let dict = page.dictionary {
                var resources: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources {
                    sink.walk(resources: resources, depth: 0)
                }
            }

            var files: [String] = []
            for (n, img) in sink.images.enumerated() {
                let seen = fingerprintCount[img.fp, default: 0]
                if seen >= 6 { continue }
                fingerprintCount[img.fp] = seen + 1
                let name = String(format: "p%03d-%d.%@", i, n + 1, img.ext)
                do {
                    try img.data.write(to: figDir.appendingPathComponent(name), options: .atomic)
                    files.append(name)
                } catch { continue }
            }

            if files.isEmpty {
                let chars = (pdfDoc?.page(at: i - 1)?.string ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .count
                let bytes = contentLength(page)
                let illustrated =
                    (sink.hasLargeImage && sink.images.isEmpty)
                    || (sink.hasForm && chars < 1500 && bytes > 3000)
                    || (chars < 800 && bytes > 4000)
                if illustrated, rasters < rasterCap,
                   let name = rasterize(page, index: i, into: figDir) {
                    files.append(name)
                    rasters += 1
                }
            }

            if !files.isEmpty {
                pageFiles[i - 1] = files
                if pageFiles.count % 8 == 0 {
                    onStatus("Saving pictures (\(pageFiles.count) so far)…")
                }
            }
        }

        let total = pageFiles.values.reduce(0) { $0 + $1.count }
        if total == 0 {
            try? FileManager.default.removeItem(at: figDir)
            return 0
        }

        onStatus("Placing \(total) pictures in the Markdown…")
        let next = splice(text: existing, pageFiles: pageFiles, folder: folderName, pdfDoc: pdfDoc)
        try? next.write(to: markdownURL, atomically: true, encoding: .utf8)
        return total
    }

    private static func splice(
        text: String,
        pageFiles: [Int: [String]],
        folder: String,
        pdfDoc: PDFDocument?
    ) -> String {
        func block(_ files: [String]) -> String {
            files.map { "![](\(folder)/\($0))" }.joined(separator: "\n\n")
        }

        if text.contains("\u{0c}") {
            var parts = text.components(separatedBy: "\u{0c}")
            let pageCount = pdfDoc?.pageCount ?? (pageFiles.keys.max() ?? 0) + 1
            let leadingBlank = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            for (page, files) in pageFiles.sorted(by: { $0.key < $1.key }) {
                var idx = page
                if parts.count == pageCount + 1, leadingBlank { idx = page + 1 }
                guard parts.indices.contains(idx) else { continue }
                let trimmed = parts[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                parts[idx] = trimmed + "\n\n" + block(files) + "\n"
            }
            return parts.joined(separator: "\u{0c}")
        }

        var result = text
        var unmatched: [(Int, [String])] = []
        for (page, files) in pageFiles.sorted(by: { $0.key < $1.key }) {
            let sample = distinctive(pdfDoc?.page(at: page)?.string)
            if let sample, let range = result.range(of: sample) {
                var insertAt = range.upperBound
                if let nl = result[insertAt...].firstIndex(of: "\n") {
                    insertAt = result.index(after: nl)
                }
                result.replaceSubrange(insertAt..<insertAt, with: "\n" + block(files) + "\n")
            } else {
                unmatched.append((page, files))
            }
        }
        if !unmatched.isEmpty {
            var extra = "\n\n## Figures\n\nPictures taken from the PDF, in page order.\n\n"
            for (page, files) in unmatched {
                extra += "### Page \(page + 1)\n\n" + block(files) + "\n\n"
            }
            result += extra
        }
        return result
    }

    private static func distinctive(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return raw
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.count >= 28 && $0.count <= 160 }
    }

    private static func contentLength(_ page: CGPDFPage) -> Int {
        guard let dict = page.dictionary else { return 0 }
        var stream: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(dict, "Contents", &stream), let stream {
            return streamByteCount(stream)
        }
        var array: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dict, "Contents", &array), let array {
            var total = 0
            let n = CGPDFArrayGetCount(array)
            for i in 0..<n {
                var s: CGPDFStreamRef?
                if CGPDFArrayGetStream(array, i, &s), let s {
                    total += streamByteCount(s)
                }
            }
            return total
        }
        return 0
    }

    private static func streamByteCount(_ stream: CGPDFStreamRef) -> Int {
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) else { return 0 }
        return CFDataGetLength(data)
    }

    private static func rasterize(_ page: CGPDFPage, index: Int, into dir: URL) -> String? {
        let box = page.getBoxRect(.mediaBox)
        let long = max(box.width, box.height)
        let scale = min(1.5, 1400 / max(long, 1))
        let width = max(1, Int((box.width * scale).rounded()))
        let height = max(1, Int((box.height * scale).rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage(), let data = jpeg(image) else { return nil }
        let name = String(format: "page-%03d.jpg", index)
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    fileprivate static func jpeg(_ image: CGImage, quality: CGFloat = 0.72) -> Data? {
        let destData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            destData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            dest,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return nil }
        return destData as Data
    }
}

private struct ExtractedImage {
    var data: Data
    var ext: String
    var fp: Int
}

private final class XSink {
    var images: [ExtractedImage] = []
    var hasForm = false
    var hasLargeImage = false
    private var walkDepth = 0

    func walk(resources: CGPDFDictionaryRef, depth: Int) {
        guard depth < 4 else { return }
        walkDepth = depth
        var xobject: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobject), let xobject else { return }
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        CGPDFDictionaryApplyFunction(xobject, { _, object, info in
            guard let info else { return }
            Unmanaged<XSink>.fromOpaque(info).takeUnretainedValue().consume(object)
        }, ptr)
    }

    private func consume(_ object: CGPDFObjectRef) {
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream else { return }
        guard let sdict = CGPDFStreamGetDictionary(stream) else { return }
        var subtype: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(sdict, "Subtype", &subtype), let subtype else { return }
        let kind = String(cString: subtype)
        if kind == "Form" {
            hasForm = true
            var inner: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(sdict, "Resources", &inner), let inner {
                walk(resources: inner, depth: walkDepth + 1)
            }
            return
        }
        guard kind == "Image" else { return }
        var width: CGPDFInteger = 0
        var height: CGPDFInteger = 0
        CGPDFDictionaryGetInteger(sdict, "Width", &width)
        CGPDFDictionaryGetInteger(sdict, "Height", &height)
        if width < 80 || height < 80 { return }
        hasLargeImage = true

        var format = CGPDFDataFormat.raw
        guard let cfData = CGPDFStreamCopyData(stream, &format) else { return }
        let data = cfData as Data
        guard data.count > 80 else { return }

        switch format {
        case .jpegEncoded:
            images.append(ExtractedImage(data: data, ext: "jpg", fp: fingerprint(data)))
        default:
            // JPEG2000 Swift case name differs by SDK; 2 is kCGPDFDataFormatJPEG2000Encoded.
            if format.rawValue == 2 {
                images.append(ExtractedImage(data: data, ext: "jp2", fp: fingerprint(data)))
            } else if let jpeg = rawBitmapJPEG(data: data, width: Int(width), height: Int(height), dict: sdict) {
                images.append(ExtractedImage(data: jpeg, ext: "jpg", fp: fingerprint(jpeg)))
            }
        }
    }
}

private func fingerprint(_ data: Data) -> Int {
    var h = data.count &* 16_777_619
    let n = min(48, data.count)
    data.withUnsafeBytes { buf in
        let bytes = buf.bindMemory(to: UInt8.self)
        for i in 0..<n { h = (h &* 31) &+ Int(bytes[i]) }
        if data.count > 80 {
            for i in (data.count - 16)..<data.count { h = (h &* 31) &+ Int(bytes[i]) }
        }
    }
    return h
}

private func rawBitmapJPEG(data: Data, width: Int, height: Int, dict: CGPDFDictionaryRef) -> Data? {
    var bpc: CGPDFInteger = 8
    CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bpc)
    guard bpc == 8, width > 0, height > 0 else { return nil }
    var csName: UnsafePointer<CChar>?
    var components = 3
    if CGPDFDictionaryGetName(dict, "ColorSpace", &csName), let csName {
        switch String(cString: csName) {
        case "DeviceGray": components = 1
        case "DeviceRGB": components = 3
        default: return nil
        }
    }
    let expected = width * height * components
    guard data.count >= expected else { return nil }
    let space: CGColorSpace = components == 1
        ? CGColorSpaceCreateDeviceGray()
        : CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * components,
            bytesPerRow: width * components,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
          )
    else { return nil }
    return PdfFigures.jpeg(image)
}
