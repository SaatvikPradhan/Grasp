import Foundation

/// A paper's method as a map: the question, what was varied, what was measured, what was held
/// the same, what wasn't controlled, how it was analysed and how many trials. Every box keeps the
/// paper's words; something not controlled that the paper never mentions is marked as Grasp's
/// suggestion, not the paper's.
public struct MethodMap: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var name: String
        /// Levels of a variable, how a measure was taken, why something matters.
        public var detail: String?
        /// Where the paper says it; nil only for something not controlled that the paper doesn't mention.
        public var cited: Cited?
    }

    public var question: Item?
    public var varied: [Item]
    public var measured: [Item]
    public var controlled: [Item]
    public var notControlled: [Item]
    public var analysis: Item?
    public var trials: Item?

    /// Every item in a fixed order, for numbering what each one cites.
    public var items: [Item] {
        [question].compactMap { $0 } + varied + measured + [analysis, trials].compactMap { $0 } + controlled + notControlled
    }
}

public struct MethodReader: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
    }

    public func read(paper lines: [String]) async throws -> MethodMap {
        let raw = try await client.generate(Raw.self, prompt: Self.prompt(lines), schema: Self.schema)
        return Self.checked(raw, lines: lines)
    }

    struct Raw: Decodable {
        struct Item: Decodable {
            var name: String
            var detail: String?
            var quote: String?
        }

        var question: Item?
        var varied: [Item]
        var measured: [Item]
        var controlled: [Item]
        var notControlled: [Item]
        var analysis: Item?
        var trials: Item?
    }

    /// Keeps a box only if its words are in the paper, and a trial count only if it's printed.
    static func checked(_ raw: Raw, lines: [String]) -> MethodMap {
        func found(_ item: Raw.Item?) -> MethodMap.Item? {
            guard let item, let quote = item.quote, !quote.isEmpty,
                  let location = SourceLocator.locate(printed: nil, quote: quote, in: lines) else { return nil }
            return MethodMap.Item(name: item.name, detail: item.detail, cited: Cited(quote: quote, location: location))
        }
        let trials = found(raw.trials).flatMap { item in
            MoneyFacts.numbers(in: item.name).allSatisfy { number in Double(number).map { PrintedNumber.line(of: $0, in: lines) != nil } ?? false }
                ? item : nil
        }
        // Something not controlled may be the reader's point rather than the paper's: kept, marked by having no
        // quote. Before saying the paper doesn't mention it, look for its own words on the page.
        let notControlled = raw.notControlled.prefix(4).map { item in
            if let cited = found(item) { return cited }
            let words = item.name + " " + (item.detail ?? "")
            if let location = SourceLocator.locate(printed: nil, quote: words, in: lines) {
                return MethodMap.Item(name: item.name, detail: item.detail, cited: Cited(quote: lines[location.line], location: location))
            }
            return MethodMap.Item(name: item.name, detail: item.detail, cited: nil)
        }
        return MethodMap(question: found(raw.question), varied: raw.varied.compactMap(found), measured: raw.measured.compactMap(found),
                         controlled: raw.controlled.compactMap(found), notControlled: Array(notControlled),
                         analysis: found(raw.analysis), trials: trials)
    }

    static func prompt(_ lines: [String]) -> String {
        """
        This is a paper's page, read line by line. Map its method for someone checking how the study was done.
        question: what the study asks, as a short question. varied: each thing the authors changed on purpose, \
        detail = its levels ("open, lid"). measured: each thing measured, detail = how. controlled: each thing \
        held the same, detail = at what. not_controlled: up to 4 things that could change the result but weren't \
        controlled or measured (the paper's own limitations first, then anything else a careful reader would ask \
        about), detail = why it matters. analysis: how the results were worked out. trials: how many trials, name \
        as printed ("12 trials per condition"). Each item's name is a few words; quote is the sentence or phrase \
        it comes from, copied exactly from the page; leave quote empty for something not controlled that the page \
        doesn't mention.

        \(lines.joined(separator: "\n").prefix(8_000))
        """
    }

    static let item: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "name": ["type": "STRING"],
            "detail": ["type": "STRING", "nullable": true],
            "quote": ["type": "STRING", "nullable": true],
        ],
        "required": ["name", "detail", "quote"],
    ]

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "question": item.merging(["nullable": true]) { $1 },
            "varied": ["type": "ARRAY", "items": item],
            "measured": ["type": "ARRAY", "items": item],
            "controlled": ["type": "ARRAY", "items": item],
            "not_controlled": ["type": "ARRAY", "items": item],
            "analysis": item.merging(["nullable": true]) { $1 },
            "trials": item.merging(["nullable": true]) { $1 },
        ],
        "required": ["question", "varied", "measured", "controlled", "not_controlled", "analysis", "trials"],
    ]
}
