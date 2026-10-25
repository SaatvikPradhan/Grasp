import Foundation

/// Finds where on the page some words came from, in the lines Vision recognized, so a number
/// on the canvas can show the exact spot on the photo it was read from.
public enum SourceLocator {
    public struct Location: Equatable, Sendable {
        /// Index of the first line.
        public var line: Int
        /// The matched part of that line.
        public var range: Range<String.Index>
        /// How many more whole lines the words run onto.
        public var extraLines: Int
    }

    /// The printed value is tried first, since it gives the tightest box; then the quote, exactly
    /// and then by shared words, across one or two lines.
    public static func locate(printed: String?, quote: String, in lines: [String]) -> Location? {
        let quoteWords = words(quote)

        if let printed = printed?.trimmingCharacters(in: .whitespaces), printed.contains(where: \.isNumber) {
            let forms = Set([printed, printed.replacingOccurrences(of: " ", with: ""), printed.replacingOccurrences(of: "$", with: "")])
                .filter { !$0.isEmpty }
            var best: (location: Location, score: Double)?
            for (index, line) in lines.enumerated() {
                for form in forms.sorted(by: { $0.count > $1.count }) {
                    guard let range = standaloneRange(of: form, in: line) else { continue }
                    let score = overlap(words(line), quoteWords)
                    if best == nil || score > best!.score {
                        best = (Location(line: index, range: range, extraLines: 0), score)
                    }
                    break
                }
            }
            if let best { return best.location }
        }

        let squeezed = quote.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if squeezed.count >= 4 {
            for (index, line) in lines.enumerated() {
                let normalLine = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if normalLine == line, let range = line.range(of: squeezed, options: .caseInsensitive) {
                    return Location(line: index, range: range, extraLines: 0)
                }
            }
        }

        guard !quoteWords.isEmpty else { return nil }
        // Enough shared words that it isn't a coincidence: most of them, and at least two.
        let needed = min(2, quoteWords.count)
        var best: (location: Location, score: Double)?
        for (index, line) in lines.enumerated() {
            let single = overlap(words(line), quoteWords)
            let pair = index + 1 < lines.count ? overlap(words(line + " " + lines[index + 1]), quoteWords) : 0
            let (score, extra) = pair > single + 0.15 ? (pair, 1) : (single, 0)
            let shared = Int((score * Double(quoteWords.count)).rounded())
            if score >= 0.6, shared >= needed, best == nil || score > best!.score {
                best = (Location(line: index, range: line.startIndex..<line.endIndex, extraLines: extra), score)
            }
        }
        return best?.location
    }

    /// Lowercased words of two or more letters or digits.
    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 2 })
    }

    /// The share of the quote's words found in the line.
    private static func overlap(_ line: Set<String>, _ quote: Set<String>) -> Double {
        quote.isEmpty ? 0 : Double(line.intersection(quote).count) / Double(quote.count)
    }

    /// A number that isn't part of a longer one: "895.00" inside "1,895.00" doesn't count.
    static func standaloneRange(of text: String, in line: String) -> Range<String.Index>? {
        var start = line.startIndex
        while let range = line.range(of: text, options: .caseInsensitive, range: start..<line.endIndex) {
            start = range.upperBound
            let before = range.lowerBound > line.startIndex ? line[line.index(before: range.lowerBound)] : " "
            let after = range.upperBound < line.endIndex ? line[range.upperBound] : " "
            let numberish: (Character) -> Bool = { $0.isNumber || $0 == "." || $0 == "," }
            if text.first?.isNumber == true, numberish(before) { continue }
            if text.last?.isNumber == true, after.isNumber { continue }
            return range
        }
        return nil
    }
}
