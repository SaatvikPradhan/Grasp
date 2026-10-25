import Foundation
import Testing
@testable import GraspKit

struct VideoReaderTests {
    @Test func readsClockTimes() {
        #expect(VideoReading.seconds("1:05") == 65)
        #expect(VideoReading.seconds("01:02:05") == 3725)
        #expect(VideoReading.seconds("65") == 65)
        #expect(VideoReading.seconds("[0:31]") == 31)
        #expect(VideoReading.seconds("soon") == nil)
        #expect(VideoReading.clock(65.9) == "1:05")
        #expect(VideoReading.clock(3725) == "1:02:05")
    }

    let raw = VideoReader.Raw(
        kind: "physics lecture", title: "Newton's Law of Cooling", summary: "How a drink cools.",
        transcript: [
            .init(at: "0:31", text: "For an open paper cup of water, k is about 0.031 per minute."),
            .init(at: "0:00", text: "Welcome back."),
            .init(at: "9:59", text: "Past the end of the video."),
        ],
        moments: [.init(at: "0:31", title: "k for an open cup", why: "The number to compare with.")],
        facts: [
            .init(label: "k, open cup", value: "0.031 per minute", number: 0.031, unit: .number, quote: "k is about 0.031 per minute"),
            .init(label: "Made up", value: "0.5", number: 0.5, unit: .number, quote: "k is about 0.031 per minute"),
            .init(label: "Not said", value: "21 °C", number: 21, unit: .number, quote: "the room was 21 degrees"),
        ])

    @Test func keepsOnlyFactsSaidInTheTranscript() {
        let video = VideoReader.checked(raw, duration: 62.4)
        #expect(video.facts.map(\.label) == ["k, open cup"])
        #expect(video.seconds(of: video.facts[0].quote) == 31)
    }

    @Test func sortsTheTranscriptAndDropsTimesPastTheEnd() {
        let video = VideoReader.checked(raw, duration: 62.4)
        #expect(video.transcript.map(\.seconds) == [0, 31])
        #expect(video.lines.first == "[0:00] Welcome back.")
        #expect(video.page.lines?.count == 2)
    }
}

struct LiveVideoReaderTests {
    @Test(.enabled(if: TestDocumentTests.key != nil)) func watchesTheLecture() async throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../props/lecture-cooling.mp4").standardized
        let started = Date()
        let video = try await VideoReader(client: GeminiClient(apiKey: TestDocumentTests.key!))
            .read(.inline(try Data(contentsOf: url), mimeType: "video/mp4"), duration: 62.4)
        print("VIDEO \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(video.kind) · \(video.title) · \(video.transcript.count) lines")
        for moment in video.moments { print("  moment \(VideoReading.clock(moment.seconds)) \(moment.title)") }
        for fact in video.facts { print("  fact \(fact.label): \(fact.asPrinted) at \(video.seconds(of: fact.quote).map(VideoReading.clock) ?? "?")") }
        #expect(video.transcript.count >= 5)
        #expect(video.moments.count >= 3)
        #expect(video.facts.contains { $0.value == 0.031 })
        // The lid comes in on the fourth slide, about halfway through.
        let lid = try #require(video.transcript.first { $0.text.contains("0.019") })
        #expect(lid.seconds > 30 && lid.seconds < 50)
    }
}

struct LiveYouTubeTests {
    /// "Me at the zoo", YouTube's first video: 19 seconds, and it never changes.
    @Test(.enabled(if: TestDocumentTests.key != nil)) func watchesAYouTubeLink() async throws {
        let url = try #require(URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw"))
        let started = Date()
        let video = try await VideoReader(client: GeminiClient(apiKey: TestDocumentTests.key!)).read(.youTube(url), duration: 19)
        print("YOUTUBE \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(video.title) · \(video.transcript.count) lines")
        for line in video.transcript { print("  \(VideoReading.clock(line.seconds)) \(line.text)") }
        #expect(!video.transcript.isEmpty)
        #expect(video.transcript.contains { $0.text.lowercased().contains("elephant") })
    }
}
