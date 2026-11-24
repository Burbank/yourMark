import ArgumentParser
import Foundation
import YourMarkCore

#if APPSTORE
@main
struct YourMark: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "yourmark",
        abstract: "yourMark document converter",
        version: "0.6.4"
    )
    
    func run() throws {
        print("yourmark CLI is not available in the App Store build.")
        throw ExitCode(4)
    }
}
#else

@main
struct YourMark: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "yourmark",
        abstract: "yourMark document converter",
        version: "0.6.4",
        subcommands: [Convert.self, Fetch.self, Probe.self, Doctor.self],
        defaultSubcommand: Convert.self
    )
}

// MARK: - Convert Command

struct Convert: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Convert a document to Markdown",
        discussion: """
        Exit codes:
          0   - Success
          1   - Partial (warnings)
          2   - Rejected (limits/policy/encryption)
          3   - Conversion failed
          4   - Engine missing
          5   - I/O error
          124 - Timeout
        """
    )
    
    @Argument(help: "Input file path or HTTPS URL")
    var input: String
    
    @Option(name: .long, help: "Output library directory")
    var out: String
    
    @Option(name: .long, help: "OCR mode: auto|on|off (default: auto)")
    var ocr: String = "auto"
    
    @Option(name: .long, help: "Extract images: on|off (default: off)")
    var images: String = "off"
    
    @Option(name: .long, help: "Keep original PDF: auto|always|never (default: auto)")
    var keepOriginal: String = "auto"
    
    @Option(name: .long, help: "Maximum file size in MB (default: 100)")
    var maxMb: Int = 100
    
    @Option(name: .long, help: "Maximum pages (default: 1500)")
    var maxPages: Int = 1500
    
    @Option(name: .long, help: "Timeout in seconds, or 'auto' (default: auto)")
    var timeout: String = "auto"
    
    @Option(name: .long, help: "OCR language: auto|eng|nld|spa|hun (default: auto)")
    var ocrLang: String = "auto"
    
    @Flag(name: .long, help: "Output JSON instead of human-readable text")
    var json: Bool = false
    
    @Flag(name: .long, help: "Dry run - check inputs without converting")
    var dryRun: Bool = false
    
    func run() async throws {
        let startTime = Date()
        
        // Parse and validate options
        let ocrMode = try parseOCRMode(ocr)
        let extractImages = try parseBool(images, name: "images")
        let keepMode = try parseKeepMode(keepOriginal)
        
        // Determine if input is a URL
        let inputURL: URL
        var fetchedTemp: URL?
        defer {
            // Only delete temp dirs we created ourselves
            if let temp = fetchedTemp {
                try? FileManager.default.removeItem(at: temp)
            }
        }
        
        // Reject http:// URLs (insecure)
        if input.hasPrefix("http://") {
            reportError(json: json, code: 2, message: "Only HTTPS URLs are supported (not http://)")
            throw ExitCode(2)
        }
        
        if input.hasPrefix("https://") {
            // Fetch the URL first
            let fetcher = try URLFetcher(maxMB: maxMb)
            if !json {
                fputs("Downloading \(stripQuery(input))...\n", stderr)
            }
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            fetchedTemp = tempDir
            
            inputURL = try await fetcher.fetch(urlString: input, to: tempDir)
        } else {
            inputURL = URL(fileURLWithPath: input)
        }
        
        // Validate input file
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            reportError(json: json, code: 2, message: "Input file does not exist: \(inputURL.path)")
            throw ExitCode(2)
        }
        
        // Check file size
        let attrs = try FileManager.default.attributesOfItem(atPath: inputURL.path)
        let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mb = Double(bytes) / 1_000_000.0
        if mb > Double(maxMb) {
            reportError(json: json, code: 2, message: "File exceeds size limit: \(Int(mb))MB > \(maxMb)MB")
            throw ExitCode(2)
        }
        
        // Probe the file
        let probeInfo = try await probeFile(inputURL)
        
        // Check page limit
        if probeInfo.pages > maxPages {
            reportError(json: json, code: 2, message: "File exceeds page limit: \(probeInfo.pages) > \(maxPages)")
            throw ExitCode(2)
        }
        
        // Check if encrypted
        if probeInfo.encrypted {
            reportError(json: json, code: 2, message: "Encrypted/password-protected PDFs are not supported")
            throw ExitCode(2)
        }
        
        if dryRun {
            if json {
                let result: [String: Any] = [
                    "status": "ok",
                    "version": "0.6.4",
                    "source_url": input.hasPrefix("https://") ? stripQuery(input) : "",
                    "sha256": probeInfo.sha256,
                    "pages": probeInfo.pages,
                    "dry_run": true
                ]
                print(jsonString(result))
            } else {
                print("Dry run OK: \(inputURL.lastPathComponent)")
                print("Pages: \(probeInfo.pages)")
                print("Size: \(formatBytes(bytes))")
            }
            return
        }
        
        // Calculate timeout
        let timeoutSeconds: Int
        if timeout == "auto" {
            let ocrPages = ocrMode == .on ? probeInfo.pages : (ocrMode == .auto && probeInfo.scannedPages > 0 ? probeInfo.scannedPages : 0)
            timeoutSeconds = calculateTimeout(pages: probeInfo.pages, ocrPages: ocrPages)
        } else if let parsed = Int(timeout) {
            timeoutSeconds = parsed
        } else {
            reportError(json: json, code: 2, message: "Invalid timeout: \(timeout)")
            throw ExitCode(2)
        }
        
        // Set up output directory
        let outputDir = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        // Create conversion options
        var options = ConvertOptions(
            ocrEnabled: ocrMode != .off,
            ocrLanguage: ocrLang,
            extractImages: extractImages,
            keepOriginalPDF: keepMode,
            timeoutSeconds: timeoutSeconds
        )
        
        // Set up progress reporting
        let onStatus: (String) -> Void = { msg in
            if !self.json {
                fputs("  \(msg)\n", stderr)
            }
        }
        
        // Create pipeline and convert
        let pipeline = ConvertPipeline(options: options, onStatus: onStatus)
        
        do {
            let result = try await pipeline.convert(input: inputURL, outputFolder: outputDir)
            
            let elapsed = Date().timeIntervalSince(startTime)
            
            if json {
                let jsonResult: [String: Any] = [
                    "status": "ok",
                    "version": "0.6.4",
                    "source_url": input.hasPrefix("https://") ? stripQuery(input) : "",
                    "sha256": probeInfo.sha256,
                    "pages": probeInfo.pages,
                    "ocr_pages": result.usedOCR ? probeInfo.scannedPages : 0,
                    "ocr_engine": result.ocrEngine ?? "",
                    "weak_ocr": result.weakOCR,
                    "images": result.pictures,
                    "original_kept": result.originalKept,
                    "folder": result.markdownURL.deletingLastPathComponent().path,
                    "md_path": result.markdownURL.path,
                    "figures_dir": extractImages ? result.markdownURL.deletingLastPathComponent().appendingPathComponent("figures").path : "",
                    "bytes_md": (try? Data(contentsOf: result.markdownURL).count) ?? 0,
                    "warnings": result.warnings,
                    "elapsed_s": elapsed
                ]
                print(jsonString(jsonResult))
            } else {
                print("✓ Converted: \(inputURL.lastPathComponent)")
                print("  → \(result.markdownURL.path)")
                if result.usedOCR {
                    print("  OCR: \(result.ocrEngine ?? "unknown")")
                }
                if result.pictures > 0 {
                    print("  Images: \(result.pictures)")
                }
                print("  Time: \(String(format: "%.1f", elapsed))s")
            }
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            reportError(json: json, code: 3, message: error.localizedDescription, elapsed: elapsed)
            throw ExitCode(3)
        }
    }
    
    private func parseOCRMode(_ raw: String) throws -> OCRMode {
        switch raw.lowercased() {
        case "auto": return .auto
        case "on": return .on
        case "off": return .off
        default:
            throw ValidationError("Invalid OCR mode: \(raw). Use auto, on, or off.")
        }
    }
    
    private func parseKeepMode(_ raw: String) throws -> ConvertOptions.KeepOriginal {
        switch raw.lowercased() {
        case "auto": return .auto
        case "always": return .always
        case "never": return .never
        default:
            throw ValidationError("Invalid keep-original mode: \(raw). Use auto, always, or never.")
        }
    }
    
    private func parseBool(_ raw: String, name: String) throws -> Bool {
        switch raw.lowercased() {
        case "on", "yes", "true": return true
        case "off", "no", "false": return false
        default:
            throw ValidationError("Invalid \(name) value: \(raw). Use on or off.")
        }
    }
    
    enum OCRMode {
        case auto, on, off
    }
}

// MARK: - Fetch Command

struct Fetch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download a file from an HTTPS URL"
    )
    
    @Argument(help: "HTTPS URL to download")
    var url: String
    
    @Option(name: .long, help: "Output directory")
    var out: String
    
    @Option(name: .long, help: "Maximum file size in MB (default: 100)")
    var maxMb: Int = 100
    
    @Flag(name: .long, help: "Output JSON instead of human-readable text")
    var json: Bool = false
    
    func run() async throws {
        // Reject http:// URLs (insecure)
        if url.hasPrefix("http://") {
            reportError(json: json, code: 2, message: "Only HTTPS URLs are supported (not http://)")
            throw ExitCode(2)
        }
        
        let fetcher = try URLFetcher(maxMB: maxMb)
        let outputDir = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        if !json {
            fputs("Downloading \(stripQuery(url))...\n", stderr)
        }
        
        do {
            let downloadedURL = try await fetcher.fetch(urlString: url, to: outputDir)
            
            let attrs = try FileManager.default.attributesOfItem(atPath: downloadedURL.path)
            let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            
            if json {
                let result: [String: Any] = [
                    "status": "ok",
                    "url": stripQuery(url),
                    "path": downloadedURL.path,
                    "bytes": bytes
                ]
                print(jsonString(result))
            } else {
                print("✓ Downloaded: \(downloadedURL.lastPathComponent)")
                print("  → \(downloadedURL.path)")
                print("  Size: \(formatBytes(bytes))")
            }
        } catch {
            reportError(json: json, code: 2, message: error.localizedDescription)
            throw ExitCode(2)
        }
    }
}

// MARK: - Probe Command

struct Probe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect a PDF file"
    )
    
    @Argument(help: "PDF file to probe")
    var file: String
    
    @Flag(name: .long, help: "Output JSON")
    var json: Bool = false
    
    func run() async throws {
        let url = URL(fileURLWithPath: file)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            reportError(json: json, code: 2, message: "File does not exist: \(url.path)")
            throw ExitCode(2)
        }
        
        do {
            let info = try await probeFile(url)
            
            if json {
                let result: [String: Any] = [
                    "pages": info.pages,
                    "has_text_layer": info.hasTextLayer,
                    "scanned_pages": info.scannedPages,
                    "encrypted": info.encrypted,
                    "sha256": info.sha256,
                    "bytes": info.bytes
                ]
                print(jsonString(result))
            } else {
                print("File: \(url.lastPathComponent)")
                print("Pages: \(info.pages)")
                print("Text layer: \(info.hasTextLayer ? "yes" : "no")")
                print("Scanned pages: \(info.scannedPages)")
                print("Encrypted: \(info.encrypted ? "yes" : "no")")
                print("Size: \(formatBytes(info.bytes))")
                print("SHA-256: \(info.sha256)")
            }
        } catch {
            reportError(json: json, code: 3, message: error.localizedDescription)
            throw ExitCode(3)
        }
    }
}

// MARK: - Doctor Command

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check converter installation and dependencies"
    )
    
    @Flag(name: .long, help: "Output JSON")
    var json: Bool = false
    
    func run() async throws {
        // Check channel
        let channel = Distribution.isAppStore ? "mas" : "direct"
        
        // Check MarkItDown
        let service = MarkItDownService()
        let (markitdownPath, markitdownVersion) = await service.refreshStatus()
        
        // Check uv
        let uvPath = findExecutable("uv")
        let uvVersion = uvPath != nil ? await getVersion(uvPath!, args: ["--version"]) : nil
        
        // Check Docling
        let doclingPath = findExecutable("docling")
        let doclingVersion = doclingPath != nil ? await getVersion(doclingPath!, args: ["--version"]) : nil
        
        // Check OCRmyPDF
        let ocrmypdfPath = findExecutable("ocrmypdf")
        let ocrmypdfVersion = ocrmypdfPath != nil ? await getVersion(ocrmypdfPath!, args: ["--version"]) : nil
        
        // Check Tesseract
        let tesseractPath = findExecutable("tesseract")
        let tesseractVersion = tesseractPath != nil ? await getVersion(tesseractPath!, args: ["--version"]) : nil
        
        // Check Tesseract languages
        let tesseractLangs = tesseractPath != nil ? await getTesseractLangs(tesseractPath!) : []
        
        // Check Vision availability
        let visionAvailable = true  // Always available on macOS 14+
        
        if json {
            let result: [String: Any] = [
                "channel": channel,
                "markitdown_path": markitdownPath ?? "",
                "markitdown_version": markitdownVersion,
                "uv_path": uvPath ?? "",
                "uv_version": uvVersion ?? "",
                "docling_path": doclingPath ?? "",
                "docling_version": doclingVersion ?? "",
                "ocrmypdf_path": ocrmypdfPath ?? "",
                "ocrmypdf_version": ocrmypdfVersion ?? "",
                "tesseract_path": tesseractPath ?? "",
                "tesseract_version": tesseractVersion ?? "",
                "tesseract_langs": tesseractLangs,
                "vision_available": visionAvailable
            ]
            print(jsonString(result))
        } else {
            print("yourMark v0.6.4")
            print("Channel: \(channel)")
            print("")
            print("MarkItDown:")
            print("  Path: \(markitdownPath ?? "not found")")
            print("  Version: \(markitdownVersion)")
            print("")
            print("uv: \(uvPath != nil ? "✓" : "✗") \(uvVersion ?? "")")
            print("Docling: \(doclingPath != nil ? "✓" : "✗") \(doclingVersion ?? "")")
            print("OCRmyPDF: \(ocrmypdfPath != nil ? "✓" : "✗") \(ocrmypdfVersion ?? "")")
            print("Tesseract: \(tesseractPath != nil ? "✓" : "✗") \(tesseractVersion ?? "")")
            if !tesseractLangs.isEmpty {
                print("  Languages: \(tesseractLangs.joined(separator: ", "))")
            }
            print("Vision: \(visionAvailable ? "✓" : "✗")")
        }
    }
    
    private func findExecutable(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/\(name)",
            "\(home)/.local/share/uv/tools/\(name)/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)"
        ]
        
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Try which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try? process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }
        
        return nil
    }
    
    private func getVersion(_ path: String, args: [String]) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try? process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            let lines = output.split(separator: "\n")
            if let first = lines.first {
                return String(first).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
    
    private func getTesseractLangs(_ path: String) async -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--list-langs"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try? process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            let lines = output.split(separator: "\n").map(String.init)
            // Skip the first line which is a header
            return Array(lines.dropFirst().filter { !$0.isEmpty })
        }
        
        return []
    }
}

// MARK: - Helper Functions

public func stripQuery(_ urlString: String) -> String {
    guard let url = URL(string: urlString) else { return urlString }
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.query = nil
    components?.fragment = nil
    return components?.url?.absoluteString ?? urlString
}

public func formatBytes(_ bytes: Int64) -> String {
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

public func calculateTimeout(pages: Int, ocrPages: Int) -> Int {
    let base = 120 + (3 * pages) + (20 * ocrPages)
    return min(max(base, 120), 3600)
}

public func jsonString(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

public func reportError(json: Bool, code: Int, message: String, elapsed: Double? = nil) {
    if json {
        var result: [String: Any] = [
            "status": statusString(code),
            "error": [
                "code": code,
                "message": message
            ]
        ]
        if let elapsed = elapsed {
            result["elapsed_s"] = elapsed
        }
        print(jsonString(result))
    } else {
        fputs("Error: \(message)\n", stderr)
    }
}

public func statusString(_ code: Int) -> String {
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

public struct ProbeInfo {
    public var pages: Int
    public var hasTextLayer: Bool
    public var scannedPages: Int
    public var encrypted: Bool
    public var sha256: String
    public var bytes: Int64
    
    public init(pages: Int, hasTextLayer: Bool, scannedPages: Int, encrypted: Bool, sha256: String, bytes: Int64) {
        self.pages = pages
        self.hasTextLayer = hasTextLayer
        self.scannedPages = scannedPages
        self.encrypted = encrypted
        self.sha256 = sha256
        self.bytes = bytes
    }
}

public func probeFile(_ url: URL) async throws -> ProbeInfo {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
    
    // Calculate SHA-256
    let data = try Data(contentsOf: url)
    let sha256 = SHA256.hash(data: data)
    let sha256String = sha256.compactMap { String(format: "%02x", $0) }.joined()
    
    // For PDF files, probe pages and structure
    if url.pathExtension.lowercased() == "pdf" {
        return await PdfWork.runAsync {
            let profile = OcrService.profile(url)
            let pageCount = OcrService.pageCount(of: url)
            
            // Check if PDF is encrypted (try to open with PDFKit)
            var encrypted = false
            if let doc = PDFDocument(url: url) {
                encrypted = doc.isEncrypted
            } else {
                // If PDFKit can't open it at all, it might be encrypted or corrupt
                encrypted = true
            }
            
            return ProbeInfo(
                pages: pageCount,
                hasTextLayer: !profile.needsOCR,
                scannedPages: profile.needsOCR ? pageCount : 0,
                encrypted: encrypted,
                sha256: sha256String,
                bytes: bytes
            )
        }
    }
    
    return ProbeInfo(
        pages: 1,
        hasTextLayer: true,
        scannedPages: 0,
        encrypted: false,
        sha256: sha256String,
        bytes: bytes
    )
}

import CryptoKit
import PDFKit

#endif
