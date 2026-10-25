import Foundation

/// Reads any page (a lease, a bill, a loan, a phone plan, a paper) into a `PageReading`.
public struct PageReader: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
    }

    public func read(jpeg: Data) async throws -> PageReading {
        try await client.generate(PageReading.self, prompt: Self.prompt, jpeg: jpeg, schema: Self.schema)
    }

    static let prompt = """
    Read this page for someone who won't read all of it.
    kind: what the page is, in a few words. title: a short name. summary: one plain sentence on what it means for the reader.
    facts: the numbers that matter most, up to 12: prices, rates, fees, totals, and lengths of time (the contract \
    or loan length, how long a promotion lasts) as their own facts. key is a short snake_case name. as_printed is copied exactly. \
    value is the plain number (8.9 for 8.90%, 85 for $85.00, negative for a discount). quote is a few words copied \
    exactly from the page, from the same line as the number, so it can be found on the photo.
    catches: anything that could cost the reader money or lock them in (fees, price or rate increases, promotions \
    ending, balances that come due, auto-renewal, deferred interest, penalties, arbitration), up to 5, most costly \
    first. explanation is one plain sentence. quote is copied exactly from the page. cost is the dollars at stake if the page says.
    model: which one fits, with numbers copied from your facts (never computed). installment_loan for money \
    borrowed and repaid monthly (principal, apr_percent, months). recurring_cost for a monthly price over time; \
    use it when the page is mainly a monthly service, even if a device is financed alongside (monthly_price is \
    the regular plan price, promo_price and promo_months if it starts cheaper, months is the contract length, \
    extra_monthly lists other monthly lines such as a device payment, negative for a discount, upfront lists \
    one-time charges paid at the start, not penalties such as late fees). breakdown for a list of charges. Otherwise none.
    """

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "kind": ["type": "STRING"],
            "title": ["type": "STRING"],
            "summary": ["type": "STRING"],
            "facts": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "key": ["type": "STRING"],
                        "label": ["type": "STRING"],
                        "as_printed": ["type": "STRING"],
                        "value": ["type": "NUMBER", "nullable": true],
                        "unit": ["type": "STRING", "enum": ["dollars", "percent", "months", "years", "days", "count", "number", "date", "text"]],
                        "quote": ["type": "STRING"],
                    ],
                    "required": ["key", "label", "as_printed", "unit", "quote"],
                ],
            ],
            "catches": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "title": ["type": "STRING"],
                        "explanation": ["type": "STRING"],
                        "quote": ["type": "STRING"],
                        "severity": ["type": "STRING", "enum": ["high", "medium", "low"]],
                        "cost": ["type": "NUMBER", "nullable": true],
                    ],
                    "required": ["title", "explanation", "quote", "severity"],
                ],
            ],
            "model": [
                "type": "OBJECT",
                "properties": [
                    "type": ["type": "STRING", "enum": ["installment_loan", "recurring_cost", "breakdown", "none"]],
                    "principal": ["type": "NUMBER", "nullable": true],
                    "apr_percent": ["type": "NUMBER", "nullable": true],
                    "months": ["type": "NUMBER", "nullable": true],
                    "monthly_price": ["type": "NUMBER", "nullable": true],
                    "promo_price": ["type": "NUMBER", "nullable": true],
                    "promo_months": ["type": "NUMBER", "nullable": true],
                    "extra_monthly": ["type": "ARRAY", "items": ["type": "NUMBER"]],
                    "upfront": ["type": "ARRAY", "items": ["type": "NUMBER"]],
                ],
                "required": ["type"],
            ],
        ],
        "required": ["kind", "title", "summary", "facts", "catches", "model"],
    ]
}
