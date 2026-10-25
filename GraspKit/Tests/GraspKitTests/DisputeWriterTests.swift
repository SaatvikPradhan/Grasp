import Foundation
import Testing
@testable import GraspKit

struct DisputeCheckTests {
    @Test func amountsComeFromPrintedNumbersOnly() {
        let lines = ["Northway Mobile", "Account 7702-4415-09", "Northway Unlimited plan $85.00", "Promotional rate $60.00/mo applies",
                     "Late payment fee $7.00", "Total new charges $145.32", "Jordan Lee"]
        var reading = PageReading(kind: "bill", title: "Bill", summary: "", facts: [], catches: [], model: .init(type: .none),
                                  relations: [.init(label: "Total new charges", kind: .sum, stated: 145.32,
                                                    inputs: [85, 25, 15, -10, 3.49, 2.99, 7, 6.84].map { .init(label: "", value: $0) })])
        reading.lines = lines + ["$25.00", "$15.00", "-$10.00", "$3.49", "$2.99", "$6.84"]
        let raw = DisputeWriter.Raw(company: "Northway Mobile", accountNumber: "7702-4415-09", customerName: "Jordan Lee",
                                    subject: "Charges on my bill", opening: "I'm writing about my bill.", closing: "Please credit me.",
                                    charges: [
            .init(title: "Promo not applied", reason: "The bill shows a $60 promo.", verdict: "price_not_applied", charged: 85, shouldBe: 60, quote: "Northway Unlimited plan $85.00"),
            .init(title: "Late fee", reason: "Paid on time.", verdict: "fee_not_owed", charged: 7, shouldBe: nil, quote: "Late payment fee $7.00"),
            .init(title: "Made-up fee", reason: "", verdict: "fee_not_owed", charged: 12, shouldBe: nil, quote: nil),
            .init(title: "Recovery fee", reason: "Northway's own charge.", verdict: "worth_asking", charged: 3.49, shouldBe: nil, quote: nil),
        ])
        let letter = try! #require(DisputeWriter.checked(raw, reading: reading))
        #expect(letter.items.map(\.amount) == [10, 25, 7])
        #expect(letter.total == 42)
        #expect(letter.items[0].math == "$145.32 − $135.32")
        #expect(letter.account == "7702-4415-09")
        #expect(letter.text.contains("In total, I'm asking for a credit of $42.00 on this bill."))
        #expect(letter.questions.map(\.amount) == [3.49])
        #expect(letter.text.contains("I'd also like an explanation of the recovery fee ($3.49)."))
    }
}

struct LiveDisputeWriterTests {
    @Test(.enabled(if: TestDocumentTests.key != nil)) func disputesThePhoneBill() async throws {
        let page = try await TestDocumentTests.read("phone-bill")
        let started = Date()
        let letter = try #require(try await DisputeWriter(client: GeminiClient(apiKey: TestDocumentTests.key!)).write(page))
        print("DISPUTE \(String(format: "%.1f", Date().timeIntervalSince(started))) s, total \(letter.total): \(letter.items.map { "\($0.title) \($0.amount)" }) · asking \(letter.questions.map { "\($0.title) \($0.amount)" })")
        #expect(letter.total == 42)
        #expect(letter.items.count == 3)
    }
}
