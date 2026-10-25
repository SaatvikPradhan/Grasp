import Foundation

/// What to say at the dealership: a few lines for the card and a short spoken version.
public struct Advice: Equatable, Sendable {
    /// Up to three things to say to the dealer.
    public var lines: [String]
    /// What Grasp says out loud to the buyer.
    public var spoken: String
    /// False when these are the plain talking points (no key, an error, or a number that didn't check out).
    public var isFromAI: Bool

    public init(lines: [String], spoken: String, isFromAI: Bool) {
        self.lines = lines
        self.spoken = spoken
        self.isFromAI = isFromAI
    }
}

/// Has Gemini phrase the talking points naturally. It may only use numbers Swift computed:
/// if any number in its answer isn't one of ours, the plain talking points are used instead.
public struct AdviceWriter: Sendable {
    public var client: GeminiClient?

    public init(client: GeminiClient?) {
        self.client = client
    }

    public func write(for facts: MoneyFacts) async -> Advice {
        let points = Array(facts.talkingPoints().prefix(3))
        let fallback = Advice(
            lines: points,
            spoken: points.isEmpty ? "Scan the contract first, and I'll tell you what to ask." : "Here's what to ask. " + points.joined(separator: " "),
            isFromAI: false
        )
        guard let client, !points.isEmpty else { return fallback }

        let prompt = """
        You are Grasp, helping someone at a car dealership decide what to say. These facts were \
        computed exactly; never change, round or add a number.
        \(facts.factSheet)

        Suggested points, most valuable first:
        \(points.map { "- " + $0 }.joined(separator: "\n"))

        Write:
        lines: up to 3 things the buyer can say to the dealer, first person, each under 16 words, \
        keeping the numbers exactly as given.
        spoken: 2 or 3 calm sentences Grasp says out loud to the buyer (not to the dealer), under \
        45 words, using only numbers from the facts.
        """
        do {
            let draft = try await client.generate(Draft.self, prompt: prompt, schema: Self.schema)
            let used = Set(MoneyFacts.numbers(in: (draft.lines + [draft.spoken]).joined(separator: " ")))
            guard !draft.lines.isEmpty, !draft.spoken.isEmpty, used.isSubset(of: facts.knownNumbers) else { return fallback }
            return Advice(lines: Array(draft.lines.prefix(3)), spoken: draft.spoken, isFromAI: true)
        } catch {
            return fallback
        }
    }

    private struct Draft: Decodable {
        var lines: [String]
        var spoken: String
    }

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "lines": ["type": "ARRAY", "items": ["type": "STRING"]],
            "spoken": ["type": "STRING"],
        ],
        "required": ["lines", "spoken"],
    ]
}
