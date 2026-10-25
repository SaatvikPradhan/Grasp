import Foundation

/// Finds where the values Gemini read appear in the page's recognized text lines, so the
/// phone can box them: loan terms in green, add-ons in red.
public enum HighlightMatcher {
    public struct Match: Equatable {
        /// Index into the lines passed in.
        public var line: Int
        public var range: Range<String.Index>
        public var kind: LinkHighlight.Kind
    }

    public static func matches(in lines: [String], for reading: OfferReading) -> [Match] {
        var targets: [(needle: String, kind: LinkHighlight.Kind)] = []
        if let value = reading.amountFinanced { targets += money(value).map { ($0, .term) } }
        if let value = reading.monthlyPayment { targets += money(value).map { ($0, .term) } }
        if let value = reading.aprPercent {
            targets += [String(format: "%.2f", value), String(format: "%.1f", value)].map { ($0, .term) }
        }
        if let months = reading.termMonths {
            targets += ["\(months) monthly", "\(months) months", "\(months) payments"].map { ($0, .term) }
        }
        for fee in reading.addOns {
            targets.append((fee.name, .addon))
            targets += money(fee.amount).map { ($0, .addon) }
        }
        // Longest first, so "21,600.00" claims its text before "21,600" can.
        targets.sort { $0.needle.count > $1.needle.count }

        var found: [Match] = []
        for (index, line) in lines.enumerated() {
            var claimed: [Range<String.Index>] = []
            for target in targets {
                var searchStart = line.startIndex
                while let range = line.range(of: target.needle, options: .caseInsensitive, range: searchStart..<line.endIndex) {
                    searchStart = range.upperBound
                    guard standsAlone(range, in: line), !claimed.contains(where: { $0.overlaps(range) }) else { continue }
                    claimed.append(range)
                    found.append(Match(line: index, range: range, kind: target.kind))
                }
            }
        }
        return found
    }

    /// The ways a dollar amount is printed: "21,600.00", "21600.00", and "21,600" for whole dollars.
    static func money(_ value: Double) -> [String] {
        let grouped = NumberFormatter()
        grouped.numberStyle = .decimal
        grouped.locale = Locale(identifier: "en_US")
        grouped.minimumFractionDigits = 2
        grouped.maximumFractionDigits = 2
        var forms = [grouped.string(from: NSNumber(value: value)), String(format: "%.2f", value)].compactMap { $0 }
        if value == value.rounded() {
            grouped.minimumFractionDigits = 0
            grouped.maximumFractionDigits = 0
            forms += [grouped.string(from: NSNumber(value: value)), String(format: "%.0f", value)].compactMap { $0 }
        }
        return Array(Set(forms))
    }

    /// A number must not be part of a longer one: "895.00" inside "1,895.00" doesn't count.
    private static func standsAlone(_ range: Range<String.Index>, in line: String) -> Bool {
        let numberish: (Character) -> Bool = { $0.isNumber || $0 == "." || $0 == "," }
        if let first = line[range].first, first.isNumber, range.lowerBound > line.startIndex,
           numberish(line[line.index(before: range.lowerBound)]) {
            return false
        }
        if let last = line[range].last, last.isNumber, range.upperBound < line.endIndex,
           line[range.upperBound].isNumber {
            return false
        }
        return true
    }
}
