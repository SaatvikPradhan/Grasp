import Foundation

/// A letter disputing a bill, ready to send: each problem with the bill's own words and an amount
/// Swift worked out from numbers printed on it, the total to get back, and Gemini's wording around
/// them. Any number in the wording must be on the bill.
public struct DisputeLetter: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var title: String
        /// One sentence: what's wrong.
        public var reason: String
        public var amount: Double
        /// How Swift got the amount: "$145.32 − $135.32".
        public var math: String
        public var cited: Cited?
    }

    public var company: String
    public var account: String?
    public var name: String?
    public var subject: String
    public var opening: String
    public var items: [Item]
    /// Charges that aren't errors but deserve an explanation; not part of the total.
    public var questions: [Item]
    public var closing: String

    public var total: Double { (items.map(\.amount).reduce(0, +) * 100).rounded() / 100 }

    /// The whole letter, as it would be sent.
    public var text: String {
        var lines = ["To: \(company)", "Re: \(subject)" + (account.map { " · Account \($0)" } ?? ""), "", opening, ""]
        for (index, item) in items.enumerated() {
            lines.append("\(index + 1). \(item.title): \(item.reason) Amount: \(Self.money(item.amount))."
                         + (item.cited.map { " The bill says: \u{201C}\($0.quote)\u{201D}" } ?? ""))
        }
        lines += ["", "In total, I'm asking for a credit of \(Self.money(total)) on this bill."]
        if !questions.isEmpty {
            lines += ["", "I'd also like an explanation of " + questions.map { "the \($0.title.lowercased()) (\(Self.money($0.amount)))" }
                .joined(separator: " and ") + "."]
        }
        lines += ["", closing, "", name ?? "[Your name]"]
        return lines.joined(separator: "\n")
    }

    static func money(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }
}

public struct DisputeWriter: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
        self.client.thinkingLevel = "low"
    }

    /// Nil when nothing on the page can be disputed with numbers printed on it.
    public func write(_ reading: PageReading) async throws -> DisputeLetter? {
        let lines = reading.lines ?? []
        let raw = try await client.generate(Raw.self, prompt: Self.prompt(reading, lines: lines), schema: Self.schema)
        return Self.checked(raw, reading: reading)
    }

    struct Raw: Decodable {
        struct Item: Decodable {
            var title: String
            var reason: String
            var verdict: String
            var charged: Double?
            var shouldBe: Double?
            var quote: String?
        }

        var company: String
        var accountNumber: String?
        var customerName: String?
        var subject: String
        var opening: String
        var closing: String
        var charges: [Item]
    }

    static func checked(_ raw: Raw, reading: PageReading) -> DisputeLetter? {
        let lines = reading.lines ?? []
        let page = lines.joined(separator: "\n")
        func printed(_ value: Double?) -> Bool { value.map { PrintedNumber.line(of: $0, in: lines) != nil } ?? false }
        func cite(_ quote: String?) -> Cited? {
            guard let quote, !quote.isEmpty, let location = SourceLocator.locate(printed: nil, quote: quote, in: lines) else { return nil }
            return Cited(quote: quote, location: location)
        }
        let money = DisputeLetter.money

        // Totals that don't add up: Swift found these, and only the overcharged ones go in a dispute.
        var items = reading.mismatches.filter { $0.difference > 0.005 }.map { mismatch in
            let stated = reading.spot(of: mismatch.relation.stated)
            return DisputeLetter.Item(
                title: "\(mismatch.relation.label) doesn't add up",
                reason: "The charges listed add up to \(money(mismatch.expected)), but the bill says \(money(mismatch.relation.stated)).",
                amount: (mismatch.difference * 100).rounded() / 100,
                math: "\(money(mismatch.relation.stated)) − \(money(mismatch.expected))",
                cited: stated.flatMap { spot in cite(spot.quote) ?? Cited(quote: spot.quote, location: nil) })
        }
        // The rest from Gemini's verdict on every charge, kept only when every number is printed on the bill.
        var questions: [DisputeLetter.Item] = []
        for item in raw.charges {
            switch item.verdict {
            case "price_not_applied":
                guard let charged = item.charged, let shouldBe = item.shouldBe, printed(charged), printed(shouldBe), charged > shouldBe else { continue }
                items.append(.init(title: item.title, reason: item.reason, amount: ((charged - shouldBe) * 100).rounded() / 100,
                                   math: "\(money(charged)) − \(money(shouldBe))", cited: cite(item.quote)))
            case "fee_not_owed":
                guard let charged = item.charged, printed(charged), charged > 0 else { continue }
                items.append(.init(title: item.title, reason: item.reason, amount: charged, math: money(charged), cited: cite(item.quote)))
            case "worth_asking":
                guard let charged = item.charged, printed(charged), charged > 0 else { continue }
                questions.append(.init(title: item.title, reason: item.reason, amount: charged, math: money(charged), cited: cite(item.quote)))
            default:
                continue
            }
        }
        guard !items.isEmpty else { return nil }

        // Wording with a number not on the bill is replaced with plain wording.
        let known = Set(MoneyFacts.numbers(in: page))
        func plain(_ text: String, otherwise fallback: String) -> String {
            Set(MoneyFacts.numbers(in: text)).isSubset(of: known) ? text : fallback
        }
        let company = page.localizedCaseInsensitiveContains(raw.company) ? raw.company : "Customer service"
        return DisputeLetter(
            company: company,
            account: raw.accountNumber.flatMap { page.contains($0) ? $0 : nil },
            name: raw.customerName.flatMap { page.contains($0) ? $0 : nil },
            subject: plain(raw.subject, otherwise: "Charges on my bill"),
            opening: plain(raw.opening, otherwise: "I'm writing about charges on my latest bill that I believe are wrong."),
            items: items,
            questions: Array(questions.prefix(2)),
            closing: plain(raw.closing, otherwise: "Please credit these amounts and send a corrected bill. Thank you."))
    }

    static func prompt(_ reading: PageReading, lines: [String]) -> String {
        """
        Help the person who got this bill dispute the charges that are wrong. Grasp has already checked the \
        arithmetic and will list any total that doesn't add up itself, so don't include those.
        charges: every charge line on the bill, each with a verdict. price_not_applied when the bill states a \
        lower price that applies to the reader but charges a higher one (charged and should_be, as printed). \
        fee_not_owed when the bill's own words show the charge shouldn't apply: check every late fee against the \
        payment date and the due date printed on the bill. worth_asking when it's allowed but deserves an \
        explanation (a fee the company adds itself, an add-on the reader may not have asked for). correct \
        otherwise. charged is the amount as printed; title is a few words; reason is one plain sentence citing \
        what the bill says; quote is the charge's line copied exactly.
        company, account_number and customer_name exactly as printed, if they are. subject is a few words. \
        opening is two sentences introducing the letter; closing is one or two sentences asking for a credit \
        and a corrected bill. Polite and firm; no amounts in the opening or closing.

        Catches Grasp found: \(reading.allCatches.map { "\($0.title): \($0.explanation)" }.joined(separator: "; "))

        The bill, as read from its page:
        \(lines.joined(separator: "\n").prefix(6_000))
        """
    }

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "company": ["type": "STRING"],
            "account_number": ["type": "STRING", "nullable": true],
            "customer_name": ["type": "STRING", "nullable": true],
            "subject": ["type": "STRING"],
            "opening": ["type": "STRING"],
            "closing": ["type": "STRING"],
            "charges": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "title": ["type": "STRING"],
                        "reason": ["type": "STRING"],
                        "verdict": ["type": "STRING", "enum": ["correct", "price_not_applied", "fee_not_owed", "worth_asking"]],
                        "charged": ["type": "NUMBER", "nullable": true],
                        "should_be": ["type": "NUMBER", "nullable": true],
                        "quote": ["type": "STRING", "nullable": true],
                    ],
                    "required": ["title", "reason", "verdict", "charged", "should_be", "quote"],
                ],
            ],
        ],
        "required": ["company", "account_number", "customer_name", "subject", "opening", "closing", "charges"],
    ]
}
