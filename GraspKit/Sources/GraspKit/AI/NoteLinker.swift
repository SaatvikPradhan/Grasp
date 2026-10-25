import Foundation

/// Someone's notes on a paper, each tied to the passage it's about, and where the research could
/// go next. Gemini matches notes to passages; Swift checks every passage is really in the paper and
/// every number in a note is one the paper gives.
public struct LinkedNotes: Equatable, Sendable {
    public struct Note: Equatable, Sendable, Identifiable {
        public enum Status: String, Codable, Sendable {
            /// The paper says the same thing.
            case matches
            /// The paper says something else: another number, the opposite, or less than the note claims.
            case differs
            /// The paper doesn't say it.
            case notInPaper = "not_in_paper"
        }

        public var note: String
        public var status: Status
        /// Words copied from the paper, found on its page.
        public var quote: String?
        /// Where the quote is in the paper's lines.
        public var location: SourceLocator.Location?
        /// When it differs: what the paper actually says.
        public var paperSays: String?

        public var id: String { note }
    }

    /// Something the paper leaves open that could be studied next.
    public struct Direction: Equatable, Sendable, Identifiable {
        public var title: String
        /// One sentence: why, and what it would show.
        public var why: String
        /// The paper's words it grows from: a limitation, something not measured, a next step.
        public var quote: String
        public var location: SourceLocator.Location
        /// The notes (by position, from 0) it connects to.
        public var buildsOn: [Int]

        public var id: String { title }
    }

    public var notes: [Note]
    public var directions: [Direction]
}

public struct NoteLinker: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
        // Weighing a note against a passage is judgment, so the model thinks a little.
        self.client.thinkingLevel = "low"
    }

    /// `paper` is every line of the paper's page; `notes` is the notes as written, one per line.
    public func link(notes: String, paper: [String], title: String) async throws -> LinkedNotes {
        let prompt = Self.prompt(notes: notes, paper: paper, title: title)
        let raw = try await client.generate(Raw.self, prompt: prompt, schema: Self.schema)
        return Self.checked(raw, paper: paper)
    }

    // MARK: Checking

    struct Raw: Decodable {
        struct Note: Decodable {
            var note: String
            var status: LinkedNotes.Note.Status
            var quote: String?
            var paperSays: String?
        }

        struct Direction: Decodable {
            var title: String
            var why: String
            var quote: String
            var buildsOn: [Int]?
        }

        var notes: [Note]
        var directions: [Direction]
    }

    /// Keeps only passages that are really on the page, and catches a number in a note that the
    /// paper never gives, even when the model called the note a match.
    static func checked(_ raw: Raw, paper: [String]) -> LinkedNotes {
        let printed = Set(paper.flatMap(MoneyFacts.numbers))
        let notes = raw.notes.map { item -> LinkedNotes.Note in
            let text = item.note.replacing(#/^\s*\d+[.)]\s*/#, with: "")
            let location = item.quote.flatMap { quote in
                quote.isEmpty ? nil : SourceLocator.locate(printed: nil, quote: quote, in: paper)
            }
            var note = LinkedNotes.Note(note: text, status: item.status, quote: location == nil ? nil : item.quote,
                                        location: location, paperSays: item.paperSays)
            let missing = MoneyFacts.numbers(in: text).filter { !printed.contains($0) }
            if note.status == .matches, let number = missing.first {
                note.status = .differs
                note.paperSays = "The paper never gives \(number)."
            }
            if note.status == .matches, location == nil {
                // Can't show where it says so: don't claim it does.
                note.status = .notInPaper
            }
            if note.status != .differs { note.paperSays = nil }
            return note
        }
        let directions = raw.directions.prefix(3).compactMap { item -> LinkedNotes.Direction? in
            guard let location = SourceLocator.locate(printed: nil, quote: item.quote, in: paper) else { return nil }
            let buildsOn = (item.buildsOn ?? []).map { $0 - 1 }.filter { notes.indices.contains($0) }
            return LinkedNotes.Direction(title: item.title, why: item.why, quote: item.quote, location: location, buildsOn: buildsOn)
        }
        return LinkedNotes(notes: notes, directions: directions)
    }

    // MARK: Prompt

    static func prompt(notes: String, paper: [String], title: String) -> String {
        """
        Someone took notes on a paper. Check each note against the paper.
        notes: one entry per note, in order, with note copied exactly as written. status is matches when \
        the paper says the same thing, differs when the paper says something else (another number, the \
        opposite finding, or more than the paper claims), and not_in_paper when the paper doesn't say it. \
        quote is the words in the paper the note is about, copied exactly from the paper's text below \
        (a phrase or one sentence; empty when not_in_paper). paper_says, only when it differs, is what \
        the paper actually says, in one plain sentence.
        directions: up to 3 things a researcher could study next. Each grows from something the paper \
        leaves open: a limitation, something it didn't measure, a test it says remains to be done, or \
        something a note wondered about. title is a few words; why is one plain sentence on what it \
        would show; quote is the paper's words it grows from, copied exactly; builds_on lists the \
        numbers (from 1) of the notes it connects to.

        The paper, "\(title)", as read from its page:
        \(paper.joined(separator: "\n").prefix(8_000))

        The notes:
        \(notes)
        """
    }

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "notes": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "note": ["type": "STRING"],
                        "status": ["type": "STRING", "enum": ["matches", "differs", "not_in_paper"]],
                        "quote": ["type": "STRING", "nullable": true],
                        "paper_says": ["type": "STRING", "nullable": true],
                    ],
                    "required": ["note", "status"],
                ],
            ],
            "directions": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "title": ["type": "STRING"],
                        "why": ["type": "STRING"],
                        "quote": ["type": "STRING"],
                        "builds_on": ["type": "ARRAY", "items": ["type": "INTEGER"]],
                    ],
                    "required": ["title", "why", "quote"],
                ],
            ],
        ],
        "required": ["notes", "directions"],
    ]
}
