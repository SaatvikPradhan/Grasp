import Foundation

/// A published paper, as OpenAlex has it.
public struct Work: Equatable, Sendable, Identifiable {
    /// OpenAlex's id: "W3047788059".
    public var id: String
    public var title: String
    public var year: Int?
    public var citations: Int
    /// "https://doi.org/…", when there is one.
    public var doi: String?
    public var firstAuthor: String?
    /// Rebuilt from OpenAlex's word index; empty when it has none.
    public var abstract: String

    public var link: URL? { doi.flatMap(URL.init(string:)) ?? URL(string: "https://openalex.org/\(id)") }

    /// "Reddy 2020"
    public var shortName: String {
        let surname = firstAuthor?.split(separator: " ").last.map(String.init) ?? "Unknown"
        return year.map { "\(surname) \($0)" } ?? surname
    }
}

/// OpenAlex's free search, no key needed: https://docs.openalex.org
public struct OpenAlexClient: Sendable {
    public init() {}

    public func search(_ query: String, limit: Int = 6) async throws -> [Work] {
        var parts = URLComponents(string: "https://api.openalex.org/works")!
        parts.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "per-page", value: String(limit)),
            URLQueryItem(name: "select", value: "id,doi,display_name,publication_year,cited_by_count,authorships,abstract_inverted_index"),
        ]
        let (data, response) = try await URLSession.shared.data(from: parts.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Page.self, from: data).results.compactMap(\.work)
    }

    struct Page: Decodable {
        struct Result: Decodable {
            struct Authorship: Decodable {
                struct Author: Decodable { var display_name: String? }
                var author: Author?
            }

            var id: String
            var doi: String?
            var display_name: String?
            var publication_year: Int?
            var cited_by_count: Int?
            var authorships: [Authorship]?
            var abstract_inverted_index: [String: [Int]]?

            var work: Work? {
                guard let title = display_name, !title.isEmpty else { return nil }
                return Work(id: id.replacingOccurrences(of: "https://openalex.org/", with: ""), title: title, year: publication_year,
                            citations: cited_by_count ?? 0, doi: doi, firstAuthor: authorships?.first?.author?.display_name,
                            abstract: OpenAlexClient.abstract(abstract_inverted_index))
            }
        }

        var results: [Result]
    }

    /// OpenAlex stores abstracts as word → positions; this puts the words back in order.
    static func abstract(_ index: [String: [Int]]?) -> String {
        guard let index else { return "" }
        var words: [Int: String] = [:]
        for (word, positions) in index {
            for position in positions { words[position] = word }
        }
        return words.keys.sorted().compactMap { words[$0] }.joined(separator: " ")
    }
}

/// Papers close to this one, and for each direction the research could take, whether someone has
/// already studied it. Gemini plans the searches and judges the results; OpenAlex supplies the
/// papers, so every paper named is a real record, and Swift drops any the search didn't return.
public struct RelatedWork: Equatable, Sendable {
    public struct Found: Equatable, Sendable {
        public var work: Work
        /// One sentence: how it relates to this paper.
        public var why: String
    }

    public struct Direction: Equatable, Sendable {
        public enum Verdict: String, Sendable {
            /// A listed paper studies this question.
            case studied
            /// A listed paper touches it but leaves part open.
            case partly
            case open
        }

        public var title: String
        public var why: String
        /// The paper's words it grows from.
        public var cited: Cited?
        public var verdict: Verdict
        /// The papers that already studied it.
        public var evidence: [Work]
        /// One sentence on the verdict.
        public var note: String
    }

    public var related: [Found]
    public var directions: [Direction]

    /// Every paper on the card, related ones first, each once.
    public var works: [Work] {
        var seen: Set<String> = []
        return (related.map(\.work) + directions.flatMap(\.evidence)).filter { seen.insert($0.id).inserted }
    }
}

public struct RelatedWorkFinder: Sendable {
    /// A direction already worked out (from linked notes), to check rather than invent.
    public struct Given: Sendable {
        public var title: String
        public var why: String
        public var cited: Cited?

        public init(title: String, why: String, cited: Cited?) {
            self.title = title
            self.why = why
            self.cited = cited
        }
    }

    public var client: GeminiClient
    public var openAlex: OpenAlexClient

    public init(client: GeminiClient, openAlex: OpenAlexClient = OpenAlexClient()) {
        self.client = client
        self.client.thinkingLevel = "low"
        self.openAlex = openAlex
    }

    public func find(paper lines: [String], title: String, directions given: [Given] = []) async throws -> RelatedWork {
        // 1. What to search for, and which directions to check.
        let plan = try await client.generate(Plan.self, prompt: Self.planPrompt(lines, title: title, given: given), schema: Self.planSchema)
        let directions = Self.directions(plan, given: given, lines: lines)

        // 2. The searches, all at once.
        let topics = Array(plan.topicQueries.prefix(3))
        let queries = topics + directions.map(\.query)
        let results = await withTaskGroup(of: (Int, [Work]).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask { (index, (try? await openAlex.search(query, limit: index < topics.count ? 8 : 6)) ?? []) }
            }
            var all: [(Int, [Work])] = []
            for await result in group { all.append(result) }
            return all.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var candidates: [String: Work] = [:]
        for work in results.flatMap({ $0 }) { candidates[work.id] = work }
        guard !candidates.isEmpty else { throw URLError(.cannotFindHost) }

        // 3. Which papers are close, and which directions are already done.
        let judged = try await client.generate(Judged.self,
                                               prompt: Self.judgePrompt(title: title, lines: lines, candidates: candidates, directions: directions),
                                               schema: Self.judgeSchema)
        return Self.checked(judged, candidates: candidates, directions: directions)
    }

    // MARK: Checking

    struct Plan: Decodable {
        struct Direction: Decodable {
            var title: String
            var why: String
            var quote: String?
            var query: String
        }

        var topicQueries: [String]
        var directions: [Direction]
    }

    struct Planned {
        var title: String
        var why: String
        var cited: Cited?
        var query: String
    }

    /// Given directions keep their own words; new ones must quote the paper.
    static func directions(_ plan: Plan, given: [Given], lines: [String]) -> [Planned] {
        if !given.isEmpty {
            return given.prefix(3).map { direction in
                let query = plan.directions.first { $0.title.lowercased() == direction.title.lowercased() }?.query ?? direction.title
                return Planned(title: direction.title, why: direction.why, cited: direction.cited, query: query)
            }
        }
        return plan.directions.prefix(3).compactMap { direction in
            guard let quote = direction.quote, let location = SourceLocator.locate(printed: nil, quote: quote, in: lines) else { return nil }
            return Planned(title: direction.title, why: direction.why, cited: Cited(quote: quote, location: location), query: direction.query)
        }
    }

    struct Judged: Decodable {
        struct Related: Decodable {
            var id: String
            var why: String
        }

        struct Direction: Decodable {
            var title: String
            var verdict: String
            var ids: [String]?
            var note: String
        }

        var related: [Related]
        var directions: [Direction]
    }

    /// Only papers the searches returned survive, and "already studied" needs one of them.
    static func checked(_ judged: Judged, candidates: [String: Work], directions: [Planned]) -> RelatedWork {
        var seen: Set<String> = []
        let related = judged.related.compactMap { item -> RelatedWork.Found? in
            guard let work = candidates[item.id], seen.insert(item.id).inserted else { return nil }
            return RelatedWork.Found(work: work, why: item.why)
        }.prefix(6)
        let checked = directions.map { direction -> RelatedWork.Direction in
            let verdict = judged.directions.first { $0.title.lowercased() == direction.title.lowercased() }
            let evidence = (verdict?.ids ?? []).compactMap { candidates[$0] }
            // A verdict that names papers needs papers the search really returned.
            let named = RelatedWork.Direction.Verdict(rawValue: verdict?.verdict ?? "open") ?? .open
            let checked: RelatedWork.Direction.Verdict = named != .open && evidence.isEmpty ? .open : named
            return RelatedWork.Direction(title: direction.title, why: direction.why, cited: direction.cited,
                                         verdict: checked, evidence: checked == .open ? [] : Array(evidence.prefix(2)),
                                         note: verdict?.note ?? "No close match in the search.")
        }
        return RelatedWork(related: Array(related), directions: checked)
    }

    // MARK: Prompts

    static func planPrompt(_ lines: [String], title: String, given: [Given]) -> String {
        let directions = given.isEmpty
            ? """
            directions: up to 3 things a researcher could study next, each growing from something the paper \
            leaves open (a limitation, something not measured, a test still to do). title is a few words; why is \
            one sentence; quote is the paper's words it grows from, copied exactly; query is a 3 to 6 word search \
            naming the phenomenon ("evaporation cooling cup of hot water"), for papers that may already have studied it.
            """
            : """
            directions: for each of these, copy its title exactly and give query, a 3 to 6 word search naming the \
            phenomenon, for papers that may already have studied it: \(given.map { "\"\($0.title)\" (\($0.why))" }.joined(separator: "; ")).
            """
        return """
        Plan a search of the research literature for this paper, "\(title)".
        topic_queries: 3 searches of 3 to 6 words for the papers closest to this one. Name the physics, method \
        or phenomenon the way a textbook would ("Newton's law of cooling coffee", "heat loss through a cup lid"), \
        not the paper's own title words: a literature search matches ideas, not phrasing.
        \(directions)

        The paper, as read from its page:
        \(lines.joined(separator: "\n").prefix(6_000))
        """
    }

    static func judgePrompt(title: String, lines: [String], candidates: [String: Work], directions: [Planned]) -> String {
        let list = candidates.values.sorted { $0.citations > $1.citations }.map { work in
            "[\(work.id)] \(work.title) (\(work.year.map(String.init) ?? "n.d."), \(work.citations) citations): \(work.abstract.prefix(300))"
        }.joined(separator: "\n")
        return """
        A paper, "\(title)", and papers a search returned. Judge them only from what's written here.
        related: up to 6 of the papers closest to this one, closest first. id is copied exactly from the list; \
        why is one sentence on how it relates. Leave out papers that only share a word.
        directions: for each direction, go through the list of papers (not the paper above, which only raises the \
        question). studied if a listed paper's title or abstract shows it studies that question; partly if one \
        touches it but leaves part of it open (ids: those papers, for either); open if none come close. note is \
        one sentence: what that paper did and, for partly or open, what is still left to do.
        Directions: \(directions.map { "\"\($0.title)\": \($0.why)" }.joined(separator: "; "))

        The paper begins:
        \(lines.joined(separator: " ").prefix(1_500))

        The papers:
        \(list)
        """
    }

    static let planSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "topic_queries": ["type": "ARRAY", "items": ["type": "STRING"]],
            "directions": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "title": ["type": "STRING"],
                        "why": ["type": "STRING"],
                        "quote": ["type": "STRING", "nullable": true],
                        "query": ["type": "STRING"],
                    ],
                    "required": ["title", "why", "quote", "query"],
                ],
            ],
        ],
        "required": ["topic_queries", "directions"],
    ]

    static let judgeSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "related": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": ["id": ["type": "STRING"], "why": ["type": "STRING"]],
                    "required": ["id", "why"],
                ],
            ],
            "directions": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "title": ["type": "STRING"],
                        "verdict": ["type": "STRING", "enum": ["studied", "partly", "open"]],
                        "ids": ["type": "ARRAY", "items": ["type": "STRING"]],
                        "note": ["type": "STRING"],
                    ],
                    "required": ["title", "verdict", "ids", "note"],
                ],
            ],
        ],
        "required": ["related", "directions"],
    ]
}
