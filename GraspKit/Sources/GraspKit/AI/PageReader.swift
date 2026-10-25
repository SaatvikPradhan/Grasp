import Foundation

/// Reads any page (a lease, a bill, a loan, a phone plan, a paper) into a `PageReading`.
public struct PageReader: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
    }

    public func read(jpeg: Data) async throws -> PageReading {
        // A second look at the same time, only at the arithmetic, so fewer sums slip by.
        async let arithmetic = try? client.generate(Arithmetic.self, prompt: Self.arithmeticPrompt, jpeg: jpeg, schema: Self.arithmeticSchema)
        var page = try await client.generate(PageReading.self, prompt: Self.prompt, jpeg: jpeg, schema: Self.schema)
        page.relations = (page.relations ?? []) + (await arithmetic?.relations ?? [])
        return page
    }

    struct Arithmetic: Decodable {
        var relations: [PageReading.Relation]
    }

    static let prompt = """
    Read this page for someone who won't read all of it.
    kind: what the page is, in a few words. title: a short name. summary: one plain sentence on what it means for the reader.
    facts: the numbers that matter most, up to 12: prices, rates, fees, totals, and lengths of time (the contract \
    or loan length, how long a promotion lasts) as their own facts. key is a short snake_case name. as_printed is copied exactly. \
    value is the plain number (8.9 for 8.90%, 85 for $85.00, negative for a discount). quote is a few words copied \
    exactly from the page, from the same line as the number, so it can be found on the photo.
    catches: anything that could cost the reader money or lock them in (fees, price or rate increases, promotions \
    ending, balances that come due, auto-renewal, deferred interest, penalties, arbitration), and anything the page \
    contradicts itself on (a promotional price it shows but doesn't charge, a late fee on a payment made before the \
    due date, something charged or withheld that the page's own fine print says may not apply to the reader, a \
    headline such as "$0 annual fee" or "fully covered" that the details take back), up to 6, most \
    costly first. explanation is one plain sentence. quote is copied exactly from the page. cost is the dollars at stake if the page says.
    model: which one fits, with numbers copied from your facts (never computed). installment_loan for money \
    borrowed and repaid monthly (principal, apr_percent, months). recurring_cost for a monthly price over time; \
    use it when the page is mainly a monthly service, even if a device is financed alongside (monthly_price is \
    the regular plan price, promo_price and promo_months if it starts cheaper, months is the contract length, \
    extra_monthly lists other monthly lines such as a device payment, negative for a discount, upfront lists \
    one-time charges paid at the start, not penalties such as late fees). breakdown for a list of charges. Otherwise none.
    relations: the page's arithmetic, so Swift can check it. \(relationsGuide)
    """

    static let relationsGuide = """
    List every one: each total or subtotal (sum of the lines it totals, a discount or credit negative); a net amount (sum: the gross, then each deduction negative); \
    hours × rate, quantity × price, or a total for a term such as 12 months at a monthly rent (product of the two); \
    and one percent_of for every line whose label has a percentage, such as each tax line marked (6.2%) or (1.45%) \
    taken from gross pay (inputs are the percent as printed, then the amount it's a percentage of). label is the \
    result's name as printed ("Total new charges", "Social Security"). stated is the printed result. Each \
    input is one number copied exactly from the line its label names, even when the result then looks wrong. \
    Never adjust a number to make it add up: the point is to catch the page's own mistakes.
    """

    static let arithmeticPrompt = """
    relations: the arithmetic printed on this page, so Swift can check it. \(relationsGuide)
    """

    static let relationSchema: [String: Any] = [
        "type": "ARRAY",
        "items": [
            "type": "OBJECT",
            "properties": [
                "label": ["type": "STRING"],
                "kind": ["type": "STRING", "enum": ["sum", "product", "percent_of"]],
                "stated": ["type": "NUMBER"],
                "inputs": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": ["label": ["type": "STRING"], "value": ["type": "NUMBER"]],
                        "required": ["label", "value"],
                    ],
                ],
            ],
            "required": ["label", "kind", "stated", "inputs"],
        ],
    ]

    static let arithmeticSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": ["relations": relationSchema],
        "required": ["relations"],
    ]

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
            "relations": relationSchema,
        ],
        "required": ["kind", "title", "summary", "facts", "catches", "model", "relations"],
    ]
}
