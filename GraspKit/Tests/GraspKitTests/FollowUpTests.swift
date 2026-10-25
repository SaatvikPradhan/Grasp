import Foundation
import Testing
@testable import GraspKit

/// Chains of follow-up questions on the five test documents, the way people actually ask:
/// "Do the charges add up?" then "and without the late fee?". Each step names the numbers
/// the answer must contain (from props/TEST-DOCUMENTS.md) or words it must use.
struct FollowUpTests {
    struct Step: CustomStringConvertible {
        var question: String
        /// Each inner list is one-of: the answer must contain at least one of them.
        var mustSay: [[String]]
        var description: String { question }
    }

    static let chains: [(document: String, steps: [Step])] = [
        ("phone-bill", [
            Step(question: "Do the charges add up?", mustSay: [["135.32"]]),
            Step(question: "And what would it be if they also took off the late fee?", mustSay: [["128.32"]]),
            Step(question: "Why is my plan $85 when I have a promo?", mustSay: [["60"]]),
            Step(question: "So what should the bill be with the promo price and no late fee?", mustSay: [["103.32"]]),
        ]),
        ("apartment-lease", [
            Step(question: "Is the total rent right?", mustSay: [["13,800", "13800"]]),
            Step(question: "What happens if I need to move out early?", mustSay: [["2,300", "2300", "two months"], ["deposit"]]),
            Step(question: "How much would that cost me in total?", mustSay: [["3,800", "3800"]]),
            Step(question: "And how do I stop it from renewing?", mustSay: [["60", "sixty"], ["writ"]]),
        ]),
        ("credit-card-offer", [
            Step(question: "Is it really 0% interest?", mustSay: [["purchase date", "deferred", "back to"]]),
            Step(question: "If I owe $2,000 at 29.99% and pay $50 a month, how long until it's paid off?", mustSay: [["325"]]),
            Step(question: "What about $100 a month?", mustSay: [["29 months"], ["806.76", "807"]]),
            Step(question: "And is there an annual fee?", mustSay: [["95"]]),
        ]),
        ("pay-stub", [
            Step(question: "Was I paid right for my hours?", mustSay: [["438.75"]]),
            Step(question: "How much was I underpaid?", mustSay: [["13.50", "13.5"]]),
            Step(question: "Should Social Security be taken out of my pay?", mustSay: [["student", "exempt"]]),
            Step(question: "How much is that this period?", mustSay: [["34.54", "28.37"]]),
        ]),
        ("financial-aid-letter", [
            Step(question: "Am I really fully covered?", mustSay: [["loan"]]),
            Step(question: "How much of this is free money?", mustSay: [["11,300", "11300"]]),
            Step(question: "So how much will I actually owe this year?", mustSay: [["15,200", "15200"]]),
            Step(question: "Does the cost add up?", mustSay: [["26,500", "26500"]]),
        ]),
    ]

    @Test(.enabled(if: TestDocumentTests.key != nil), arguments: chains.map(\.document))
    func followUps(_ name: String) async throws {
        let steps = try #require(Self.chains.first { $0.document == name }?.steps)
        let jpeg = try Data(contentsOf: TestDocumentTests.photo(name))
        var page = try await PageReader(client: GeminiClient(apiKey: TestDocumentTests.key!)).read(jpeg: jpeg)
        let lines = try TestDocumentTests.lines(jpeg)
        page.lines = lines
        let document = AskedDocument(page, text: lines)
        let answerer = QuestionAnswerer(client: GeminiClient(apiKey: TestDocumentTests.key!))
        var earlier: [Exchange] = []
        var log = "CHAIN \(name)"
        for (index, step) in steps.enumerated() {
            let started = Date()
            let answer = try await answerer.answer(step.question, documents: [document], canvas: "one page", earlier: earlier)
            let missing = step.mustSay.filter { options in !options.contains { answer.answer.localizedCaseInsensitiveContains($0) } }
            log += "\n  \(index + 1). \(step.question) [\(String(format: "%.1f", Date().timeIntervalSince(started))) s]\n     → \(answer.answer)\n     math: \(answer.calculations) checked: \(answer.numbersChecked)"
            if !missing.isEmpty { log += "\n     MISSING \(missing)" }
            #expect(missing.isEmpty, "\(name) step \(index + 1) “\(step.question)”: missing \(missing) in “\(answer.answer)”")
            #expect(answer.numbersChecked, "\(name) step \(index + 1): numbers not checked in “\(answer.answer)”")
            earlier.append(Exchange(question: step.question, answer: answer))
        }
        print(log)
    }
}
