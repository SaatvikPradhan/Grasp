import Foundation
import Testing
import Vision
@testable import GraspKit

/// The five test documents in props/photos, each with mistakes planted on purpose
/// (see props/TEST-DOCUMENTS.md). Grasp should find every one by itself.
struct TestDocumentTests {
    static let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]

    static func photo(_ name: String) -> URL {
        if let fixture = Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures") { return fixture }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("props/photos/\(name).jpg")
    }

    /// Every line of text on the photo, as the Mac app reads it.
    static func lines(_ jpeg: Data) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(data: jpeg).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    static func read(_ name: String) async throws -> PageReading {
        let started = Date()
        let jpeg = try Data(contentsOf: photo(name))
        var page = try await PageReader(client: GeminiClient(apiKey: key!)).read(jpeg: jpeg)
        page.lines = try lines(jpeg)
        print("""
        DOC \(name) \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(page.kind) · \(page.title)
          facts: \(page.facts.map { "\($0.key)=\($0.asPrinted)" })
          relations: \((page.relations ?? []).map { "\($0.label) \($0.kind.rawValue) \($0.stated) ← \($0.inputs.map { "\($0.label)=\($0.value)" })" })
          mismatches: \(page.mismatches.map { "\($0.relation.label): \($0.relation.stated) vs \($0.expected)" })
          catches: \(page.allCatches.map { "\($0.title): \($0.explanation)" })
        """)
        return page
    }

    static func expected(_ page: PageReading) -> [Double] { page.mismatches.map(\.expected) }

    @Test(.enabled(if: key != nil)) func phoneBillTotalIsTenDollarsHigh() async throws {
        let page = try await Self.read("phone-bill")
        #expect(Self.expected(page).contains(135.32))
    }

    @Test(.enabled(if: key != nil)) func leaseTotalRentIsWrong() async throws {
        let page = try await Self.read("apartment-lease")
        #expect(Self.expected(page).contains(13_800))
        #expect(page.mismatches.count == 1)
    }

    @Test(.enabled(if: key != nil)) func payStubIsShortAnHour() async throws {
        let page = try await Self.read("pay-stub")
        #expect(Self.expected(page).contains(438.75))
        #expect(Self.expected(page).contains(26.37))
        #expect(page.mismatches.count == 2)
    }

    @Test(.enabled(if: key != nil)) func aidLetterCostIsWrong() async throws {
        let page = try await Self.read("financial-aid-letter")
        #expect(Self.expected(page).contains(26_500))
        #expect(page.mismatches.count == 1)
    }

    @Test(.enabled(if: key != nil)) func cardOfferAddsUpButHasCatches() async throws {
        let page = try await Self.read("credit-card-offer")
        #expect(page.mismatches.isEmpty)
        let words = page.catches.map { ($0.title + " " + $0.explanation).lowercased() }.joined(separator: " ")
        #expect(words.contains("95"))
        #expect(words.contains("purchase date") || words.contains("deferred") || words.contains("retroactive"))
    }

    /// Pages with nothing wrong in their arithmetic must not get a false alarm.
    @Test(.enabled(if: key != nil), arguments: ["contract-photo", "sticker-photo", "quote-photo", "phone-plan"])
    func correctPagesAddUp(_ name: String) async throws {
        let page = try await Self.read(name)
        #expect(page.mismatches.isEmpty, "\(name): \(page.mismatches)")
    }
}

/// None of the five test documents is about a car, so the car reader must leave them alone,
/// or they'd turn into loan cards.
struct NotACarTests {
    @Test(.enabled(if: TestDocumentTests.key != nil),
          arguments: ["phone-bill", "apartment-lease", "credit-card-offer", "pay-stub", "financial-aid-letter"])
    func carReaderLeavesItAlone(_ name: String) async throws {
        let jpeg = try Data(contentsOf: TestDocumentTests.photo(name))
        let offer = try await OfferReader(client: GeminiClient(apiKey: TestDocumentTests.key!)).read(jpeg: jpeg)
        print("CAR? \(name): \(offer.documentType) apr \(String(describing: offer.aprPercent)) financed \(String(describing: offer.amountFinanced))")
        #expect(offer.documentType == .other, "\(name) read as \(offer.documentType)")
    }
}
