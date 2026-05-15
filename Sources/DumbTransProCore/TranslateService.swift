import Foundation

public enum TranslateError: Error, LocalizedError {
    case noAPIKey
    case requestTimedOut
    case apiError(statusCode: Int, message: String)
    case invalidResponse
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API Key 未设置"
        case .requestTimedOut: return "翻译请求超时，请稍后重试"
        case .apiError(let code, let msg): return "API 错误 (\(code)): \(msg)"
        case .invalidResponse: return "无效的 API 响应"
        case .networkError(let err): return "网络错误: \(err.localizedDescription)"
        }
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

    public func translate(_ text: String, style: TranslationStyle = .natural) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = "\(style.filenamePrompt)\n\n现在翻译：\(text)"

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0,
            "max_tokens": 100,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await send(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslateError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = parseErrorMessage(from: data)
            throw TranslateError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslateError.invalidResponse
        }

        return TextFormatter.toKebabCase(content)
    }

    public func lookup(_ text: String, style: TranslationStyle = .natural) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = "\(style.lookupPrompt)\n\n\(text)"

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0,
            "max_tokens": 500,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await send(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslateError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = parseErrorMessage(from: data)
            throw TranslateError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslateError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
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
