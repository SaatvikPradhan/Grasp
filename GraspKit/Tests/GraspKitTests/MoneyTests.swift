import Foundation
import Testing
@testable import GraspKit

struct MoneyFactsTests {
    let pitch = LoanTerms.demoContract
    let sticker = OfferReading(documentType: .windowSticker, cashPrice: 19_900, fees: [
        .init(name: "Nitrogen-filled tires", amount: 299, isAddon: true),
        .init(name: "Paint and fabric protection", amount: 895, isAddon: true),
    ])

    var facts: MoneyFacts {
        MoneyFacts(
            pitch: pitch,
            chosen: pitch.with(termMonths: 48),
            quote: LoanTerms(principal: 21_600, apr: 0.064, termMonths: 48),
            contract: .demoContract,
            stickers: [sticker]
        )
    }

    @Test func mergesAddOnsAcrossContractAndSticker() {
        let addOns = facts.addOns
        #expect(addOns.count == 2)   // paint protection once, though it's on both
        #expect(addOns.first?.name == "Paint and fabric protection")
        #expect(addOns.first?.onContract == true && addOns.first?.onSticker == true)
        #expect(addOns.last?.onContract == false)
        #expect(facts.addOnTotal == 1_194)
    }

    @Test func savingsMatchTheBrief() {
        #expect(facts.savedByTerm == 2_204)
        #expect(facts.savedByQuote == 3_416)
        #expect(facts.quoteVersusDealer == 1_212)
        #expect(facts.outTheDoor == 22_600)
        #expect(facts.negotiableFees.map(\.name) == ["Documentary fee"])
    }

    @Test func talkingPointsLeadWithTheBiggestWin() {
        let points = facts.talkingPoints()
        #expect(points.count == 4)
        #expect(points[0].contains("6.4%") && points[0].contains("$3,416"))
        #expect(points[1].contains("48 months") && points[1].contains("$2,204"))
        #expect(points[2].contains("paint and fabric protection") && points[2].contains("$1,194"))
    }

    @Test func talkingPointsWithoutAQuote() {
        let facts = MoneyFacts(pitch: pitch, chosen: pitch, contract: .demoContract)
        let points = facts.talkingPoints()
        #expect(points.first?.contains("paint and fabric protection") == true)
        #expect(!points.joined().contains("credit union"))
    }

    @Test func numbersAreNormalized() {
        #expect(MoneyFacts.numbers(in: "saves $2,204 at 8.90% over 48.0 months") == ["2204", "8.9", "48"])
        #expect(facts.knownNumbers.isSuperset(of: ["3416", "2204", "6.4", "1194"]))
    }
}

struct PitchCheckerTests {
    let offer = LoanTerms.demoContract

    @Test func catchesTheMonthlyPitch() {
        let checks = PitchChecker.checks(in: "We can get you in at just $388 a month", against: offer)
        #expect(checks.count == 1)
        #expect(checks[0].verdict == .catch)
        #expect(checks[0].note.contains("72 months"))
        #expect(checks[0].note.contains("$27,956"))
        #expect(checks[0].note.contains("$536"))
    }

    @Test func understandsOtherWaysOfSayingIt() {
        #expect(PitchChecker.checks(in: "only 388 bucks per month", against: offer).first?.verdict == .catch)
        #expect(PitchChecker.checks(in: "about 536 dollars a month", against: offer).first?.verdict == .holds)
        #expect(PitchChecker.checks(in: "it's $300 a month", against: offer).first?.note.contains("doesn't match") == true)
    }

    @Test func checksRatesAndTerms() {
        let checks = PitchChecker.checks(in: "that's 8.9 percent over six years, or 5.9% if you sign", against: offer)
        #expect(checks.contains { $0.heard == "8.9%" && $0.verdict == .holds })
        #expect(checks.contains { $0.heard == "5.9%" && $0.verdict == .catch })
        #expect(checks.contains { $0.heard == "72 months" && $0.verdict == .holds })
    }

    @Test func flagsPressure() {
        let checks = PitchChecker.checks(in: "This price ends today, someone else is looking at it", against: offer)
        #expect(checks.filter { $0.verdict == .pressure }.count == 2)
    }

    @Test func ignoresSmallTalk() {
        #expect(PitchChecker.checks(in: "how was the drive over here", against: offer).isEmpty)
    }
}

struct AdviceWriterTests {
    let facts = MoneyFactsTests().facts

    @Test func fallsBackToTalkingPointsWithoutAKey() async {
        let advice = await AdviceWriter(client: nil).write(for: facts)
        #expect(!advice.isFromAI)
        #expect(advice.lines == Array(facts.talkingPoints().prefix(3)))
    }

    /// Calls the real API: `GEMINI_API_KEY=... swift test --filter LiveAdvice`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil)) func liveAdviceUsesOnlyOurNumbers() async {
        let client = GeminiClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)
        let advice = await AdviceWriter(client: client).write(for: facts)
        print("ADVICE", advice)
        #expect(advice.isFromAI)
        #expect(!advice.lines.isEmpty && advice.lines.count <= 3)
        #expect(Set(MoneyFacts.numbers(in: (advice.lines + [advice.spoken]).joined(separator: " "))).isSubset(of: facts.knownNumbers))
    }
}

struct LiveElevenLabsTests {
    /// Costs about 30 characters of the plan: `ELEVENLABS_API_KEY=... swift test --filter LiveElevenLabs`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"] != nil)) func speaks() async throws {
        let audio = try await ElevenLabsClient(apiKey: ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]!)
            .speech(for: "Ask for forty eight months.")
        #expect(audio.count > 5_000)
        #expect(audio.prefix(3) == Data("ID3".utf8) || audio.first == 0xFF)
    }
}
