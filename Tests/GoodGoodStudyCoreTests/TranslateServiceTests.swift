import Testing
import Foundation
@testable import GoodGoodStudyCore

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockResponseData: Data?
    nonisolated(unsafe) static var mockStatusCode: Int = 200
    nonisolated(unsafe) static var mockError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = MockURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.mockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = MockURLProtocol.mockResponseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct TranslateServiceTests {
    func makeTestSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func successfulTranslation() async throws {
        let responseJSON = """
        {
          "choices": [{
            "message": {
              "content": "good good study"
            }
          }]
        }
        """
        MockURLProtocol.mockResponseData = responseJSON.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.translate("好好学习")
        #expect(result == "good-good-study")
    }

    @Test func apiErrorReturnsError() async {
        MockURLProtocol.mockStatusCode = 401
        MockURLProtocol.mockResponseData = """
        {"error":{"message":"Invalid API key"}}
        """.data(using: .utf8)

        let service = TranslateService(apiKey: "bad-key", session: makeTestSession())
        do {
            _ = try await service.translate("测试")
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is TranslateError)
        }
    }

    @Test func responseWithWhitespace() async throws {
        let responseJSON = """
        {
          "choices": [{
            "message": {
              "content": "  Good Good Study  "
            }
          }]
        }
        """
        MockURLProtocol.mockResponseData = responseJSON.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.translate("好好学习")
        #expect(result == "good-good-study")
    }
}
