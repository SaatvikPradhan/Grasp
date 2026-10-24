import Foundation

/// Reads a photo of a car contract, window sticker or loan quote into an `OfferReading`.
public struct OfferReader: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
    }

    public func read(jpeg: Data) async throws -> OfferReading {
        try await client.generate(OfferReading.self, prompt: Self.prompt, jpeg: jpeg, schema: Self.schema)
    }

    static let prompt = """
    Read this car purchase document. Copy numbers exactly as printed; do not calculate anything.
    document_type: loan_contract for a signed or unsigned financing contract, window_sticker for a \
    price sticker or dealer add-on sticker, loan_quote for a lender's pre-approval or rate quote, otherwise other.
    fees: every itemized charge other than the cash price and the down payment. is_addon is true for \
    optional dealer extras (paint or fabric protection, nitrogen tires, VIN etching, service contracts, \
    GAP that was purchased) and false for tax, title, registration and documentary fees.
    apr_percent is the annual percentage rate as printed, for example 8.9 for 8.90%.
    Use null for any value that is not on the page.
    """

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "document_type": ["type": "STRING", "enum": ["loan_contract", "window_sticker", "loan_quote", "other"]],
            "cash_price": ["type": "NUMBER", "nullable": true],
            "fees": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "name": ["type": "STRING"],
                        "amount": ["type": "NUMBER"],
                        "is_addon": ["type": "BOOLEAN"],
                    ],
                    "required": ["name", "amount", "is_addon"],
                ],
            ],
            "down_payment": ["type": "NUMBER", "nullable": true],
            "amount_financed": ["type": "NUMBER", "nullable": true],
            "apr_percent": ["type": "NUMBER", "nullable": true],
            "term_months": ["type": "INTEGER", "nullable": true],
            "monthly_payment": ["type": "NUMBER", "nullable": true],
        ],
        "required": ["document_type", "fees"],
    ]
}
