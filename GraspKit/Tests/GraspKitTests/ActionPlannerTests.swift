import Foundation
import Testing
@testable import GraspKit

struct ActionPlannerTests {
    var reading: PageReading {
        var reading = PageReading(
            kind: "phone bill", title: "Northway Mobile Statement", summary: "A monthly bill.",
            facts: [.init(key: "plan", label: "Unlimited plan", asPrinted: "$85.00", value: 85, unit: .dollars, quote: "Northway Unlimited plan $85.00")],
            catches: [.init(title: "Late fee", explanation: "A $7.00 late fee though paid on time.", quote: "Late payment fee $7.00", severity: .high)],
            model: .init(type: .none))
        reading.lines = ["Northway Unlimited plan $85.00", "Late payment fee $7.00", "Total new charges $145.32"]
        return reading
    }

    let market = Grounded(
        text: """
        - Unlimited plans from the major carriers run about $65 to $90 a month for one line.
        - A claim nobody backs up at all.
        """,
        searches: ["unlimited phone plan price one line"],
        pages: [.init(title: "consumerreports.org", url: "https://example.com/plans")],
        supports: [.init(text: "Unlimited plans from the major carriers run about $65 to $90 a month for one line.", pages: [0])])

    let steps = ActionPlanner.Raw(steps: [
        .init(problem: 1, text: "Ask Northway to remove the $7.00 late fee, since the payment arrived on time."),
        .init(problem: nil, text: "Ask for a $40 loyalty credit."),
        .init(problem: 9, text: "A step about a problem that isn't there."),
    ], bottomLine: "Getting the late fee back saves $7.00 this month.")

    @Test func keepsOnlyComparisonsWithAPageBehindThem() {
        let plan = ActionPlanner.checked(market: market, steps: steps, reading: reading)
        #expect(plan.findings.map(\.text) == ["Unlimited plans from the major carriers run about $65 to $90 a month for one line."])
        #expect(plan.sources.map(\.site) == ["consumerreports.org"])
        #expect(plan.searches == ["unlimited phone plan price one line"])
    }

    @Test func tiesStepsToTheirCatchAndChecksTheirAmounts() {
        let plan = ActionPlanner.checked(market: market, steps: steps, reading: reading)
        #expect(plan.steps.count == 3)
        #expect(plan.steps[0].catchIndex == 0)
        #expect(plan.steps[0].numbersChecked)
        // $40 is on neither the page nor in Grasp's arithmetic.
        #expect(!plan.steps[1].numbersChecked)
        // 9 isn't one of the page's catches, so it stays a plain step.
        #expect(plan.steps[2].catchIndex == nil)
        #expect(plan.bottomLine == "Getting the late fee back saves $7.00 this month.")
    }

    @Test func bottomLineAddsUpFromTheSteps() {
        let steps = ["Ask them to fix the $10.00 overcharge on the $145.32 total.", "Apply the $25.00 promo.",
                     "Waive the $7.00 late fee.", "Drop the $15.00 add-on."]
        #expect(ActionPlanner.math(of: "You could save up to $57.00.", from: steps) == "$25.00 + $15.00 + $10.00 + $7.00")
        #expect(ActionPlanner.math(of: "You could save $99.", from: steps) == nil)
        #expect(ActionPlanner.math(of: "Call them today.", from: steps) == nil)
    }

    @Test func onlyPagesWithMoneyGetAPlan() {
        #expect(ActionPlanner.isWorthPlanning(reading))
        let paper = PageReading(kind: "research paper", title: "Lids", summary: "", facts: [], catches: [], model: .init(type: .none))
        #expect(!ActionPlanner.isWorthPlanning(paper))
    }
}

struct LiveActionPlannerTests {
    @Test(.enabled(if: TestDocumentTests.key != nil)) func plansThePhoneBill() async throws {
        let page = try await TestDocumentTests.read("phone-bill")
        let started = Date()
        let plan = try await ActionPlanner(client: GeminiClient(apiKey: TestDocumentTests.key!)).plan(page)
        print("PLAN \(String(format: "%.1f", Date().timeIntervalSince(started))) s, searched \(plan.searches)")
        for finding in plan.findings { print("  compare: \(finding.text) \(finding.sources.map { "[\($0 + 1)]" }.joined())") }
        for step in plan.steps {
            print("  do\(step.catchIndex.map { " (catch \($0 + 1))" } ?? ""): \(step.text)\(step.numbersChecked ? "" : " [UNCHECKED]")")
        }
        print("  bottom: \(plan.bottomLine ?? "-")")
        for (index, source) in plan.sources.enumerated() { print("  [\(index + 1)] \(source.site)") }
        #expect(!plan.findings.isEmpty)
        #expect(plan.steps.count >= 2)
        #expect(plan.steps.contains { $0.catchIndex != nil })
    }
}
