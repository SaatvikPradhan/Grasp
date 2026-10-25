import Foundation

/// What to dive into: one thing on a page (a fee, a clause, a result) and where it came from.
public struct DeepDiveSubject: Equatable, Sendable {
    /// A few words: "Late payment fee: $7.00".
    public var topic: String
    /// The words on the page, if it came from one.
    public var quote: String?
    /// The page it's on: "Northway Mobile Statement (phone bill)".
    public var source: String?
    /// More about it: the catch's explanation, the page's summary.
    public var context: String?

    public init(topic: String, quote: String? = nil, source: String? = nil, context: String? = nil) {
        self.topic = topic
        self.quote = quote
        self.source = source
        self.context = context
    }
}

/// What the web says about one thing, each finding tied to the pages that back it.
public struct DeepDive: Equatable, Sendable {
    public struct Source: Equatable, Sendable, Identifiable {
        /// The site, such as "consumerfinance.gov".
        public var site: String
        public var url: URL
        public var id: String { url.absoluteString }
    }

    public struct Finding: Equatable, Sendable {
        public var text: String
        /// Indexes into `sources`, from 0.
        public var sources: [Int]
    }

    /// Something to do, for a plan: which problem on the page it fixes, and whether its numbers
    /// are the page's own (or a source's).
    public struct Step: Equatable, Sendable {
        public var text: String
        public var sources: [Int]
        /// The catch on the page it's about, from 0, in `PageReading.allCatches`.
        public var catchIndex: Int?
        public var numbersChecked: Bool
    }

    public var findings: [Finding]
    /// Steps to take, for a plan; empty for a deep dive.
    public var steps: [Step] = []
    /// One sentence: what it means for the reader.
    public var bottomLine: String?
    /// For a plan: how Swift gets the bottom line's amount from the steps' amounts ("$10.00 + $7.00"),
    /// or nil when it doesn't add up from them.
    public var bottomLineMath: String?
    /// Only the pages some finding cites, numbered in the order they're first cited.
    public var sources: [Source]
    /// What was searched for.
    public var searches: [String]
}

/// Dives into one thing with Google Search: findings from the web, each kept only if a web page
/// backs it, so every line on the card can show where it came from.
public struct DeepDiveFinder: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
        self.client.thinkingLevel = "low"
    }

    public func dive(_ subject: DeepDiveSubject) async throws -> DeepDive {
        Self.checked(try await client.searchGrounded(Self.prompt(subject)))
    }

    static func prompt(_ subject: DeepDiveSubject) -> String {
        var lines = ["Someone is reading a page and wants to go deeper on one thing on it. Search the web and brief them.",
                     "", "The thing: \(subject.topic)"]
        if let source = subject.source { lines.append("On: \(source)") }
        if let quote = subject.quote, !quote.isEmpty { lines.append("Where the page says: \u{201C}\(quote)\u{201D}") }
        if let context = subject.context, !context.isEmpty { lines.append("More: \(context)") }
        lines += ["",
                  "Write 4 to 6 findings, each on its own line starting with \"- \": what reliable sources say that helps "
                      + "them understand or act on it (what it means, what's typical, their rights or options, what to watch "
                      + "for; for research, what's known and what other work found). One or two plain sentences each, with "
                      + "specific numbers where a source gives them. Prefer government, academic and established sources.",
                  "Then one last line starting with \"Bottom line: \" saying in one sentence what it means for them.",
                  "No headings, no introduction."]
        return lines.joined(separator: "\n")
    }

    /// Splits the answer into findings, ties each to the pages whose supported text it contains,
    /// and keeps only findings with a page behind them (all of them, unsourced, if none has one).
    static func checked(_ grounded: Grounded) -> DeepDive {
        var bottomLine: String?
        var raw: [(text: String, pages: [Int])] = []
        for line in grounded.text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("bottom line:") {
                bottomLine = String(trimmed.dropFirst("bottom line:".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            let text = trimmed.drop { "-*•".contains($0) || $0 == " " }.trimmingCharacters(in: .whitespaces)
            guard text.count > 12 else { continue }
            raw.append((String(text), SourceNumbering(grounded).pages(for: String(text))))
        }
        let sourced = raw.filter { !$0.pages.isEmpty }
        let kept = (sourced.isEmpty ? raw : sourced).prefix(5)

        var numbering = SourceNumbering(grounded)
        let findings = kept.map { DeepDive.Finding(text: $0.text, sources: numbering.numbers(forPages: $0.pages)) }
        return DeepDive(findings: findings, bottomLine: bottomLine, sources: numbering.sources, searches: grounded.searches)
    }
}

/// Numbers a grounded answer's web pages in the order lines first cite them, one number to a site.
struct SourceNumbering {
    let grounded: Grounded
    private(set) var sources: [DeepDive.Source] = []

    init(_ grounded: Grounded) {
        self.grounded = grounded
    }

    /// The pages (indexes into `grounded.pages`) whose supported text is part of `line`.
    func pages(for line: String) -> [Int] {
        let pages = grounded.supports.filter { support in
            let piece = support.text.trimmingCharacters(in: .whitespaces).drop { "-*•".contains($0) || $0 == " " }
            return !piece.isEmpty && (line.contains(piece) || piece.contains(line))
        }
        .flatMap(\.pages)
        return pages.reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
    }

    mutating func numbers(for line: String) -> [Int] {
        numbers(forPages: pages(for: line))
    }

    mutating func numbers(forPages pages: [Int]) -> [Int] {
        let numbers = pages.compactMap { page -> Int? in
            guard grounded.pages.indices.contains(page), let url = URL(string: grounded.pages[page].url) else { return nil }
            let site = grounded.pages[page].title.isEmpty ? (url.host ?? "web") : grounded.pages[page].title
            if let at = sources.firstIndex(where: { $0.site == site }) { return at }
            sources.append(.init(site: site, url: url))
            return sources.count - 1
        }
        return numbers.reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
    }
}
