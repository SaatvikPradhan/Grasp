import Foundation
import Testing
@testable import GraspKit

struct PageModelTests {
    func fact(_ key: String, _ value: Double, _ unit: PageReading.Fact.Unit) -> PageReading.Fact {
        PageReading.Fact(key: key, label: key, asPrinted: "\(value)", value: value, unit: unit, quote: key)
    }

    @Test func installmentLoanBecomesLoanTerms() {
        let page = PageReading(kind: "car loan contract", title: "Loan", summary: "", facts: [
            fact("amount_financed", 21_600, .dollars), fact("apr", 8.9, .percent), fact("term", 6, .years),
        ], catches: [], model: .init(type: .installmentLoan, principal: 21_600, aprPercent: 8.9, months: 72))
        guard case .loan(let loan) = page.resolvedModel else { Issue.record("not a loan"); return }
        #expect(loan.principal == 21_600 && loan.termMonths == 72 && abs(loan.apr - 0.089) < 1e-9)
        #expect(page.source(of: 72)?.key == "term")   // 6 years
    }

    @Test func recurringCostCountsThePromoThenTheRegularPrice() {
        let page = PageReading(kind: "phone plan", title: "Plan", summary: "", facts: [
            fact("promo_price", 60, .dollars), fact("promo_length", 12, .months), fact("price", 85, .dollars),
            fact("term", 24, .months), fact("device", 25, .dollars), fact("autopay", -10, .dollars), fact("activation", 35, .dollars),
        ], catches: [], model: .init(type: .recurringCost, months: 24, monthlyPrice: 85, promoPrice: 60, promoMonths: 12,
                                      extraMonthly: [25, -10], upfront: [35]))
        guard case .recurring(let cost) = page.resolvedModel else { Issue.record("not recurring"); return }
        let full: Double = 2_135          // 12 × $60 + 12 × $85 + 24 × ($25 − $10) + $35
        let inPromo: Double = 485         // 6 × $60 + 6 × $15 + $35, still inside the promo
        #expect(cost.total == full)
        #expect(cost.with(months: 6).total == inPromo)
        #expect(cost.regularBill == 100)
    }

    @Test func aLateFeeIsNotChargedUpFront() {
        let page = PageReading(kind: "phone plan", title: "", summary: "", facts: [
            fact("price", 85, .dollars), fact("term", 24, .months), fact("activation_fee", 35, .dollars), fact("late_fee", 7, .dollars),
        ], catches: [], model: .init(type: .recurringCost, months: 24, monthlyPrice: 85, upfront: [35, 7]))
        guard case .recurring(let cost) = page.resolvedModel else { Issue.record("not recurring"); return }
        #expect(cost.upfront == 35)
    }

    @Test func numbersNotOnThePageAreDropped() {
        let page = PageReading(kind: "loan", title: "", summary: "", facts: [fact("amount", 5_000, .dollars)], catches: [],
                               model: .init(type: .installmentLoan, principal: 5_000, aprPercent: 7, months: 36))
        #expect(page.resolvedModel == .none)   // 36 months isn't on the page
    }
}

/// Calls the real API: `GEMINI_API_KEY=... swift test --filter LivePage`
struct LivePageTests {
    static let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]

    func read(_ fixture: String) async throws -> PageReading {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "jpg", subdirectory: "Fixtures"))
        let started = Date()
        let page = try await PageReader(client: GeminiClient(apiKey: Self.key!)).read(jpeg: Data(contentsOf: url))
        print("PAGE \(fixture) \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(page.kind) · \(page.title) · facts \(page.facts.map { "\($0.key)=\($0.asPrinted)" }) · catches \(page.catches.map(\.title)) · model \(page.resolvedModel)")
        return page
    }

    @Test(.enabled(if: key != nil)) func readsThePhonePlan() async throws {
        let page = try await read("phone-plan")
        guard case .recurring(let cost) = page.resolvedModel else { Issue.record("expected a recurring cost"); return }
        #expect(cost.monthly == 85)
        #expect(cost.promoMonthly == 60 && cost.promoMonths == 12)
        #expect(page.catches.count >= 3)
        // The promotion ending is the catch that matters most here.
        #expect(page.catches.contains { catchItem in
            let words = (catchItem.title + " " + catchItem.explanation + " " + catchItem.quote).lowercased()
            return words.contains("promo") || words.contains("12") || words.contains("$85")
        })
    }

    @Test(.enabled(if: key != nil)) func readsTheCarContractAsALoan() async throws {
        let page = try await read("contract-photo")
        guard case .loan(let loan) = page.resolvedModel else { Issue.record("expected a loan"); return }
        #expect(isDemoLoan(loan))
    }
}
