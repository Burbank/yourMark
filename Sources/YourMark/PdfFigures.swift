import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// MarkItDown/pdfminer keeps words, not pictures. After convert, pull every
/// embedded raster and, where the page is a vector diagram with no photo,
/// draw that page so the figure still appears in the Markdown.
enum PdfFigures {
    static let folderSuffix = "-figures"

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
        // Docling already inlined pictures as data URIs — do not duplicate.
        if existing.contains("data:image/") {
            let n = existing.components(separatedBy: "data:image/").count - 1
            onStatus("Pictures already in the Markdown (\(n)).")
            return n
        }
        guard let cgDoc = CGPDFDocument(sourcePDF as CFURL), cgDoc.numberOfPages > 0 else { return 0 }

        onStatus("Looking for pictures in the PDF…")

        let stem = markdownURL.deletingPathExtension().lastPathComponent
        let folderName = stem + folderSuffix
        let figDir = markdownURL.deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: figDir)
        try? FileManager.default.createDirectory(at: figDir, withIntermediateDirectories: true)

        let pdfDoc = PDFDocument(url: sourcePDF)
        let pageCount = cgDoc.numberOfPages
        var pageFiles: [Int: [String]] = [:]
        var fingerprintCount: [Int: Int] = [:]
        var extracted = 0
        var rasters = 0

        for i in 1...pageCount {
            if i == 1 || i % 8 == 0 || i == pageCount {
                onStatus("Pictures — page \(i) of \(pageCount) (\(extracted + rasters) saved)…")
            }
            guard let page = cgDoc.page(at: i) else { continue }
            let sink = XSink()
            if let dict = page.dictionary {
                var resources: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources {
                    sink.walk(resources: resources, depth: 0)
                }
            }

            var files: [String] = []
            var extractedLarge = false
            for (n, img) in sink.images.enumerated() {
                let seen = fingerprintCount[img.fp, default: 0]
                // Repeating chrome (header logos) — keep a few, skip the rest.
                if seen >= 12 { continue }
                fingerprintCount[img.fp] = seen + 1
                if img.wide >= 200 && img.tall >= 200 { extractedLarge = true }
                let name = String(format: "p%04d-%d.%@", i, n + 1, img.ext)
                do {
                    try img.data.write(to: figDir.appendingPathComponent(name), options: .atomic)
                    files.append(name)
                    extracted += 1
                } catch { continue }
            }

            let chars = (pdfDoc?.page(at: i - 1)?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .count
            let bytes = contentLength(page)
            let needsPageDraw =
                !extractedLarge
                && (
                    sink.hasUndecodedImage
                    || (sink.hasForm && chars < 2800)
                    || (sink.hasLargeImage && files.isEmpty)
                    || (chars < 500 && bytes > 2500)
                )
            if needsPageDraw, let name = rasterize(page, index: i, into: figDir) {
                files.append(name)
                rasters += 1
            }

            if !files.isEmpty {
                pageFiles[i - 1] = files
            }
        }

        let total = pageFiles.values.reduce(0) { $0 + $1.count }
        if total == 0 {
            try? FileManager.default.removeItem(at: figDir)
            onStatus("No pictures found in this PDF.")
            return 0
        }

        onStatus("Placing \(total) pictures in the Markdown…")
        let next = splice(text: existing, pageFiles: pageFiles, folder: folderName, pdfDoc: pdfDoc)
        try? next.write(to: markdownURL, atomically: true, encoding: .utf8)
        onStatus("\(total) pictures in the Markdown (\(extracted) from the PDF, \(rasters) page drawings).")
        return total
    }

    private static func splice(
        text: String,
        pageFiles: [Int: [String]],
        folder: String,
        pdfDoc: PDFDocument?
    ) -> String {
        func block(_ page: Int, _ files: [String]) -> [String] {
            files.map { "![Figure, page \(page + 1)](\(folder)/\($0))" }
        }

        var remaining = pageFiles
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        out.reserveCapacity(lines.count + remaining.count * 3)

        func takePage(_ page: Int) {
            guard let files = remaining.removeValue(forKey: page) else { return }
            out.append("")
            out.append(contentsOf: block(page, files))
            out.append("")
        }

        var usedDistinct = Set<Int>()
        for line in lines {
            out.append(line)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<!-- page "), trimmed.hasSuffix("-->") {
                let inner = trimmed
                    .dropFirst("<!-- page ".count)
                    .dropLast(3)
                    .trimmingCharacters(in: .whitespaces)
                if let n = Int(inner), n > 0 {
                    takePage(n - 1)
                    usedDistinct.insert(n - 1)
                }
            }
        }

        if !remaining.isEmpty {
            var rebuilt = out.joined(separator: "\n")
            for (page, files) in remaining.sorted(by: { $0.key < $1.key }) {
                if usedDistinct.contains(page) { continue }
                if let sample = distinctive(pdfDoc?.page(at: page)?.string),
                   let range = rebuilt.range(of: sample) {
                    var insertAt = range.upperBound
                    if let nl = rebuilt[insertAt...].firstIndex(of: "\n") {
                        insertAt = rebuilt.index(after: nl)
                    }
                    let chunk = "\n" + block(page, files).joined(separator: "\n") + "\n"
                    rebuilt.replaceSubrange(insertAt..<insertAt, with: chunk)
                    remaining.removeValue(forKey: page)
                }
            }
            out = rebuilt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }

        if !remaining.isEmpty {
            out.append("")
            out.append("## Figures")
            out.append("")
            out.append("Pictures from the PDF that could not be placed next to their page text, in page order.")
            out.append("")
            for (page, files) in remaining.sorted(by: { $0.key < $1.key }) {
                out.append("### Page \(page + 1)")
                out.append("")
                out.append(contentsOf: block(page, files))
                out.append("")
            }
        }
        return out.joined(separator: "\n")
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
        let scale = min(1.6, 1600 / max(long, 1))
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
        guard let image = ctx.makeImage(), let data = jpeg(image, quality: 0.78) else { return nil }
        let name = String(format: "page-%04d.jpg", index)
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    fileprivate static func jpeg(_ image: CGImage, quality: CGFloat = 0.78) -> Data? {
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
    var wide: Int
    var tall: Int
}

private final class XSink {
    var images: [ExtractedImage] = []
    var hasForm = false
    var hasLargeImage = false
    var hasUndecodedImage = false
    private var walkDepth = 0
    private var visits = 0
    private var seen = Set<Int>()

    func walk(resources: CGPDFDictionaryRef, depth: Int) {
        guard depth < 8 else { return }
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
        visits += 1
        if visits > 2500 { return }
        let key = Int(bitPattern: object)
        if seen.contains(key) { return }
        seen.insert(key)

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
        if width < 48 || height < 48 { return }
        hasLargeImage = true

        var format = CGPDFDataFormat.raw
        guard let cfData = CGPDFStreamCopyData(stream, &format) else { return }
        let data = cfData as Data
        guard data.count > 60 else { return }

        if format == .jpegEncoded {
            images.append(ExtractedImage(data: data, ext: "jpg", fp: fingerprint(data), wide: Int(width), tall: Int(height)))
            return
        }
        if format.rawValue == 2 { // JPEG2000
            images.append(ExtractedImage(data: data, ext: "jp2", fp: fingerprint(data), wide: Int(width), tall: Int(height)))
            return
        }
        if let jpeg = imageIOJPEG(data) ?? rawBitmapJPEG(data: data, width: Int(width), height: Int(height), dict: sdict) {
            images.append(ExtractedImage(data: jpeg, ext: "jpg", fp: fingerprint(jpeg), wide: Int(width), tall: Int(height)))
            return
        }
        hasUndecodedImage = true
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

private func imageIOJPEG(_ data: Data) -> Data? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetCount(src) > 0,
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }
    return PdfFigures.jpeg(image)
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
        case "DeviceCMYK": components = 4
        default: return nil
        }
    } else {
        return nil
    }
    let expected = width * height * components
    guard data.count >= expected else { return nil }
    let space: CGColorSpace
    switch components {
    case 1: space = CGColorSpaceCreateDeviceGray()
    case 4: space = CGColorSpaceCreateDeviceCMYK()
    default: space = CGColorSpaceCreateDeviceRGB()
    }
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
