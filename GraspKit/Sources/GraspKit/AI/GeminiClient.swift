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

    /// A video or other file to send with a prompt.
    public enum Media: Sendable {
        /// Small enough to go in the request (under about 15 MB).
        case inline(Data, mimeType: String)
        /// Uploaded first with `upload`.
        case file(uri: String, mimeType: String)
        /// A public YouTube video, which Gemini watches itself.
        case youTube(URL)

        var part: [String: Any] {
            switch self {
            case .inline(let data, let mimeType): ["inlineData": ["mimeType": mimeType, "data": data.base64EncodedString()]]
            case .file(let uri, let mimeType): ["fileData": ["mimeType": mimeType, "fileUri": uri]]
            case .youTube(let url): ["fileData": ["fileUri": url.absoluteString]]
            }
        }
    }

    /// Sends `prompt` (and `jpeg`, if any, or several `images`, each after its caption, or `media`) and
    /// decodes the JSON answer as `T`. `schema` is a Gemini response schema; its property names should be snake_case.
    public func generate<T: Decodable>(_ type: T.Type, prompt: String, jpeg: Data? = nil,
                                       images: [(caption: String, jpeg: Data)] = [], media: [Media] = [],
                                       schema: [String: Any]) async throws -> T {
        var parts: [[String: Any]] = media.map(\.part)
        if let jpeg {
            parts.append(["inlineData": ["mimeType": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        for image in images {
            parts.append(["text": image.caption])
            parts.append(["inlineData": ["mimeType": "image/jpeg", "data": image.jpeg.base64EncodedString()]])
        }
        parts.append(["text": prompt])

        var generation = generationConfig
        generation["responseMimeType"] = "application/json"
        generation["responseSchema"] = schema
        // Video is long: fewer tokens a frame, and more time to watch it.
        if !media.isEmpty { generation["mediaResolution"] = "MEDIA_RESOLUTION_LOW" }
        let answer = try JSONDecoder().decode(Answer.self, from: try await post([
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generation,
        ], timeout: media.isEmpty ? 30 : 240))

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

    /// Answers `prompt` in plain text with Google Search, returning the text and which web
    /// pages back which parts of it.
    public func searchGrounded(_ prompt: String) async throws -> Grounded {
        let data = try await post([
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "tools": [["google_search": [String: Any]()]],
            "generationConfig": generationConfig,
        ], timeout: 60)
        let answer = try JSONDecoder().decode(GroundedAnswer.self, from: data)
        let candidate = answer.candidates?.first
        let text = (candidate?.content?.parts ?? []).compactMap(\.text).joined()
        guard !text.isEmpty else { throw Failure.noAnswer(reason: candidate?.finishReason ?? "empty") }
        let metadata = candidate?.groundingMetadata
        return Grounded(
            text: text,
            searches: metadata?.webSearchQueries ?? [],
            pages: (metadata?.groundingChunks ?? []).map { Grounded.Page(title: $0.web?.title ?? "", url: $0.web?.uri ?? "") },
            supports: (metadata?.groundingSupports ?? []).compactMap { support in
                guard let segment = support.segment?.text else { return nil }
                return Grounded.Support(text: segment, pages: support.groundingChunkIndices ?? [])
            }
        )
    }

    /// Uploads a file too big to send inline (a lecture video) and waits until Gemini can use it.
    public func upload(_ data: Data, mimeType: String, name: String) async throws -> Media {
        var start = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/upload/v1beta/files")!)
        start.httpMethod = "POST"
        start.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        start.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        start.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        start.setValue(String(data.count), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        start.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        start.setValue("application/json", forHTTPHeaderField: "Content-Type")
        start.httpBody = try JSONSerialization.data(withJSONObject: ["file": ["display_name": name]])
        let (_, started) = try await URLSession.shared.data(for: start)
        guard let uploadURL = (started as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-goog-upload-url").flatMap(URL.init) else {
            throw Failure.http(status: (started as? HTTPURLResponse)?.statusCode ?? 0, message: "the upload didn't start")
        }

        var send = URLRequest(url: uploadURL)
        send.httpMethod = "POST"
        send.timeoutInterval = 600
        send.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        send.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        let (body, _) = try await URLSession.shared.upload(for: send, from: data)
        guard var file = try? JSONDecoder().decode(UploadedFile.self, from: body).file else {
            throw Failure.http(status: 0, message: String(decoding: body.prefix(300), as: UTF8.self))
        }
        // A video is processed before it can be read.
        for _ in 0..<120 where file.state == "PROCESSING" {
            try await Task.sleep(for: .seconds(2))
            var check = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/\(file.name)")!)
            check.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            let (status, _) = try await URLSession.shared.data(for: check)
            file = try JSONDecoder().decode(UploadedFile.File.self, from: status)
        }
        guard file.state == "ACTIVE" else { throw Failure.noAnswer(reason: "the upload is \(file.state ?? "unknown")") }
        return .file(uri: file.uri, mimeType: file.mimeType ?? mimeType)
    }

    private struct UploadedFile: Decodable {
        struct File: Decodable {
            var name: String
            var uri: String
            var mimeType: String?
            var state: String?
        }
        var file: File
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

    private func post(_ body: [String: Any], timeout: Double = 30) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
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

    private struct GroundedAnswer: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { var text: String? }
                var parts: [Part]?
            }
            struct Metadata: Decodable {
                struct Chunk: Decodable {
                    struct Web: Decodable { var uri: String?; var title: String? }
                    var web: Web?
                }
                struct Support: Decodable {
                    struct Segment: Decodable { var text: String? }
                    var segment: Segment?
                    var groundingChunkIndices: [Int]?
                }
                var webSearchQueries: [String]?
                var groundingChunks: [Chunk]?
                var groundingSupports: [Support]?
            }
            var content: Content?
            var finishReason: String?
            var groundingMetadata: Metadata?
        }
        var candidates: [Candidate]?
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { var message: String }
        var error: Detail
    }
}

/// A plain-text answer written with Google Search, and the web pages behind it.
public struct Grounded: Sendable, Equatable {
    public struct Page: Sendable, Equatable {
        /// Usually the site's domain, such as "consumerfinance.gov".
        public var title: String
        public var url: String
    }

    /// A stretch of the answer and the pages (indexes into `pages`) that back it.
    public struct Support: Sendable, Equatable {
        public var text: String
        public var pages: [Int]
    }

    public var text: String
    /// What Gemini searched for.
    public var searches: [String]
    public var pages: [Page]
    public var supports: [Support]

    public init(text: String, searches: [String] = [], pages: [Page] = [], supports: [Support] = []) {
        self.text = text
        self.searches = searches
        self.pages = pages
        self.supports = supports
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
        // "$26,500" or "29.99%" sent as text.
        if case .text(let text)? = arguments[key] { return Double(text.filter { $0.isNumber || $0 == "." || $0 == "-" }) }
        return nil
    }

    public func numbers(_ key: String) -> [Double] {
        guard case .list(let values)? = arguments[key] else { return number(key).map { [$0] } ?? [] }
        return values.compactMap { value in
            switch value {
            case .number(let number): number
            case .text(let text): Double(text.filter { $0.isNumber || $0 == "." || $0 == "-" })
            default: nil
            }
        }
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
