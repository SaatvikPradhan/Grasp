import Foundation
import Testing
@testable import GraspKit

struct CalculatorToolTests {
    @Test func loanPayment() {
        let result = QuestionAnswerer.run(FunctionCall(name: "loan_payment", arguments: [
            "principal": .number(21_600), "apr_percent": .number(8.9), "months": .number(48),
        ]))
        #expect(result.values == [536.49, 25_751.52, 4_151.52])
    }

    @Test func payoffAtTheMinimumAndBelowTheInterest() {
        let paid = QuestionAnswerer.run(FunctionCall(name: "payoff_months", arguments: [
            "balance": .number(1_000), "apr_percent": .number(24), "monthly_payment": .number(50),
        ]))
        #expect(paid.values.first == 26)
        let never = QuestionAnswerer.run(FunctionCall(name: "payoff_months", arguments: [
            "balance": .number(1_000), "apr_percent": .number(24), "monthly_payment": .number(15),
        ]))
        #expect(never.summary.contains("never"))
    }

    @Test func arithmetic() {
        let result = QuestionAnswerer.run(FunctionCall(name: "arithmetic", arguments: [
            "a": .number(85), "operation": .text("subtract"), "b": .number(60),
        ]))
        #expect(result.values == [25])
    }
}

/// Calls the real API: `GEMINI_API_KEY=... swift test --filter LiveAsk`
struct LiveAskTests {
    static let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]

    let phonePlan = AskedDocument(
        title: "Unlimited Plus plan with iPhone 17", kind: "phone plan agreement",
        summary: "A 24-month plan that starts at $60 a month and rises to $85, plus $25 a month for the phone.",
        facts: ["Promo plan price: $60.00", "Regular plan price: $85.00", "Device payment: $25.00", "AutoPay discount: -$10.00", "Activation fee: $35.00", "Service term: 24 months"],
        catches: ["Remaining device balance due if you cancel early", "Price rises after 12 months"],
        text: """
        Unlimited Plus plan (months 1 to 12, promotional) $60.00
        Unlimited Plus plan (from month 13) $85.00
        Device payment, 36 months at 0% APR $25.00
        Activation fee $35.00
        Early termination. If you cancel service or port your number before the device installment plan is paid off, the remaining device balance becomes due immediately on your next bill.
        Renewal. At the end of the service term, service continues month to month at the then-current price unless you cancel.
        """
    )

    func ask(_ question: String, _ documents: [AskedDocument]) async throws -> GroundedAnswer {
        let started = Date()
        let answer = try await QuestionAnswerer(client: GeminiClient(apiKey: Self.key!)).answer(question, documents: documents, canvas: "One phone plan card.")
        print("ASK \(String(format: "%.1f", Date().timeIntervalSince(started))) s · \(question) → \(answer.answer) · quotes \(answer.quotes) · math \(answer.calculations) · checked \(answer.numbersChecked)")
        return answer
    }

    @Test(.enabled(if: key != nil)) func canICancelEarly() async throws {
        let answer = try await ask("Can I cancel early?", [phonePlan])
        #expect(answer.answer.lowercased().contains("balance"))
        #expect(answer.quotes.contains { $0.lowercased().contains("remaining device balance") || $0.lowercased().contains("cancel") })
        #expect(answer.numbersChecked)
    }

    @Test(.enabled(if: key != nil)) func mathGoesThroughTheTools() async throws {
        let answer = try await ask("How much more is the plan each month after the promotion ends?", [phonePlan])
        #expect(answer.answer.contains("25"))
        #expect(!answer.calculations.isEmpty)
        #expect(answer.numbersChecked)
    }
}
