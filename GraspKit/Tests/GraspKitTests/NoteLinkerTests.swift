import Foundation
import Testing
@testable import GraspKit

struct NoteCheckTests {
    let paper = [
        "A lid lowered the cooling constant from 0.031 per minute to 0.019 per minute, so a lidded paper",
        "cup took 23.5 minutes to reach 60 °C, compared with 14.2 minutes without a lid.",
        "Evaporative mass loss was not recorded; weighing the cup during",
    ]

    @Test func aNumberThePaperNeverGivesIsCaughtEvenIfCalledAMatch() {
        let raw = NoteLinker.Raw(notes: [
            .init(note: "2. With a lid it takes 25 minutes to get down to 60 °C.", status: .matches, quote: "cup took 23.5 minutes to reach 60 °C"),
            .init(note: "1. k goes from 0.031 to 0.019 per minute.", status: .matches, quote: "from 0.031 per minute to 0.019 per minute"),
        ], directions: [])
        let linked = NoteLinker.checked(raw, paper: paper)
        #expect(linked.notes[0].note == "With a lid it takes 25 minutes to get down to 60 °C.")
        #expect(linked.notes[0].status == .differs)
        #expect(linked.notes[0].paperSays == "The paper never gives 25.")
        #expect(linked.notes[1].status == .matches)
        #expect(linked.notes[1].location?.line == 0)
    }

    @Test func aPassageThatIsntOnThePageIsntShown() {
        let raw = NoteLinker.Raw(notes: [
            .init(note: "Stirring made it cool faster.", status: .matches, quote: "stirring sped up cooling"),
        ], directions: [
            .init(title: "Weigh the cup", why: "Separates evaporation from conduction.", quote: "Evaporative mass loss was not recorded", buildsOn: [1, 9]),
            .init(title: "Made up", why: "Not grounded.", quote: "We recommend copper cups", buildsOn: nil),
        ])
        let linked = NoteLinker.checked(raw, paper: paper)
        #expect(linked.notes[0].status == .notInPaper)
        #expect(linked.notes[0].quote == nil)
        #expect(linked.directions.map(\.title) == ["Weigh the cup"])
        #expect(linked.directions[0].buildsOn == [0])
    }
}

/// The sample paper and a student's notes on it (props/research-paper.html, props/paper-notes.html):
/// notes 2, 3, 5 and 7 get the paper wrong, 6 isn't in it.
struct LiveNoteLinkerTests {
    @Test(.enabled(if: TestDocumentTests.key != nil)) func linksTheNotesToThePaper() async throws {
        let paper = try TestDocumentTests.lines(Data(contentsOf: TestDocumentTests.photo("research-paper")))
        let notes = try TestDocumentTests.lines(Data(contentsOf: TestDocumentTests.photo("paper-notes")))
        let started = Date()
        let linked = try await NoteLinker(client: GeminiClient(apiKey: TestDocumentTests.key!))
            .link(notes: notes.joined(separator: "\n"), paper: paper, title: "Lids, Sleeves and the Cooling of Hot Drinks")
        print("NOTES \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        for note in linked.notes {
            print("  [\(note.status.rawValue)] \(note.note)\n      quote: \(note.quote ?? "-")\n      paper says: \(note.paperSays ?? "-")")
        }
        for direction in linked.directions {
            print("  → \(direction.title): \(direction.why)\n      from: \(direction.quote) · notes \(direction.buildsOn)")
        }
        func status(_ words: String) -> LinkedNotes.Note.Status? {
            linked.notes.first { $0.note.localizedCaseInsensitiveContains(words) }?.status
        }
        #expect(status("0.031") == .matches)
        #expect(status("25 minutes") == .differs)
        #expect(status("20 trials") == .differs)
        #expect(status("21") == .matches)
        #expect(status("Ceramic") == .differs)
        #expect(status("Stirring") != .matches)
        #expect(status("Evaporation") == .differs)
        #expect(status("Sleeves") == .matches)
        #expect(linked.directions.count >= 2)
    }
}
