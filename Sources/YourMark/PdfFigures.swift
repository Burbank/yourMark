import AppKit
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
    static let folderName = "figures"

    @discardableResult
    static func embed(
        markdownURL: URL,
        sourcePDF: URL,
        stripChrome: Bool = true,
        onStatus: @escaping @Sendable (String) -> Void
    ) async -> Int {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let n = run(
                    markdownURL: markdownURL,
                    sourcePDF: sourcePDF,
                    stripChrome: stripChrome,
                    onStatus: onStatus
                )
                cont.resume(returning: n)
            }
        }
    }

    private static func run(
        markdownURL: URL,
        sourcePDF: URL,
        stripChrome: Bool,
        onStatus: @escaping @Sendable (String) -> Void
    ) -> Int {
        guard sourcePDF.pathExtension.lowercased() == "pdf" else { return 0 }
        guard let existing = try? String(contentsOf: markdownURL, encoding: .utf8) else { return 0 }
        // Docling already inlined many pictures as data URIs — do not duplicate.
        // A couple of leftover data URIs (a logo, a cover) must not skip the PDF walk.
        if existing.contains("data:image/") {
            let n = existing.components(separatedBy: "data:image/").count - 1
            if n >= 6 {
                onStatus("Pictures already in the Markdown (\(n)).")
                return n
            }
        }
        guard let cgDoc = CGPDFDocument(sourcePDF as CFURL), cgDoc.numberOfPages > 0 else { return 0 }

        onStatus("Looking for pictures in the PDF…")

        let folderName = Self.folderName
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
        let deadline = Date().addingTimeInterval(20 * 60)

        for i in 1...pageCount {
            if ProcessRun.convertWasCancelled { return extracted + rasters }
            if Date() > deadline {
                onStatus("Pictures stopped after 20 minutes — placing what was found…")
                break
            }
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

            let chars = (pdfDoc?.page(at: i - 1)?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .count
            let box = page.getBoxRect(.mediaBox)
            let pageArea = max(1, abs(box.width * box.height))
            // A scan is a photograph of the whole page. Do not save that photo
            // as a "figure" — OCR is supposed to turn it into words.
            let looksLikeScan = chars < 120 && sink.hasLargeImage
            let draws = imageCTMs(page)

            var files: [String] = []
            if !looksLikeScan {
                for img in sink.images {
                    let seen = fingerprintCount[img.fp, default: 0]
                    let logoCap = stripChrome ? 1 : 12
                    if seen >= logoCap { continue }
                    fingerprintCount[img.fp] = seen + 1
                    if stripChrome, seen >= 1 { continue }
                    let imgArea = CGFloat(max(img.wide, 1) * max(img.tall, 1))
                    if chars < 200, imgArea > pageArea * 0.35 { continue }
                    let name = String(format: "figure-%03d.%@", extracted + files.count + 1, img.ext)
                    let dest = figDir.appendingPathComponent(name)
                    let data = uprightData(img.data, ctm: draws[img.name]) ?? img.data
                    do {
                        try data.write(to: dest, options: .atomic)
                        if imgArea > pageArea * 0.25, let kit = pdfDoc?.page(at: i - 1) {
                            correctIfInverted(file: dest, page: kit)
                        }
                        files.append(name)
                        extracted += 1
                    } catch { continue }
                }
            }

            let bytes = contentLength(page)
            // Vector diagram: little text, no photo of the page, lots of drawing.
            let needsPageDraw =
                !looksLikeScan
                && files.isEmpty
                && chars < 160
                && (
                    sink.hasUndecodedImage
                    || sink.hasLargeForm
                    || (sink.hasForm && bytes > 3500)
                    || bytes > 8000
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
            files.enumerated().map { idx, name in
                let n = figureNumber(from: name)
                return "![Figure \(n) · page \(page + 1)](\(folder)/\(name))"
            }
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
        var pending: Int?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isComment = trimmed.hasPrefix("<!-- page ") && trimmed.hasSuffix("-->")
            let isHeading = PdfSidecar.headingText(line) != nil
            if let page = pending, !isHeading, !isComment, !trimmed.isEmpty {
                takePage(page)
                usedDistinct.insert(page)
                pending = nil
            }
            out.append(line)
            if isComment {
                let inner = trimmed
                    .dropFirst("<!-- page ".count)
                    .dropLast(3)
                    .trimmingCharacters(in: .whitespaces)
                if let n = Int(inner), n > 0 {
                    pending = n - 1
                }
            }
        }
        if let page = pending {
            takePage(page)
            usedDistinct.insert(page)
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

    private static func figureNumber(from name: String) -> String {
        let digits = name.filter(\.isNumber)
        if let n = Int(digits.prefix(4)), n > 0 { return "\(n)" }
        return name
    }

    /// Turn data-URI pictures into files in figures/, so the Markdown stays
    /// small for the reader and for AI. Returns how many files were written.
    @discardableResult
    static func materializeEmbedded(markdownURL: URL) async -> Int {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: materializeLocked(markdownURL))
            }
        }
    }

    private static func materializeLocked(_ markdownURL: URL) -> Int {
        guard var text = try? String(contentsOf: markdownURL, encoding: .utf8),
              text.contains("data:image") else { return 0 }
        let figDir = markdownURL.deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: figDir, withIntermediateDirectories: true)
        var n = existingFigureCount(figDir)
        var written = 0
        let pattern = #"!\[[^\]]*\]\(data:image\/([A-Za-z0-9.+-]+);base64,([A-Za-z0-9+/=\s]+)\)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return 0 }
        while written < 400 {
            let ns = text as NSString
            let full = NSRange(location: 0, length: ns.length)
            guard let match = re.firstMatch(in: text, range: full), match.numberOfRanges >= 3 else { break }
            let mime = ns.substring(with: match.range(at: 1)).lowercased()
            let b64 = ns.substring(with: match.range(at: 2))
                .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            guard let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]), data.count > 32,
                  let range = Range(match.range, in: text) else {
                if let range = Range(match.range, in: text) {
                    text.removeSubrange(range)
                } else {
                    break
                }
                continue
            }
            n += 1
            let ext = mime.contains("png") ? "png" : (mime.contains("webp") ? "webp" : "jpg")
            let name = String(format: "figure-%03d.%@", n, ext)
            try? data.write(to: figDir.appendingPathComponent(name), options: .atomic)
            text.replaceSubrange(range, with: "![Figure \(n)](\(folderName)/\(name))")
            written += 1
        }
        try? text.write(to: markdownURL, atomically: true, encoding: .utf8)
        return written
    }

    private static func existingFigureCount(_ dir: URL) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter {
            $0.hasPrefix("figure-") || $0.hasPrefix("p0") || $0.hasPrefix("page-")
        }.count
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
        let angle = Int(page.rotationAngle)
        let swapped = angle % 180 != 0
        let drawW = swapped ? box.height : box.width
        let drawH = swapped ? box.width : box.height
        let long = max(abs(drawW), abs(drawH))
        let scale = min(1.6, 1600 / max(long, 1))
        let width = max(1, Int((abs(drawW) * scale).rounded()))
        let height = max(1, Int((abs(drawH) * scale).rounded()))
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
        let dest = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.concatenate(page.getDrawingTransform(.mediaBox, rect: dest, rotate: 0, preserveAspectRatio: true))
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

    private static func imageCTMs(_ page: CGPDFPage) -> [String: CGAffineTransform] {
        let stream = CGPDFContentStreamCreateWithPage(page)
        guard let table = CGPDFOperatorTableCreate() else {
            CGPDFContentStreamRelease(stream)
            return [:]
        }
        let sink = ImageDraws()
        let info = Unmanaged.passUnretained(sink).toOpaque()
        let concat: CGPDFOperatorCallback = { scanner, raw in
            guard let raw else { return }
            let s = Unmanaged<ImageDraws>.fromOpaque(raw).takeUnretainedValue()
            var f: CGPDFReal = 0, e: CGPDFReal = 0, d: CGPDFReal = 0
            var c: CGPDFReal = 0, b: CGPDFReal = 0, a: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &f),
                  CGPDFScannerPopNumber(scanner, &e),
                  CGPDFScannerPopNumber(scanner, &d),
                  CGPDFScannerPopNumber(scanner, &c),
                  CGPDFScannerPopNumber(scanner, &b),
                  CGPDFScannerPopNumber(scanner, &a)
            else { return }
            let t = CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f)
            s.current = t.concatenating(s.current)
        }
        let save: CGPDFOperatorCallback = { _, raw in
            guard let raw else { return }
            let s = Unmanaged<ImageDraws>.fromOpaque(raw).takeUnretainedValue()
            s.stack.append(s.current)
        }
        let restore: CGPDFOperatorCallback = { _, raw in
            guard let raw else { return }
            let s = Unmanaged<ImageDraws>.fromOpaque(raw).takeUnretainedValue()
            if let last = s.stack.popLast() { s.current = last }
        }
        let draw: CGPDFOperatorCallback = { scanner, raw in
            guard let raw else { return }
            let s = Unmanaged<ImageDraws>.fromOpaque(raw).takeUnretainedValue()
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name else { return }
            s.ctmByName[String(cString: name)] = s.current
        }
        CGPDFOperatorTableSetCallback(table, "cm", concat)
        CGPDFOperatorTableSetCallback(table, "q", save)
        CGPDFOperatorTableSetCallback(table, "Q", restore)
        CGPDFOperatorTableSetCallback(table, "Do", draw)
        let scanner = CGPDFScannerCreate(stream, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFOperatorTableRelease(table)
        CGPDFContentStreamRelease(stream)
        return sink.ctmByName
    }

    private static func uprightData(_ data: Data, ctm: CGAffineTransform?) -> Data? {
        guard let ctm, let image = cgImage(from: data) else { return nil }
        let upright = applyCTM(image, ctm: ctm)
        if upright === image { return nil }
        return jpeg(upright, quality: 0.82)
    }

    private static func applyCTM(_ image: CGImage, ctm: CGAffineTransform) -> CGImage {
        let swapped = abs(ctm.b) > abs(ctm.a) && abs(ctm.c) > abs(ctm.d)
        if swapped {
            return rotate90(image, clockwise: ctm.b > 0) ?? image
        }
        let flipH = ctm.a < 0
        let flipV = ctm.d < 0
        if flipH && flipV { return rotate180(image) ?? image }
        if flipV { return flip(image, horizontal: false, vertical: true) ?? image }
        if flipH { return flip(image, horizontal: true, vertical: false) ?? image }
        return image
    }

    private static func correctIfInverted(file: URL, page: PDFPage) {
        let pageThumb = page.thumbnail(of: CGSize(width: 48, height: 48), for: .mediaBox)
        guard let pageCG = pageThumb.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let fileCG = cgImage(fromFile: file, maxPixel: 48)
        else { return }
        let d0 = lumaMAD(pageCG, fileCG)
        guard let flipped = rotate180(fileCG) else { return }
        let d1 = lumaMAD(pageCG, flipped)
        guard d1 + 8 < d0 else { return }
        guard let full = cgImage(fromFile: file, maxPixel: 2200),
              let rotated = rotate180(full),
              let data = jpeg(rotated, quality: 0.82)
        else { return }
        try? data.write(to: file, options: .atomic)
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(src) > 0
        else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    private static func cgImage(fromFile url: URL, maxPixel: CGFloat) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    private static func rotate180(_ image: CGImage) -> CGImage? {
        draw(width: image.width, height: image.height) { ctx, w, h in
            ctx.translateBy(x: w, y: h)
            ctx.rotate(by: .pi)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    private static func rotate90(_ image: CGImage, clockwise: Bool) -> CGImage? {
        draw(width: image.height, height: image.width) { ctx, w, h in
            if clockwise {
                ctx.translateBy(x: w, y: 0)
                ctx.rotate(by: .pi / 2)
            } else {
                ctx.translateBy(x: 0, y: h)
                ctx.rotate(by: -.pi / 2)
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: h, height: w))
        }
    }

    private static func flip(_ image: CGImage, horizontal: Bool, vertical: Bool) -> CGImage? {
        draw(width: image.width, height: image.height) { ctx, w, h in
            ctx.translateBy(x: horizontal ? w : 0, y: vertical ? h : 0)
            ctx.scaleBy(x: horizontal ? -1 : 1, y: vertical ? -1 : 1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    private static func draw(
        width: Int,
        height: Int,
        body: (CGContext, CGFloat, CGFloat) -> Void
    ) -> CGImage? {
        let w = max(1, width)
        let h = max(1, height)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        body(ctx, CGFloat(w), CGFloat(h))
        return ctx.makeImage()
    }

    private static func lumaMAD(_ a: CGImage, _ b: CGImage) -> Double {
        let side = 32
        guard let pa = pixels32(a, side: side), let pb = pixels32(b, side: side) else { return .greatestFiniteMagnitude }
        var sum = 0
        for i in 0..<pa.count { sum += abs(Int(pa[i]) - Int(pb[i])) }
        return Double(sum) / Double(pa.count)
    }

    private static func pixels32(_ image: CGImage, side: Int) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: side * side)
        let cs = CGColorSpaceCreateDeviceGray()
        out.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return out
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

private final class ImageDraws {
    var ctmByName: [String: CGAffineTransform] = [:]
    var current = CGAffineTransform.identity
    var stack: [CGAffineTransform] = []
}

private struct ExtractedImage {
    var name: String
    var data: Data
    var ext: String
    var fp: Int
    var wide: Int
    var tall: Int
}

private final class XSink {
    var images: [ExtractedImage] = []
    var hasForm = false
    var hasLargeForm = false
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
        CGPDFDictionaryApplyFunction(xobject, { key, object, info in
            guard let info else { return }
            Unmanaged<XSink>.fromOpaque(info).takeUnretainedValue().consume(String(cString: key), object)
        }, ptr)
    }

    private func consume(_ name: String, _ object: CGPDFObjectRef) {
        visits += 1
        if visits > 8000 { return }
        let key = withUnsafeBytes(of: object) { raw -> Int in
            raw.load(as: Int.self)
        }
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
            if formBBoxLooksLarge(sdict) { hasLargeForm = true }
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
            images.append(ExtractedImage(name: name, data: data, ext: "jpg", fp: fingerprint(data), wide: Int(width), tall: Int(height)))
            return
        }
        if format.rawValue == 2 { // JPEG2000
            images.append(ExtractedImage(name: name, data: data, ext: "jp2", fp: fingerprint(data), wide: Int(width), tall: Int(height)))
            return
        }
        if let jpeg = imageIOJPEG(data) ?? rawBitmapJPEG(data: data, width: Int(width), height: Int(height), dict: sdict) {
            images.append(ExtractedImage(name: name, data: jpeg, ext: "jpg", fp: fingerprint(jpeg), wide: Int(width), tall: Int(height)))
            return
        }
        hasUndecodedImage = true
    }

    /// Header/footer Forms are wide and short. Diagrams are both directions.
    private func formBBoxLooksLarge(_ dict: CGPDFDictionaryRef) -> Bool {
        var bbox: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, "BBox", &bbox), let bbox,
              CGPDFArrayGetCount(bbox) >= 4
        else { return true }
        var n0: CGPDFReal = 0, n1: CGPDFReal = 0, n2: CGPDFReal = 0, n3: CGPDFReal = 0
        guard CGPDFArrayGetNumber(bbox, 0, &n0),
              CGPDFArrayGetNumber(bbox, 1, &n1),
              CGPDFArrayGetNumber(bbox, 2, &n2),
              CGPDFArrayGetNumber(bbox, 3, &n3)
        else { return true }
        let w = abs(n2 - n0)
        let h = abs(n3 - n1)
        return w >= 96 && h >= 96
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
