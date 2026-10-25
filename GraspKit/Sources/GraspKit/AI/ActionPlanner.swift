import Foundation

/// What to do about a page: how it compares with what's typical right now (from the web, each line
/// with its sources), the steps that fix what Grasp found wrong on it (each tied to its catch, with
/// the page's own amounts), and what it comes to. A deep dive with steps.
public struct ActionPlanner: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
        self.client.thinkingLevel = "low"
    }

    /// Pages worth a plan: ones with money on them.
    public static func isWorthPlanning(_ reading: PageReading) -> Bool {
        !reading.mismatches.isEmpty || reading.facts.contains { $0.unit == .dollars }
    }

    /// Two asks at once: the web, for what's typical right now (each line must have a page behind
    /// it), and the page, for the steps that fix what's wrong with it.
    public func plan(_ reading: PageReading) async throws -> DeepDive {
        async let market = client.searchGrounded(Self.marketPrompt(reading))
        async let steps = client.generate(Raw.self, prompt: Self.stepsPrompt(reading), schema: Self.schema)
        return Self.checked(market: try await market, steps: try await steps, reading: reading)
    }

    struct Raw: Decodable {
        struct Step: Decodable {
            /// The problem it fixes, from 1, or nil.
            var problem: Int?
            var text: String
        }

        var steps: [Step]
        var bottomLine: String
    }

    /// The problems Grasp found, numbered as the steps refer to them: catches, with Swift's own
    /// arithmetic for anything that doesn't add up.
    static func problems(_ reading: PageReading) -> [String] {
        reading.allCatches.map { item in
            if let mismatch = reading.mismatches.first(where: { item.title.contains($0.relation.label) }) {
                let stated = money(mismatch.relation.stated), expected = money(mismatch.expected)
                return "\(item.title): the page says \(stated), but its own lines add up to \(expected) (\(money(abs(mismatch.difference))) "
                    + (mismatch.difference > 0 ? "too much)" : "too little)")
            }
            return "\(item.title): \(item.explanation)"
        }
    }

    static func marketPrompt(_ reading: PageReading) -> String {
        let prices = reading.facts.filter { $0.unit == .dollars || $0.unit == .percent }.prefix(8)
            .map { "\($0.label): \($0.asPrinted)" }.joined(separator: "; ")
        return """
            Search the web for what this costs elsewhere right now, so someone can tell whether they're getting a \
            fair deal: \(reading.kind), "\(reading.title)". What it charges: \(prices). \(reading.summary)
            Compare with the same kind of thing (the same kind of plan, product, loan, rent, fee or pay, in the same \
            area if the page says where) from other companies or typical rates.
            Write 2 or 3 findings, each on its own line starting with "- ", with real numbers and ranges from \
            reliable, current sources. No headings, no introduction.
            """
    }

    static func stepsPrompt(_ reading: PageReading) -> String {
        let facts = reading.facts.prefix(12).map { "\($0.label): \($0.asPrinted)" }.joined(separator: "; ")
        let problems = problems(reading).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return """
            Someone handed Grasp this page. Tell them what to do about it.
            The page: \(reading.title) (\(reading.kind)). \(reading.summary)
            Its numbers: \(facts)
            Problems Grasp found on it:
            \(problems.isEmpty ? "none" : problems)
            The page as read: \((reading.lines ?? []).joined(separator: " | ").prefix(4_000))

            steps: 3 to 5 concrete steps, most valuable first: fixing each problem (problem = its number above), then \
            anything else on the page worth changing (problem = null). One or two plain sentences each, using the \
            page's own amounts and saying who to contact and what to ask for.
            bottom_line: one sentence on what it comes to, such as how much they could get back or save.
            """
    }

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "steps": ["type": "ARRAY", "items": [
                "type": "OBJECT",
                "properties": ["problem": ["type": "INTEGER", "nullable": true], "text": ["type": "STRING"]],
                "required": ["problem", "text"],
            ]],
            "bottom_line": ["type": "STRING"],
        ],
        "required": ["steps", "bottom_line"],
    ]

    static func checked(market: Grounded, steps raw: Raw, reading: PageReading) -> DeepDive {
        // What's typical comes from the web, so each line has to have a page behind it.
        let compared = DeepDiveFinder.checked(market)
        let findings = compared.sources.isEmpty ? [] : compared.findings.filter { !$0.sources.isEmpty }
        // Amounts Grasp knows: printed on the page, or its own arithmetic.
        var known = (reading.lines ?? []) + reading.facts.map(\.asPrinted)
        known += reading.mismatches.flatMap { [money($0.expected), money(abs($0.difference))] }
        let catches = reading.allCatches
        let steps = raw.steps.prefix(5).map { step in
            let numbers = MoneyFacts.numbers(in: step.text).compactMap(Double.init)
            return DeepDive.Step(text: step.text, sources: [],
                                 catchIndex: step.problem.flatMap { catches.indices.contains($0 - 1) ? $0 - 1 : nil },
                                 numbersChecked: numbers.allSatisfy { PrintedNumber.line(of: $0, in: known) != nil })
        }
        var plan = DeepDive(findings: Array(findings.prefix(3)), steps: Array(steps), bottomLine: raw.bottomLine,
                            sources: compared.sources, searches: compared.searches)
        plan.bottomLineMath = math(of: raw.bottomLine, from: steps.filter(\.numbersChecked).map(\.text))
        return plan
    }

    /// How the bottom line's amount comes from amounts in the steps, worked out in Swift: the fewest
    /// of them that add up to it, "$10.00 + $25.00 + $7.00". Nil when it has no amount or they don't.
    static func math(of bottomLine: String, from steps: [String]) -> String? {
        guard let target = MoneyFacts.numbers(in: bottomLine).compactMap(Double.init).max(), target > 0 else { return nil }
        let amounts = Array(Set(steps.flatMap { MoneyFacts.numbers(in: $0).compactMap(Double.init) }.filter { $0 > 0 && $0 <= target }))
            .sorted().prefix(14)
        var best: [Double]?
        for mask in 1..<(1 << amounts.count) {
            let picked = amounts.indices.filter { mask & (1 << $0) != 0 }.map { amounts[$0] }
            guard picked.count <= 6, abs(picked.reduce(0, +) - target) < 0.005 else { continue }
            if best == nil || picked.count < best!.count { best = picked }
        }
        return best.map { $0.sorted(by: >).map(money).joined(separator: " + ") }
    }

    static func money(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }
}
