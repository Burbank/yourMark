import Foundation

/// Protocol for testable URL fetching
public protocol URLFetcherProtocol {
    func fetch(urlString: String, to directory: URL) async throws -> URL
}

/// Safe HTTPS-only downloader with size limits, redirect checks, and content validation
public actor URLFetcher: URLFetcherProtocol {
    private let maxBytes: Int64
    private let connectTimeout: TimeInterval = 15
    private let totalTimeout: TimeInterval = 300
    private let maxRedirects = 5
    
    public enum FetchError: Error, LocalizedError {
        case invalidURL(String)
        case notHTTPS(String)
        case httpRedirect(String)
        case tooManyRedirects
        case sizeLimitExceeded(String)
        case invalidContentType(String)
        case notAPDF(String)
        case downloadFailed(String)
        case timeout
        
        public var errorDescription: String? {
            switch self {
            case .invalidURL(let url):
                return "Invalid URL: \(url)"
            case .notHTTPS(let url):
                return "Only HTTPS URLs are supported: \(url)"
            case .httpRedirect(let url):
                return "HTTP redirect detected (insecure): \(url)"
            case .tooManyRedirects:
                return "Too many redirects (max \(5))"
            case .sizeLimitExceeded(let msg):
                return msg
            case .invalidContentType(let type):
                return "Invalid content type: \(type). Expected application/pdf or application/octet-stream"
            case .notAPDF(let msg):
                return msg
            case .downloadFailed(let msg):
                return "Download failed: \(msg)"
            case .timeout:
                return "Download timed out"
            }
        }
    }
    
    private let injectedConfiguration: URLSessionConfiguration?

    public init(maxMB: Int, sessionConfiguration: URLSessionConfiguration? = nil) {
        self.init(maxBytes: Int64(maxMB) * 1_000_000, sessionConfiguration: sessionConfiguration)
    }

    /// `maxBytes` is the streaming cap. Tests use a small cap; the CLI uses megabytes.
    public init(maxBytes: Int64, sessionConfiguration: URLSessionConfiguration? = nil) {
        self.maxBytes = maxBytes
        self.injectedConfiguration = sessionConfiguration
    }
    
    public func fetch(urlString: String, to directory: URL) async throws -> URL {
        // Validate URL
        guard let url = URL(string: urlString) else {
            throw FetchError.invalidURL(urlString)
        }
        
        guard url.scheme == "https" else {
            throw FetchError.notHTTPS(urlString)
        }
        
        // Create session with security settings and redirect handler
        let config = injectedConfiguration ?? URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = connectTimeout
        config.timeoutIntervalForResource = totalTimeout
        config.httpMaximumConnectionsPerHost = 1
        
        let delegate = RedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        
        // Follow redirects manually to validate each hop
        var currentURL = url
        var redirectCount = 0
        
        while redirectCount <= maxRedirects {
            var request = URLRequest(url: currentURL, timeoutInterval: connectTimeout)
            request.httpMethod = "GET"
            request.setValue("yourmark/0.6.4", forHTTPHeaderField: "User-Agent")
            
            // Get headers first to check content length and type
            var headRequest = request
            headRequest.httpMethod = "HEAD"
            
            let (_, headResponse) = try await session.data(for: headRequest)
            
            guard let httpResponse = headResponse as? HTTPURLResponse else {
                throw FetchError.downloadFailed("Invalid response")
            }
            
            // Check for redirects
            if (300...399).contains(httpResponse.statusCode) {
                guard let location = httpResponse.value(forHTTPHeaderField: "Location"),
                      let redirectURL = URL(string: location, relativeTo: currentURL) else {
                    throw FetchError.downloadFailed("Invalid redirect location")
                }
                
                // Validate redirect is HTTPS
                guard redirectURL.scheme == "https" else {
                    throw FetchError.httpRedirect(redirectURL.absoluteString)
                }
                
                redirectCount += 1
                if redirectCount > maxRedirects {
                    throw FetchError.tooManyRedirects
                }
                
                currentURL = redirectURL
                continue
            }
            
            // Check status code
            guard httpResponse.statusCode == 200 else {
                throw FetchError.downloadFailed("HTTP \(httpResponse.statusCode)")
            }
            
            // Check content length
            if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let size = Int64(contentLength) {
                if size > maxBytes {
                    throw FetchError.sizeLimitExceeded("File size \(size / 1_000_000)MB exceeds limit of \(maxBytes / 1_000_000)MB")
                }
            }
            
            // Check content type
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                let type = contentType.split(separator: ";").first?.trimmingCharacters(in: .whitespaces) ?? contentType
                if type != "application/pdf" && type != "application/octet-stream" {
                    throw FetchError.invalidContentType(type)
                }
            }
            
            // Download the file with streaming to check size
            let (data, response) = try await downloadWithSizeCheck(session: session, request: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw FetchError.downloadFailed("Download request failed")
            }
            
            // Verify PDF magic bytes
            guard data.count >= 4 else {
                throw FetchError.notAPDF("File is too small to be a valid PDF")
            }
            
            let magicBytes = data.prefix(4)
            let pdfMagic = Data([0x25, 0x50, 0x44, 0x46])  // %PDF
            guard magicBytes == pdfMagic else {
                throw FetchError.notAPDF("File does not start with PDF magic bytes")
            }
            
            // Save to file
            let filename = suggestFilename(from: httpResponse, url: currentURL)
            let outputURL = directory.appendingPathComponent(filename)
            try data.write(to: outputURL)
            
            return outputURL
        }
        
        throw FetchError.tooManyRedirects
    }
    
    private func downloadWithSizeCheck(session: URLSession, request: URLRequest) async throws -> (Data, URLResponse) {
        var receivedData = Data()
        var receivedResponse: URLResponse?
        
        let (asyncBytes, response) = try await session.bytes(for: request)
        receivedResponse = response
        
        for try await byte in asyncBytes {
            receivedData.append(byte)
            
            // Check size limit while downloading
            if Int64(receivedData.count) > maxBytes {
                throw FetchError.sizeLimitExceeded("Downloaded size exceeds limit of \(maxBytes / 1_000_000)MB")
            }
        }
        
        return (receivedData, receivedResponse!)
    }
    
    private func suggestFilename(from response: HTTPURLResponse, url: URL) -> String {
        // Try Content-Disposition header
        if let disposition = response.value(forHTTPHeaderField: "Content-Disposition") {
            let pattern = #"filename[*]?=(?:"([^"]+)"|'([^']+)'|([^;\s]+))"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: disposition, range: NSRange(disposition.startIndex..., in: disposition)) {
                for i in 1...3 {
                    if match.range(at: i).location != NSNotFound,
                       let range = Range(match.range(at: i), in: disposition) {
                        let filename = String(disposition[range])
                        if !filename.isEmpty {
                            return sanitizeFilename(filename)
                        }
                    }
                }
            }
        }
        
        // Fall back to URL path
        let pathComponent = url.lastPathComponent
        if !pathComponent.isEmpty && pathComponent != "/" {
            return sanitizeFilename(pathComponent)
        }
        
        // Last resort
        return "download.pdf"
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        var clean = name
        
        // Remove path traversal attempts
        clean = clean.replacingOccurrences(of: "..", with: "")
        clean = clean.replacingOccurrences(of: "/", with: "")
        clean = clean.replacingOccurrences(of: "\\", with: "")
        
        // Ensure it has .pdf extension
        if !clean.lowercased().hasSuffix(".pdf") {
            clean += ".pdf"
        }
        
        // Limit length
        if clean.count > 200 {
            let ext = (clean as NSString).pathExtension
            let base = (clean as NSString).deletingPathExtension
            clean = String(base.prefix(190)) + "." + ext
        }
        
        return clean.isEmpty ? "download.pdf" : clean
    }
}

/// Session delegate to intercept and validate redirects
private class RedirectDelegate: NSObject, URLSessionTaskDelegate {
    private var redirectCount = 0
    private let maxRedirects = 5
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirectCount += 1
        
        // Reject if too many redirects
        guard redirectCount <= maxRedirects else {
            completionHandler(nil)
            return
        }
        
        // Reject all automatic follows — URLFetcher follows manually and validates each hop.
        completionHandler(nil)
    }
}
