import Testing
import Foundation
@testable import DumbTransProCore

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockResponseData: Data?
    nonisolated(unsafe) static var mockStatusCode: Int = 200
    nonisolated(unsafe) static var mockError: Error?
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var lastAuthorizationHeader: String?
    nonisolated(unsafe) static var allRequestBodies: [Data] = []
    nonisolated(unsafe) static var responseQueue: [(data: Data, status: Int)] = []

    static func reset() {
        mockResponseData = nil
        mockStatusCode = 200
        mockError = nil
        lastRequestBody = nil
        lastAuthorizationHeader = nil
        allRequestBodies = []
        responseQueue = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.readBodyStream(from: request)
        MockURLProtocol.lastRequestBody = body
        MockURLProtocol.lastAuthorizationHeader = request.value(forHTTPHeaderField: "Authorization")
        if let body { MockURLProtocol.allRequestBodies.append(body) }
        if let error = MockURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let payload: Data?
        let status: Int
        if !MockURLProtocol.responseQueue.isEmpty {
            let next = MockURLProtocol.responseQueue.removeFirst()
            payload = next.data
            status = next.status
        } else {
            payload = MockURLProtocol.mockResponseData
            status = MockURLProtocol.mockStatusCode
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let payload {
            client?.urlProtocol(self, didLoad: payload)
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
        MockURLProtocol.reset()
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

    @Test func topLevelAPIErrorMessageIsPreserved() async {
        MockURLProtocol.reset()
        MockURLProtocol.mockStatusCode = 401
        MockURLProtocol.mockResponseData = """
        {"code":401,"message":"invalid app id"}
        """.data(using: .utf8)

        let service = TranslateService(apiKey: "bad-key", session: makeTestSession())
        do {
            _ = try await service.translate("测试", style: .plain)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TranslateError {
            if case .apiError(let statusCode, let message) = error {
                #expect(statusCode == 401)
                #expect(message == "invalid app id")
            } else {
                Issue.record("expected apiError, got \(error)")
            }
        } catch {
            Issue.record("expected TranslateError, got \(error)")
        }
    }

    @Test func trimsAuthorizationHeaderWhitespace() async throws {
        MockURLProtocol.reset()
        let responseJSON = """
        {"choices":[{"message":{"content":"study hard"}}]}
        """
        MockURLProtocol.mockResponseData = responseJSON.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = TranslateService(apiKey: "  app-id-with-newline\n", session: makeTestSession())
        _ = try await service.translate("好好学习", style: .natural)

        #expect(MockURLProtocol.lastAuthorizationHeader == "Bearer app-id-with-newline")
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
        MockURLProtocol.reset()
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
        #expect(result.text == "你好，世界！")
        #expect(result.didFallback == false)
    }

    @Test func lookupTrimsWhitespace() async throws {
        MockURLProtocol.reset()
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
        #expect(result.text == "人工智能")
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

    // MARK: - Leak detection helpers

    @Test func leakedLookupDetectedWhenOutputContainsArrow() {
        let bad = "Hello → 你好\nWorld → 世界\nFoo → 嗯"
        #expect(TranslateService.isLikelyLeakedLookup(input: "Hello", output: bad))
    }

    @Test func leakedLookupDetectedWhenMultilineOnShortInput() {
        let bad = """
        line1
        line2
        line3
        line4
        line5
        line6
        """
        #expect(TranslateService.isLikelyLeakedLookup(input: "test", output: bad))
    }

    @Test func normalLookupOutputNotFlagged() {
        #expect(!TranslateService.isLikelyLeakedLookup(input: "Hello", output: "你好"))
        #expect(!TranslateService.isLikelyLeakedLookup(
            input: "Time flies",
            output: "光阴荏苒,白驹过隙。"
        ))
    }

    @Test func longPoeticLookupOutputNotFlagged() {
        // Elegant style on a longer input might produce multi-line poem — should NOT be flagged
        let poem = """
        晨光熹微,盈室如练。
        风过帘动,影上窗前。
        """
        #expect(!TranslateService.isLikelyLeakedLookup(input: "The morning light filled the room.", output: poem))
    }

    @Test func leakedKebabDetectedWhenOutputContainsArrow() {
        let bad = "好好学习 → good good study"
        #expect(TranslateService.isLikelyLeakedKebab(input: "好好学习", output: bad))
    }

    @Test func leakedKebabDetectedWhenMultiline() {
        let bad = "good good study\nday day up"
        #expect(TranslateService.isLikelyLeakedKebab(input: "好好学习", output: bad))
    }

    @Test func normalKebabOutputNotFlagged() {
        #expect(!TranslateService.isLikelyLeakedKebab(input: "好好学习", output: "good good study"))
    }

    // MARK: - Fallback flow

    @Test func plainLookupFallsBackWhenModelLeaks() async throws {
        MockURLProtocol.reset()
        let leakResponse = """
        {"choices":[{"message":{"content":"Hello → 嘿\\nLong time no see → 好久不见\\nTake it easy → 别紧张\\nWhat's up → 咋了\\nIt is what it is → 事就是这事儿"}}]}
        """
        let fallbackResponse = """
        {"choices":[{"message":{"content":"可选参考图片"}}]}
        """
        MockURLProtocol.responseQueue = [
            (data: leakResponse.data(using: .utf8)!, status: 200),
            (data: fallbackResponse.data(using: .utf8)!, status: 200),
        ]

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.lookup("and optional reference images", style: .plain)
        #expect(result.didFallback == true)
        #expect(result.text == "可选参考图片")
        // Two calls were made (primary + fallback)
        #expect(MockURLProtocol.allRequestBodies.count == 2)
    }

    @Test func elegantLookupFallsBackWhenModelLeaks() async throws {
        MockURLProtocol.reset()
        let leakResponse = """
        {"choices":[{"message":{"content":"Wisdom → 睿哲\\nSolitude → 孤怀\\nTime → 光阴\\nLove → 情\\nDream → 梦\\nHope → 望"}}]}
        """
        let fallbackResponse = """
        {"choices":[{"message":{"content":"智慧"}}]}
        """
        MockURLProtocol.responseQueue = [
            (data: leakResponse.data(using: .utf8)!, status: 200),
            (data: fallbackResponse.data(using: .utf8)!, status: 200),
        ]

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.lookup("wisdom", style: .elegant)
        #expect(result.didFallback == true)
        #expect(result.text == "智慧")
    }

    @Test func plainKebabFallsBackSilentlyWhenModelLeaks() async throws {
        MockURLProtocol.reset()
        let leakResponse = """
        {"choices":[{"message":{"content":"好好学习 → good good study"}}]}
        """
        let fallbackResponse = """
        {"choices":[{"message":{"content":"study hard"}}]}
        """
        MockURLProtocol.responseQueue = [
            (data: leakResponse.data(using: .utf8)!, status: 200),
            (data: fallbackResponse.data(using: .utf8)!, status: 200),
        ]

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.translate("好好学习", style: .plain)
        // Kebab path: no prefix, just clean fallback
        #expect(result == "study-hard")
        #expect(MockURLProtocol.allRequestBodies.count == 2)
    }

    @Test func naturalStyleDoesNotTriggerFallback() async throws {
        // Even if response contains arrow, natural style does NOT fall back (it IS the fallback)
        MockURLProtocol.reset()
        let response = """
        {"choices":[{"message":{"content":"a → b"}}]}
        """
        MockURLProtocol.responseQueue = [
            (data: response.data(using: .utf8)!, status: 200),
        ]

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.lookup("test", style: .natural)
        #expect(result.text == "a → b")
        #expect(result.didFallback == false)
        #expect(MockURLProtocol.allRequestBodies.count == 1)
    }

    @Test func goodLookupOutputPassesThrough() async throws {
        MockURLProtocol.reset()
        let response = """
        {"choices":[{"message":{"content":"睿哲"}}]}
        """
        MockURLProtocol.responseQueue = [
            (data: response.data(using: .utf8)!, status: 200),
        ]

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.lookup("wisdom", style: .elegant)
        #expect(result.text == "睿哲")
        #expect(result.didFallback == false)
        #expect(MockURLProtocol.allRequestBodies.count == 1)
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
        #expect(result.text == "月光落在纸上。")
        let prompt = try requestPrompt()
        #expect(prompt.contains("典雅"))
    }
}
