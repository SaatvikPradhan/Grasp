import Foundation

/// A video Grasp has watched: what's said when, the moments worth jumping to, and the facts in
/// it, each tied to the moment it's said. Times are seconds from the start.
public struct VideoReading: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var seconds: Double
        public var text: String
    }

    public struct Moment: Equatable, Sendable {
        public var seconds: Double
        public var title: String
        /// Why it matters, in a sentence.
        public var why: String
    }

    public var kind: String
    public var title: String
    public var summary: String
    public var transcript: [Line]
    public var moments: [Moment]
    /// Each with the exact words said, which are on a transcript line.
    public var facts: [PageReading.Fact]

    /// The transcript as page lines, each with its time in front: "[0:31] For an open paper cup…".
    public var lines: [String] { transcript.map { "[\(Self.clock($0.seconds))] \($0.text)" } }

    /// The video as a page, so everything that reads pages (Ask, notes, deep dives) reads it too.
    public var page: PageReading {
        var reading = PageReading(kind: kind, title: title, summary: summary, facts: facts, catches: [], model: .init(type: .none))
        reading.lines = lines
        return reading
    }

    /// When the line with these words is said, if they're in the transcript.
    public func seconds(of quote: String) -> Double? {
        SourceLocator.locate(printed: nil, quote: quote, in: transcript.map(\.text)).map { transcript[$0.line].seconds }
    }

    /// "1:05", or "1:02:05" past an hour.
    public static func clock(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let (hours, minutes, rest) = (total / 3600, total % 3600 / 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// Reads "1:05", "01:02:05", "65" or "65s".
    public static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "s[]")).split(separator: ":")
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count else { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }
}

/// Watches a video with Gemini: a timestamped transcript, the key moments, and the facts said.
/// Swift keeps a fact only if its words are on a transcript line and its number is in them, so
/// every fact can jump to the moment it's said.
public struct VideoReader: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
        self.client.thinkingLevel = "low"
    }

    /// `duration` is the video's length when known, to drop times past the end.
    public func read(_ video: GeminiClient.Media, duration: Double? = nil) async throws -> VideoReading {
        let raw = try await client.generate(Raw.self, prompt: Self.prompt, media: [video], schema: Self.schema)
        return Self.checked(raw, duration: duration)
    }

    struct Raw: Decodable {
        struct Line: Decodable {
            var at: String
            var text: String
        }

        struct Moment: Decodable {
            var at: String
            var title: String
            var why: String
        }

        struct Fact: Decodable {
            var label: String
            var value: String
            var number: Double?
            var unit: PageReading.Fact.Unit?
            var quote: String
        }

        var kind: String
        var title: String
        var summary: String
        var transcript: [Line]
        var moments: [Moment]
        var facts: [Fact]
    }

    static func checked(_ raw: Raw, duration: Double?) -> VideoReading {
        let end = (duration ?? .infinity) + 5
        let transcript = raw.transcript.compactMap { line -> VideoReading.Line? in
            guard let seconds = VideoReading.seconds(line.at), seconds <= end else { return nil }
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : .init(seconds: seconds, text: text)
        }
        .sorted { $0.seconds < $1.seconds }
        let moments = raw.moments.compactMap { moment -> VideoReading.Moment? in
            guard let seconds = VideoReading.seconds(moment.at), seconds <= end else { return nil }
            return .init(seconds: seconds, title: moment.title, why: moment.why)
        }
        .sorted { $0.seconds < $1.seconds }
        let texts = transcript.map(\.text)
        let facts = raw.facts.enumerated().compactMap { index, fact -> PageReading.Fact? in
            guard let found = SourceLocator.locate(printed: nil, quote: fact.quote, in: texts) else { return nil }
            if let number = fact.number, PrintedNumber.line(of: number, in: [texts[found.line]]) == nil,
               PrintedNumber.line(of: number, in: [fact.quote]) == nil {
                return nil
            }
            return PageReading.Fact(key: "v\(index)", label: fact.label, asPrinted: fact.value, value: fact.number,
                                    unit: fact.unit ?? .text, quote: fact.quote)
        }
        return VideoReading(kind: raw.kind, title: raw.title, summary: raw.summary, transcript: transcript,
                            moments: Array(moments.prefix(8)), facts: Array(facts.prefix(10)))
    }

    static let prompt = """
        Watch this video for someone studying it.
        transcript: everything said, in order, one entry per sentence, each with at = when that sentence starts \
        (m:ss, or h:mm:ss past an hour) and text = the words exactly as said, with numbers as digits.
        moments: 3 to 8 moments worth jumping back to (a definition, an equation, a key result, an example, \
        an assignment), each with at, a title of a few words, and why it matters in one sentence.
        facts: up to 10 numbers, results and definitions said, each with a short label, value as said \
        ("0.031 per minute"), number when it's a number, unit, and quote = the words from the transcript \
        that say it, copied exactly.
        kind: what this is in a few words ("physics lecture"). title: its title, as shown or said. \
        summary: one plain sentence.
        """

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "kind": ["type": "STRING"],
            "title": ["type": "STRING"],
            "summary": ["type": "STRING"],
            "transcript": ["type": "ARRAY", "items": [
                "type": "OBJECT",
                "properties": ["at": ["type": "STRING"], "text": ["type": "STRING"]],
                "required": ["at", "text"],
            ]],
            "moments": ["type": "ARRAY", "items": [
                "type": "OBJECT",
                "properties": ["at": ["type": "STRING"], "title": ["type": "STRING"], "why": ["type": "STRING"]],
                "required": ["at", "title", "why"],
            ]],
            "facts": ["type": "ARRAY", "items": [
                "type": "OBJECT",
                "properties": [
                    "label": ["type": "STRING"],
                    "value": ["type": "STRING"],
                    "number": ["type": "NUMBER", "nullable": true],
                    "unit": ["type": "STRING", "nullable": true,
                             "enum": ["dollars", "percent", "months", "years", "days", "count", "number", "date", "text"]],
                    "quote": ["type": "STRING"],
                ],
                "required": ["label", "value", "number", "unit", "quote"],
            ]],
        ],
        "required": ["kind", "title", "summary", "transcript", "moments", "facts"],
    ]
}
