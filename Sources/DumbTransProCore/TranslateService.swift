import Foundation

public enum TranslateError: Error, LocalizedError {
    case noAPIKey
    case requestTimedOut
    case apiError(statusCode: Int, message: String)
    case contentBlocked(message: String)
    case invalidResponse
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API Key 未设置"
        case .requestTimedOut: return "翻译请求超时，请稍后重试"
        case .apiError(let code, let msg): return "API 错误 (\(code)): \(msg)"
        case .contentBlocked(let msg):
            return "服务商触发了内容审核,可能涉及敏感内容。\n建议改用 OpenAI 或 Friday 等其他端点重试。\n\n服务商返回:\(msg)"
        case .invalidResponse: return "无效的 API 响应"
        case .networkError(let err): return "网络错误: \(err.localizedDescription)"
        }
    }
}

public struct LookupResult: Sendable, Equatable {
    public let text: String
    public let didFallback: Bool

    public init(text: String, didFallback: Bool) {
        self.text = text
        self.didFallback = didFallback
    }
}

public final class TranslateService: Sendable {
    private let apiKey: String
    private let baseURL: String
    private let model: String
    private let session: URLSession

    public init(apiKey: String, baseURL: String = "https://api.openai.com/v1", model: String = "gpt-4o-mini", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    // MARK: - Public API

    public func translate(_ text: String, style: TranslationStyle = .natural) async throws -> String {
        let raw = try await chatRequest(
            system: style.filenameSystem,
            examples: style.filenameExamples,
            userText: text,
            timeout: 30,
            maxTokens: 1500
        )

        if style != .natural && Self.isLikelyLeakedKebab(input: text, output: raw) {
            // Silent fallback: pasted into a filename, prefix would corrupt it
            let natural = try await chatRequest(
                system: TranslationStyle.natural.filenameSystem,
                examples: TranslationStyle.natural.filenameExamples,
                userText: text,
                timeout: 30,
                maxTokens: 1500
            )
            return TextFormatter.toKebabCase(natural)
        }
        return TextFormatter.toKebabCase(raw)
    }

    public func lookup(_ text: String, style: TranslationStyle = .natural) async throws -> LookupResult {
        let raw = try await chatRequest(
            system: style.lookupSystem,
            examples: style.lookupExamples,
            userText: text,
            timeout: 90,
            maxTokens: 4000
        )

        if style != .natural && Self.isLikelyLeakedLookup(input: text, output: raw) {
            let natural = try await chatRequest(
                system: TranslationStyle.natural.lookupSystem,
                examples: TranslationStyle.natural.lookupExamples,
                userText: text,
                timeout: 90,
                maxTokens: 4000
            )
            return LookupResult(
                text: natural.trimmingCharacters(in: .whitespacesAndNewlines),
                didFallback: true
            )
        }
        return LookupResult(
            text: raw.trimmingCharacters(in: .whitespacesAndNewlines),
            didFallback: false
        )
    }

    // MARK: - Leak detection (exposed for tests)

    static func isLikelyLeakedLookup(input: String, output: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.contains("→") || trimmed.contains(" -> ") { return true }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
        // Multi-line list response when input is short — almost certainly a leak
        if input.count <= 80 && lines.count >= 5 { return true }
        return false
    }

    static func isLikelyLeakedKebab(input: String, output: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.contains("→") || trimmed.contains(" -> ") { return true }
        // A filename should be one line; multiple lines → leak
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count >= 2 { return true }
        // Unreasonably long for a filename
        if trimmed.count > 120 { return true }
        return false
    }

    // MARK: - HTTP

    private func chatRequest(
        system: String,
        examples: [(input: String, output: String)],
        userText: String,
        timeout: TimeInterval,
        maxTokens: Int
    ) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for pair in examples {
            messages.append(["role": "user", "content": pair.input])
            messages.append(["role": "assistant", "content": pair.output])
        }
        messages.append(["role": "user", "content": userText])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0,
            "max_tokens": maxTokens,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await send(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslateError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = parseErrorMessage(from: data)
            if httpResponse.statusCode == 400 && Self.isContentBlock(message) {
                throw TranslateError.contentBlocked(message: message)
            }
            throw TranslateError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        return try extractContent(from: data)
    }

    private func extractContent(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw TranslateError.invalidResponse
        }
        let primary = (message["content"] as? String) ?? ""
        if !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return primary
        }
        let finishReason = (first["finish_reason"] as? String) ?? ""
        if finishReason == "length" {
            throw TranslateError.apiError(statusCode: 200, message: "模型未输出最终答案(可能被 token 上限截断)。请改用非推理模型,或切换到其他端点。")
        }
        throw TranslateError.invalidResponse
    }

    private static func isContentBlock(_ message: String) -> Bool {
        let lower = message.lowercased()
        let keywords = ["敏感", "不安全", "内容审核", "合规", "content policy", "moderation", "unsafe content", "sensitive content"]
        return keywords.contains { lower.contains($0.lowercased()) }
    }

    private func parseErrorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return "Unknown error"
        }
        return message
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw TranslateError.requestTimedOut
        } catch {
            throw TranslateError.networkError(error)
        }
    }
}
