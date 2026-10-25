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

        var generation = generationConfig
        generation["responseMimeType"] = "application/json"
        generation["responseSchema"] = schema
        let answer = try await send([
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generation,
        ])

        let text = answer.parts.compactMap(\.text).joined()
        guard !text.isEmpty else { throw Failure.noAnswer(reason: answer.reason) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(text.utf8))
    }

    /// Makes Gemini pick exactly one of `functions` (Gemini function declarations) for `prompt`.
    public func call(_ functions: [[String: Any]], prompt: String) async throws -> FunctionCall {
        let answer = try await send([
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "tools": [["functionDeclarations": functions]],
            "toolConfig": ["functionCallingConfig": ["mode": "ANY"]],
            "generationConfig": generationConfig,
        ])
        guard let call = answer.parts.compactMap(\.functionCall).first else {
            throw Failure.noAnswer(reason: answer.reason)
        }
        return FunctionCall(name: call.name, arguments: call.args ?? [:])
    }

    private var generationConfig: [String: Any] {
        var generation: [String: Any] = ["temperature": 0]
        if let thinkingLevel {
            generation["thinkingConfig"] = ["thinkingLevel": thinkingLevel]
        }
        return generation
    }

    /// One step of a conversation in which Gemini must call one of `functions`. Returns the
    /// model's turn exactly as sent, to append to `contents` for the next step (Gemini 3 needs
    /// its thought signatures back), and the calls it made.
    public func toolStep(_ contents: [[String: Any]], functions: [[String: Any]]) async throws -> (turn: [String: Any], calls: [FunctionCall]) {
        let data = try await post([
            "contents": contents,
            "tools": [["functionDeclarations": functions]],
            "toolConfig": ["functionCallingConfig": ["mode": "ANY"]],
            "generationConfig": generationConfig,
        ])
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let turn = ((raw?["candidates"] as? [[String: Any]])?.first)?["content"] as? [String: Any] else {
            throw Failure.noAnswer(reason: answer.reason)
        }
        let calls = answer.parts.compactMap(\.functionCall).map { FunctionCall(name: $0.name, arguments: $0.args ?? [:]) }
        return (turn, calls)
    }

    private func send(_ body: [String: Any]) async throws -> Answer {
        try JSONDecoder().decode(Answer.self, from: try await post(body))
    }

    private func post(_ body: [String: Any]) async throws -> Data {
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
        return data
    }

    private struct Answer: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                var parts: [Part]?
            }
            var content: Content?
            var finishReason: String?
        }
        struct Part: Decodable {
            struct Call: Decodable {
                var name: String
                var args: [String: FunctionCall.Value]?
            }
            var text: String?
            var functionCall: Call?
        }
        struct Feedback: Decodable { var blockReason: String? }
        var candidates: [Candidate]?
        var promptFeedback: Feedback?

        var parts: [Part] { candidates?.first?.content?.parts ?? [] }
        var reason: String { promptFeedback?.blockReason ?? candidates?.first?.finishReason ?? "empty" }
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { var message: String }
        var error: Detail
    }
}

/// The function Gemini chose, with its arguments.
public struct FunctionCall: Sendable, Equatable {
    /// An argument value: Gemini's function arguments are plain JSON.
    public enum Value: Decodable, Sendable, Equatable {
        case number(Double)
        case text(String)
        case flag(Bool)
        case list([Value])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .flag(flag)
            } else if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else if let list = try? container.decode([Value].self) {
                self = .list(list)
            } else {
                self = .text(try container.decode(String.self))
            }
        }
    }

    public var name: String
    public var arguments: [String: Value]

    public init(name: String, arguments: [String: Value] = [:]) {
        self.name = name
        self.arguments = arguments
    }

    public func number(_ key: String) -> Double? {
        if case .number(let value)? = arguments[key] { return value }
        if case .text(let text)? = arguments[key] { return Double(text) }
        return nil
    }

    public func flag(_ key: String) -> Bool? {
        if case .flag(let value)? = arguments[key] { return value }
        return nil
    }

    public func text(_ key: String) -> String? {
        if case .text(let value)? = arguments[key] { return value }
        return nil
    }

    public func texts(_ key: String) -> [String] {
        guard case .list(let values)? = arguments[key] else { return text(key).map { [$0] } ?? [] }
        return values.compactMap { if case .text(let value) = $0 { value } else { nil } }
    }
}
