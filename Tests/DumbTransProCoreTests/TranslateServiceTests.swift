import Testing
import Foundation
@testable import DumbTransProCore

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockResponseData: Data?
    nonisolated(unsafe) static var mockStatusCode: Int = 200
    nonisolated(unsafe) static var mockError: Error?
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequestBody = request.httpBody ?? Self.readBodyStream(from: request)
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

    private static func readBodyStream(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}

@Suite(.serialized)
struct TranslateServiceTests {
    func makeTestSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func requestPrompt() throws -> String {
        let data = try #require(MockURLProtocol.lastRequestBody)
        let object = try JSONSerialization.jsonObject(with: data)
        let json = try #require(object as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let first = try #require(messages.first)
        return try #require(first["content"] as? String)
    }

    @Test func plainStyleTranslation() async throws {
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
        let result = try await service.translate("好好学习", style: .plain)
        #expect(result == "good-good-study")
    }

    @Test func naturalStyleTranslation() async throws {
        let responseJSON = """
        {
          "choices": [{
            "message": {
              "content": "study hard"
            }
          }]
        }
        """
        MockURLProtocol.mockResponseData = responseJSON.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.translate("好好学习", style: .natural)
        #expect(result == "study-hard")
    }

    @Test func elegantStyleTranslation() async throws {
        let responseJSON = """
        {
          "choices": [{
            "message": {
              "content": "diligent pursuit of erudition"
            }
          }]
        }
        """
        MockURLProtocol.mockResponseData = responseJSON.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.translate("好好学习", style: .elegant)
        #expect(result == "diligent-pursuit-of-erudition")
    }

    @Test func apiErrorReturnsError() async {
        MockURLProtocol.mockStatusCode = 401
        MockURLProtocol.mockResponseData = """
        {"error":{"message":"Invalid API key"}}
        """.data(using: .utf8)

        let service = TranslateService(apiKey: "bad-key", session: makeTestSession())
        do {
            _ = try await service.translate("测试", style: .plain)
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
        let result = try await service.translate("好好学习", style: .plain)
        #expect(result == "good-good-study")
    }

    @Test func lookupReturnsRawText() async throws {
        let responseJSON = """
        {
          "choices": [{
            "message": {
              "content": "你好，世界！"
            }
          }]
        }
        """
        MockURLProtocol.mockResponseData = responseJSON.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.lookup("Hello, world!")
        // lookup must NOT apply kebab-case formatting
        #expect(result == "你好，世界！")
    }

    @Test func lookupTrimsWhitespace() async throws {
        let responseJSON = """
        {
          "choices": [{
            "message": {
              "content": "  人工智能  "
            }
          }]
        }
        """
        MockURLProtocol.mockResponseData = responseJSON.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.lookup("AI")
        #expect(result == "人工智能")
    }

    @Test func defaultStyleIsNatural() async throws {
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
        // Call without style parameter — should default to .natural
        let result = try await service.translate("好好学习")
        #expect(result == "good-good-study")
        let prompt = try requestPrompt()
        #expect(prompt.contains("风格：自然"))
    }

    @Test func lookupUsesSelectedStylePrompt() async throws {
        let responseJSON = """
        {
          "choices": [{
            "message": {
              "content": "月光落在纸上。"
            }
          }]
        }
        """
        MockURLProtocol.mockResponseData = responseJSON.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.lookup("Moonlight rests on the page.", style: .elegant)
        #expect(result == "月光落在纸上。")
        let prompt = try requestPrompt()
        #expect(prompt.contains("风格：典雅"))
    }
}
