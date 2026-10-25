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

struct AddsUpTests {
    func fact(_ key: String, _ value: Double) -> PageReading.Fact {
        PageReading.Fact(key: key, label: key, asPrinted: String(format: "$%.2f", value), value: value, unit: .dollars, quote: key)
    }

    func inputs(_ values: [Double]) -> [PageReading.Relation.Input] {
        values.map { .init(label: "", value: $0) }
    }

    func page(_ facts: [PageReading.Fact], _ relations: [PageReading.Relation]) -> PageReading {
        PageReading(kind: "bill", title: "Bill", summary: "", facts: facts, catches: [], model: .init(type: .none), relations: relations)
    }

    @Test func catchesATotalThatIsTooHigh() {
        // The phone bill: the −$10 discount was never subtracted.
        let lines: [Double] = [85, 25, 15, -10, 3.49, 2.99, 7, 6.84]
        let reading = page(lines.enumerated().map { fact("line\($0.offset)", $0.element) } + [fact("total", 145.32)],
                           [.init(label: "Total new charges", kind: .sum, stated: 145.32, inputs: inputs(lines))])
        #expect(reading.mismatches.count == 1)
        #expect(abs(reading.mismatches[0].expected - 135.32) < 0.001)
        #expect(abs(reading.mismatches[0].difference - 10) < 0.001)
        #expect(reading.allCatches.first?.title == "Doesn't add up: Total new charges")
    }

    @Test func catchesHoursTimesRateAndAPercentage() {
        let reading = page([fact("hours", 32.5), fact("rate", 13.5), fact("gross", 425.25), fact("ss", 28.37), fact("pct", 6.2)], [
            .init(label: "Gross pay", kind: .product, stated: 425.25, inputs: inputs([32.5, 13.5])),
            .init(label: "Social Security", kind: .percentOf, stated: 28.37, inputs: inputs([6.2, 425.25])),
        ])
        #expect(reading.mismatches.map(\.expected) == [438.75, 26.37])
    }

    @Test func aTotalListedTwiceIsTrustedIfEitherAddsUp() {
        let facts = [fact("a", 100), fact("b", 50), fact("c", 25), fact("total", 175)]
        let wrongly = PageReading.Relation(label: "Total", kind: .sum, stated: 175, inputs: inputs([100, 50]))
        let rightly = PageReading.Relation(label: "Total", kind: .sum, stated: 175, inputs: inputs([100, 50, 25]))
        #expect(page(facts, [wrongly, rightly]).mismatches.isEmpty)
        #expect(page(facts, [wrongly, wrongly]).mismatches.count == 1)
    }

    @Test func theBreakdownIsThePagesLongestTotalAddedUpAgain() {
        let lines: [Double] = [85, 25, 15, -10, 3.49, 2.99, 7, 6.84]
        var reading = page(lines.enumerated().map { fact("line\($0.offset)", $0.element) } + [fact("total", 145.32), fact("net", 340)], [
            .init(label: "Net pay", kind: .sum, stated: 340, inputs: inputs([425.25, -85.25])),
            .init(label: "Total new charges", kind: .sum, stated: 145.32, inputs: inputs(lines)),
        ])
        reading.model = .init(type: .breakdown)
        guard case .breakdown(let breakdown) = reading.resolvedModel else { Issue.record("expected a breakdown"); return }
        #expect(breakdown.label == "Total new charges")
        #expect(breakdown.lines.count == 8)
        #expect(breakdown.total == 135.32)
        #expect(!breakdown.matchesPage)
        // No itemized total on the page: no made-up one.
        reading.relations = []
        #expect(reading.resolvedModel == .none)
    }

    @Test func aProductWithARateInItIsntChecked() {
        let reading = page([fact("payment", 25), fact("months", 36)], [
            .init(label: "Device payment", kind: .product, stated: 25,
                  inputs: [.init(label: "36 months", value: 36), .init(label: "0%", value: 0)]),
        ])
        #expect(reading.mismatches.isEmpty)
    }

    @Test func anotherTotalOfTheSameAmountDoesntHideAMistake() {
        // The phone bill: "Total amount due" adds up, "Total new charges" doesn't; both say $145.32.
        let lines: [Double] = [85, 25, 15, -10, 3.49, 2.99, 7, 6.84]
        let facts = (lines + [110.30, 145.32]).enumerated().map { fact("f\($0.offset)", $0.element) }
        let reading = page(facts, [
            .init(label: "Total amount due", kind: .sum, stated: 145.32, inputs: inputs([110.30, -110.30, 145.32])),
            .init(label: "Total new charges", kind: .sum, stated: 145.32, inputs: inputs(lines)),
        ])
        #expect(reading.mismatches.map(\.expected) == [135.32])
    }

    @Test func aPercentPrintedWithOneDecimalCounts() {
        var reading = page([fact("gross", 425.25)], [
            .init(label: "Social Security", kind: .percentOf, stated: 28.37, inputs: inputs([6.2, 425.25])),
        ])
        reading.lines = ["Social Security (6.2%)", "28.37"]
        #expect(reading.mismatches.map(\.expected) == [26.37])
    }

    @Test func correctTotalsPass() {
        let reading = page([fact("a", 19_900), fact("b", 499), fact("c", 895), fact("d", 1_306), fact("subtotal", 22_600)],
                           [.init(label: "Subtotal", kind: .sum, stated: 22_600, inputs: inputs([19_900, 499, 895, 1_306]))])
        #expect(reading.mismatches.isEmpty)
    }

    @Test func numbersNotOnThePageCantCreateAMistake() {
        let reading = page([fact("total", 100)], [.init(label: "Total", kind: .sum, stated: 100, inputs: inputs([60, 50]))])
        #expect(reading.mismatches.isEmpty)
    }

    @Test func aNumberOnAnyLineOfThePageCounts() {
        // Hours and rate aren't facts, but Vision read them on the page.
        var reading = page([fact("gross", 425.25)], [.init(label: "Gross pay", kind: .product, stated: 425.25, inputs: inputs([32.5, 13.5]))])
        #expect(reading.mismatches.isEmpty)
        reading.lines = ["Regular 32.50 13.50 425.25 2,104.75"]
        #expect(reading.mismatches.map(\.expected) == [438.75])
        // A number that only looks close doesn't count: 1,150 is not 150.
        reading.lines = ["Monthly rent $1,150.00"]
        #expect(reading.spot(of: 150) == nil)
        #expect(reading.spot(of: 1_150)?.quote == "Monthly rent $1,150.00")
    }

    @Test func aFixedUpInputIsReadFromItsLine() {
        // The page says $14,400 for 12 months at $1,150; the model wrote 1,200 so it would add up.
        var rent = fact("monthly_rent", 1_150)
        rent.label = "Monthly rent"
        var reading = page([rent, fact("total_rent", 14_400)], [
            .init(label: "Total rent", kind: .product, stated: 14_400,
                  inputs: [.init(label: "Monthly rent", value: 1_200), .init(label: "Months", value: 12)]),
        ])
        reading.lines = ["Lease term 12 months: Aug 15, 2026 to Aug 14, 2027"]
        #expect(reading.mismatches.map(\.expected) == [13_800])
        #expect(reading.mismatches.first?.relation.values == [1_150, 12])
    }
}
