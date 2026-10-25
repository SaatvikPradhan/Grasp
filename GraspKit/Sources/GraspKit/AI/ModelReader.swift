import Foundation

/// Reads the model a paper describes (its equation, constants and each condition's rate and
/// reported results) from the paper's lines, so Swift can run it. Gemini finds the numbers;
/// Swift keeps only the ones printed on the page.
public struct ModelReader: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
    }

    /// Nil when the paper has no model Swift knows how to run.
    public func read(paper lines: [String]) async throws -> PaperModel? {
        let raw = try await client.generate(Raw.self, prompt: Self.prompt(lines), schema: Self.schema)
        return Self.checked(raw, lines: lines)
    }

    struct Raw: Decodable {
        struct Number: Decodable {
            var value: Double
            var quote: String
        }

        struct Reported: Decodable {
            var kind: PaperModel.Reported.Kind
            var at: Double
            var value: Double
            var quote: String
        }

        struct Condition: Decodable {
            var name: String
            var k: Number
            var plusMinus: Double?
            var reported: [Reported]?
        }

        var kind: String
        var equationQuote: String?
        var timeUnit: String?
        var start: Number?
        var room: Number?
        var conditions: [Condition]?
    }

    /// Only numbers printed on the page survive; a condition whose rate isn't there is dropped.
    static func checked(_ raw: Raw, lines: [String]) -> PaperModel? {
        guard let kind = PaperModel.Kind(rawValue: raw.kind), let rawStart = raw.start else { return nil }
        func number(_ item: Raw.Number?) -> PaperModel.Number? {
            guard let item, PrintedNumber.line(of: item.value, in: lines) != nil else { return nil }
            return PaperModel.Number(value: item.value, cited: cite(item.quote, number: item.value, in: lines))
        }
        guard let start = number(rawStart) else { return nil }
        let room = number(raw.room)
        if kind == .newtonCooling, room == nil { return nil }
        let conditions = (raw.conditions ?? []).compactMap { condition -> PaperModel.Condition? in
            guard let k = number(condition.k), k.value > 0 else { return nil }
            let reported = (condition.reported ?? []).compactMap { item -> PaperModel.Reported? in
                guard PrintedNumber.line(of: item.value, in: lines) != nil,
                      PrintedNumber.line(of: item.at, in: lines) != nil else { return nil }
                return PaperModel.Reported(kind: item.kind, at: item.at, value: PaperModel.Number(
                    value: item.value, cited: cite(item.quote, number: item.value, in: lines)))
            }
            let spread = condition.plusMinus.flatMap { PrintedNumber.line(of: $0, in: lines) == nil ? nil : $0 }
            return PaperModel.Condition(name: condition.name, k: k, spread: spread, reported: reported)
        }
        guard !conditions.isEmpty else { return nil }
        let equation = raw.equationQuote ?? ""
        return PaperModel(kind: kind, equation: Cited(quote: equation, location: SourceLocator.locate(printed: nil, quote: equation, in: lines)),
                          timeUnit: raw.timeUnit ?? "min", start: start, room: room, conditions: conditions)
    }

    /// Where a number is: the line its quote names if the number is on it, otherwise the first line it's printed on.
    static func cite(_ quote: String, number: Double, in lines: [String]) -> Cited {
        if let location = SourceLocator.locate(printed: nil, quote: quote, in: lines),
           (location.line...(location.line + location.extraLines)).contains(where: { lines.indices.contains($0) && PrintedNumber.line(of: number, in: [lines[$0]]) != nil }) {
            return Cited(quote: quote, location: location)
        }
        guard let line = PrintedNumber.line(of: number, in: lines) else { return Cited(quote: quote, location: nil) }
        let text = lines[line]
        return Cited(quote: text, location: SourceLocator.Location(line: line, range: text.startIndex..<text.endIndex, extraLines: 0))
    }

    static func prompt(_ lines: [String]) -> String {
        """
        This is a paper's page, as read line by line. If it describes a model Swift can run, give it.
        kind: newton_cooling for a temperature relaxing toward the room (T = room + (start − room)·e^(−kt)); \
        exponential for a quantity decaying as start·e^(−kt); otherwise none.
        equation_quote: the equation or the sentence stating it, copied exactly.
        time_unit: the unit k is per (min, s or h).
        start: the starting value (for cooling, the starting temperature); room: the room temperature. Each \
        with value and quote, the quote copied exactly from the line it's on.
        conditions: every condition the paper reports a rate for (for example "Paper, no lid"). k is that \
        condition's rate as printed, plus_minus its ± if printed. reported lists results the paper gives for \
        that condition that its equation should reproduce: time_to (at is the value reached, value is the time \
        printed) or value_at (at is the time, value is the value printed). Copy every number exactly as printed; \
        never work one out.

        \(lines.joined(separator: "\n").prefix(8_000))
        """
    }

    static let number: [String: Any] = [
        "type": "OBJECT",
        "properties": ["value": ["type": "NUMBER"], "quote": ["type": "STRING"]],
        "required": ["value", "quote"],
    ]

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "kind": ["type": "STRING", "enum": ["newton_cooling", "exponential", "none"]],
            "equation_quote": ["type": "STRING", "nullable": true],
            "time_unit": ["type": "STRING", "enum": ["min", "s", "h"], "nullable": true],
            "start": number.merging(["nullable": true]) { $1 },
            "room": number.merging(["nullable": true]) { $1 },
            "conditions": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "name": ["type": "STRING"],
                        "k": number,
                        "plus_minus": ["type": "NUMBER", "nullable": true],
                        "reported": [
                            "type": "ARRAY",
                            "items": [
                                "type": "OBJECT",
                                "properties": [
                                    "kind": ["type": "STRING", "enum": ["time_to", "value_at"]],
                                    "at": ["type": "NUMBER"],
                                    "value": ["type": "NUMBER"],
                                    "quote": ["type": "STRING"],
                                ],
                                "required": ["kind", "at", "value", "quote"],
                            ],
                        ],
                    ],
                    "required": ["name", "k", "plus_minus", "reported"],
                ],
            ],
        ],
        "required": ["kind", "equation_quote", "time_unit", "start", "room", "conditions"],
    ]
}
