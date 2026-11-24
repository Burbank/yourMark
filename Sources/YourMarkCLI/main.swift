import ArgumentParser
import Foundation
import YourMarkCore

#if APPSTORE
@main
struct YourMarkCLICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "yourmark",
        abstract: "yourMark document converter",
        version: "0.6.4"
    )
    
    func run() async throws {
        print("yourmark CLI is not available in the App Store build.")
        throw ExitCode(4)
    }
}
#else

@main
struct YourMarkCLICommand: AsyncParsableCommand {
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
            let fetcher = URLFetcher(maxMB: maxMb)
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
        
        let outputDir = URL(fileURLWithPath: out)
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            try throwMapped(error, json: json, elapsed: Date().timeIntervalSince(startTime))
        }
        
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
            
            let partial = !result.warnings.isEmpty
            if json {
                let jsonResult: [String: Any] = [
                    "status": partial ? "partial" : "ok",
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
            if partial {
                throw ExitCode(1)
            }
        } catch let exit as ExitCode {
            throw exit
        } catch {
            try throwMapped(error, json: json, elapsed: Date().timeIntervalSince(startTime))
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
        
        let fetcher = URLFetcher(maxMB: maxMb)
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

#endif

// MARK: - Helper Functions

public func jsonString(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

func cliExitCode(for error: Error) -> Int {
    if let markError = error as? YourMarkError {
        switch markError {
        case .timedOut: return 124
        case .engineNotFound: return 4
        case .outputMissing: return 5
        case .invalidInput: return 2
        case .processFailed: return 3
        }
    }
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain {
        return 5
    }
    return 3
}

func throwMapped(_ error: Error, json: Bool, elapsed: Double?) throws -> Never {
    let code = cliExitCode(for: error)
    reportError(json: json, code: code, message: error.localizedDescription, elapsed: elapsed)
    throw ExitCode(Int32(code))
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
