import Foundation
import Testing
@testable import GraspKit

struct OfferReadingTests {
    /// What Gemini returned for `Fixtures/contract-photo.jpg`.
    let answer = """
    {"document_type": "loan_contract", "fees": [{"name": "Documentary fee", "amount": 499.0, "is_addon": false}, \
    {"name": "Paint and fabric protection", "amount": 895.0, "is_addon": true}, \
    {"name": "Sales tax, title and registration", "amount": 1306.0, "is_addon": false}], \
    "amount_financed": 21600.0, "apr_percent": 8.9, "cash_price": 19900.0, "down_payment": 1000.0, \
    "monthly_payment": 388.28, "term_months": 72}
    """

    func decode(_ json: String) throws -> OfferReading {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OfferReading.self, from: Data(json.utf8))
    }

    @Test func decodesGeminisAnswer() throws {
        let reading = try decode(answer)
        #expect(reading.documentType == .loanContract)
        #expect(isDemoLoan(reading.loan))
        #expect(reading.addOns.map(\.name) == ["Paint and fabric protection"])
        #expect(reading.addOnTotal == 895)
        #expect(reading.discrepancies.isEmpty)
    }

    @Test func stickerHasNoLoan() throws {
        let reading = try decode("""
        {"document_type": "window_sticker", "fees": [{"name": "Nitrogen tires", "amount": 299, "is_addon": true}, \
        {"name": "Paint protection", "amount": 895, "is_addon": true}], "cash_price": 19900}
        """)
        #expect(reading.loan == nil)
        #expect(reading.addOnTotal == 1_194)
    }

    @Test func catchesAPaymentThatDoesNotFit() {
        var reading = OfferReading(documentType: .loanContract, amountFinanced: 21_600, aprPercent: 8.9, termMonths: 72, monthlyPayment: 368)
        #expect(reading.discrepancies.count == 1)
        reading.monthlyPayment = 388.28
        #expect(reading.discrepancies.isEmpty)
    }

    @Test func catchesItemsThatDoNotAddUp() {
        let reading = OfferReading(
            documentType: .loanContract, cashPrice: 19_900,
            fees: [OfferReading.Fee(name: "Doc fee", amount: 499, isAddon: false)],
            downPayment: 1_000, amountFinanced: 21_600
        )
        #expect(reading.discrepancies.count == 1)
    }
}

/// Calls the real API. Runs only with a key: `GEMINI_API_KEY=... swift test --filter LiveGemini`
struct LiveGeminiTests {
    static let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]

    @Test(.enabled(if: key != nil)) func readsTheContractPhoto() async throws {
        let url = try #require(Bundle.module.url(forResource: "contract-photo", withExtension: "jpg", subdirectory: "Fixtures"))
        let reader = OfferReader(client: GeminiClient(apiKey: Self.key!))
        let started = Date()
        let reading = try await reader.read(jpeg: Data(contentsOf: url))
        print("Read the contract in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
        #expect(reading.documentType == .loanContract)
        #expect(isDemoLoan(reading.loan))
        #expect(reading.monthlyPayment == 388.28)
        #expect(reading.addOnTotal == 895)
        #expect(reading.discrepancies.isEmpty)
    }

    @Test(.enabled(if: key != nil)) func readsTheWindowSticker() async throws {
        let reading = try await read("sticker-photo")
        #expect(reading.documentType == .windowSticker)
        #expect(reading.addOnTotal == 1_194)   // not doubled by the "Total dealer add-ons" line
        #expect(reading.addOns.count == 2)
        #expect(reading.loan == nil)
    }

    @Test(.enabled(if: key != nil)) func readsTheCreditUnionQuote() async throws {
        let reading = try await read("quote-photo")
        #expect(reading.documentType == .loanQuote)
        #expect(reading.aprPercent == 6.4)
        #expect(reading.addOns.isEmpty)
    }

    private func read(_ fixture: String) async throws -> OfferReading {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "jpg", subdirectory: "Fixtures"))
        return try await OfferReader(client: GeminiClient(apiKey: Self.key!)).read(jpeg: Data(contentsOf: url))
    }
}

/// 8.9 / 100 is 0.08900000000000001 in floating point, so compare the rate loosely.
func isDemoLoan(_ loan: LoanTerms?) -> Bool {
    guard let loan else { return false }
    let demo = LoanTerms.demoContract
    return loan.principal == demo.principal && loan.termMonths == demo.termMonths && abs(loan.apr - demo.apr) < 1e-9
}
