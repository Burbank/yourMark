import XCTest
import YourMarkCore
@testable import YourMarkCLI

/// In-memory stub transport for URLFetcher redirect and policy tests.
final class MockURLFetcher: URLFetcherProtocol {
    var error: Error?
    var resultURL: URL?

    func fetch(urlString: String, to directory: URL) async throws -> URL {
        if let error { throw error }
        guard let resultURL else { throw URLFetcher.FetchError.invalidURL(urlString) }
        return resultURL
    }
}

final class FetchSecurityTests: XCTestCase {
    func testURLFetcherRejectsHTTPScheme() async {
        let fetcher = URLFetcher(maxMB: 1)
        do {
            _ = try await fetcher.fetch(urlString: "http://example.com/a.pdf", to: FileManager.default.temporaryDirectory)
            XCTFail("Expected http rejection")
        } catch URLFetcher.FetchError.notHTTPS {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStripQueryRemovesSecrets() {
        XCTAssertEqual(
            stripQuery("https://cdn.example.com/doc.pdf?sig=abc#frag"),
            "https://cdn.example.com/doc.pdf"
        )
    }

    func testStubRejectsOversizeContentLength() async {
        StubHTTP.queue = [
            "https://files.test/big.pdf": (200, ["Content-Type": "application/pdf", "Content-Length": "99999999"], Data("%PDF".utf8))
        ]
        let fetcher = stubFetcher(maxBytes: 100)
        do {
            _ = try await fetcher.fetch(urlString: "https://files.test/big.pdf", to: FileManager.default.temporaryDirectory)
            XCTFail("Expected size limit")
        } catch URLFetcher.FetchError.sizeLimitExceeded {
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testStubRejectsHTMLContentType() async {
        StubHTTP.queue = [
            "https://files.test/page.pdf": (200, ["Content-Type": "text/html"], Data("%PDF".utf8))
        ]
        let fetcher = stubFetcher(maxBytes: 100)
        do {
            _ = try await fetcher.fetch(urlString: "https://files.test/page.pdf", to: FileManager.default.temporaryDirectory)
            XCTFail("Expected content type rejection")
        } catch URLFetcher.FetchError.invalidContentType {
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testStubRejectsHTMLDisguisedAsPDF() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        StubHTTP.queue = [
            "https://files.test/fake.pdf": (200, ["Content-Type": "application/pdf", "Content-Length": "12"], Data("<html></html>".utf8))
        ]
        let fetcher = stubFetcher(maxBytes: 100)
        do {
            _ = try await fetcher.fetch(urlString: "https://files.test/fake.pdf", to: dir)
            XCTFail("Expected magic-byte rejection")
        } catch URLFetcher.FetchError.notAPDF {
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testStubRejectsHTTPRedirect() async {
        StubHTTP.queue = [
            "https://files.test/a.pdf": (302, ["Location": "http://files.test/a.pdf"], Data())
        ]
        let fetcher = stubFetcher(maxBytes: 100)
        do {
            _ = try await fetcher.fetch(urlString: "https://files.test/a.pdf", to: FileManager.default.temporaryDirectory)
            XCTFail("Expected http hop rejection")
        } catch URLFetcher.FetchError.httpRedirect {
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testStubRejectsMoreThanFiveRedirects() async {
        var queue: [String: (Int, [String: String], Data)] = [:]
        for hop in 0...6 {
            let from = "https://files.test/r\(hop).pdf"
            let next = "https://files.test/r\(hop + 1).pdf"
            queue[from] = (302, ["Location": next], Data())
        }
        StubHTTP.queue = queue
        let fetcher = stubFetcher(maxBytes: 100)
        do {
            _ = try await fetcher.fetch(urlString: "https://files.test/r0.pdf", to: FileManager.default.temporaryDirectory)
            XCTFail("Expected redirect cap")
        } catch URLFetcher.FetchError.tooManyRedirects {
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testStubRejectsStreamingOversize() async {
        var body = Data("%PDF".utf8)
        body.append(Data(repeating: 0x20, count: 32))
        StubHTTP.queue = [
            "https://files.test/stream.pdf": (200, ["Content-Type": "application/pdf"], body)
        ]
        let fetcher = stubFetcher(maxBytes: 8)
        do {
            _ = try await fetcher.fetch(urlString: "https://files.test/stream.pdf", to: FileManager.default.temporaryDirectory)
            XCTFail("Expected streaming cap")
        } catch URLFetcher.FetchError.sizeLimitExceeded {
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testSessionDisablesCookies() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        StubHTTP.queue = [
            "https://files.test/ok.pdf": (200, ["Content-Type": "application/pdf", "Content-Length": "8"], Data("%PDF-1.4".utf8))
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubHTTP.self]
        let fetcher = URLFetcher(maxBytes: 100, sessionConfiguration: config)
        _ = try await fetcher.fetch(urlString: "https://files.test/ok.pdf", to: dir)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.httpCookieAcceptPolicy, .never)
    }

    private func stubFetcher(maxBytes: Int64) -> URLFetcher {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubHTTP.self]
        return URLFetcher(maxBytes: maxBytes, sessionConfiguration: config)
    }
}

final class StubHTTP: URLProtocol {
    static var queue: [String: (Int, [String: String], Data)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.url?.absoluteString ?? ""
        let item = StubHTTP.queue[key] ?? (500, [:], Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: item.0, httpVersion: "HTTP/1.1", headerFields: item.1)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: item.2)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}