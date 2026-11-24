import XCTest
import YourMarkCore
@testable import yourmark

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
}