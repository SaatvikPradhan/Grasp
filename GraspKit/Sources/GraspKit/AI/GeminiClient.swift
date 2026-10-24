import Foundation

/// Gemini over REST: an optional image plus instructions in, JSON that matches a schema out.
public struct GeminiClient: Sendable {
    /// Read the demo contract correctly in about 1.5 s (Oct 24). `gemini-3.8-flash` was
    /// just as accurate but took about 4.5 s; switch to it, with `thinkingLevel` "low", if lite misreads.
    public static let fastModel = "gemini-3.5-flash-lite"

    public enum Failure: LocalizedError {
        case missingKey
        case http(status: Int, message: String)
        case noAnswer(reason: String)

        public var errorDescription: String? {
            switch self {
            case .missingKey: "No Gemini key. Add GEMINI_API_KEY to Config/Secrets.xcconfig."
            case .http(let status, let message): "Gemini error \(status): \(message)"
            case .noAnswer(let reason): "Gemini gave no answer (\(reason))."
            }
        }
    }

    public var apiKey: String
    public var model: String
    /// "minimal" is fastest; not every model accepts it.
    public var thinkingLevel: String?

    public init(apiKey: String, model: String = GeminiClient.fastModel, thinkingLevel: String? = "minimal") {
        self.apiKey = apiKey
        self.model = model
        self.thinkingLevel = thinkingLevel
    }

    /// A client using the key from the app's Info.plist, or nil when none is set.
    public static var fromAppKeys: GeminiClient? {
        APIKeys.gemini.map { GeminiClient(apiKey: $0) }
    }

    /// Sends `prompt` (and `jpeg`, if any) and decodes the JSON answer as `T`.
    /// `schema` is a Gemini response schema; its property names should be snake_case.
    public func generate<T: Decodable>(_ type: T.Type, prompt: String, jpeg: Data? = nil, schema: [String: Any]) async throws -> T {
        var parts: [[String: Any]] = []
        if let jpeg {
            parts.append(["inlineData": ["mimeType": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        parts.append(["text": prompt])

        var generation: [String: Any] = [
            "responseMimeType": "application/json",
            "responseSchema": schema,
            "temperature": 0,
        ]
        if let thinkingLevel {
            generation["thinkingConfig"] = ["thinkingLevel": thinkingLevel]
        }
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generation,
        ]

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
            throw Failure.http(status: status, message: message ?? String(decoding: data.prefix(300), as: UTF8.self))
        }

        let answer = try JSONDecoder().decode(Answer.self, from: data)
        guard let text = answer.candidates?.first?.content?.parts?.compactMap(\.text).joined(), !text.isEmpty else {
            let reason = answer.promptFeedback?.blockReason ?? answer.candidates?.first?.finishReason ?? "empty"
            throw Failure.noAnswer(reason: reason)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(text.utf8))
    }

    private struct Answer: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { var text: String? }
                var parts: [Part]?
            }
            var content: Content?
            var finishReason: String?
        }
        struct Feedback: Decodable { var blockReason: String? }
        var candidates: [Candidate]?
        var promptFeedback: Feedback?
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { var message: String }
        var error: Detail
    }
}
