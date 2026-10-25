import Foundation

/// Text as it should be said: money, percents, decimals, times, years and symbols in words. The
/// fast ElevenLabs model reads "$27,956", "8.9%" or "0.031" wrongly, so Grasp says them in words.
public enum SpokenText {
    public static func words(_ text: String) -> String {
        var text = text
        for (symbol, words) in symbols { text = text.replacingOccurrences(of: symbol, with: words) }
        text = replace(#"(\d)\s?[–—-]\s?(\d)"#, in: text) { "\($0[1]) to \($0[2])" }   // ranges: 5–10
        text = replace(#"(-)?\$\s?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?(\s?(?:million|billion|thousand))?"#, in: text) { match in
            money(dollars: match[2], cents: match[3], scale: match[4], negative: !match[1].isEmpty)
        }
        text = replace(#"(-?\d+(?:\.\d+)?)\s?%"#, in: text) { "\(number($0[1])) percent" }
        text = replace(#"\b(\d{1,2}):(\d{2})\s?([AaPp]\.?[Mm]\.?)"#, in: text) { match in
            let minutes = Int(match[2]) ?? 0
            let ampm = match[3].uppercased().filter(\.isLetter).map(String.init).joined(separator: " ")
            return "\(number(match[1])) \(minutes == 0 ? "" : minutes < 10 ? "oh \(number(match[2])) " : "\(number(match[2])) ")\(ampm)"
        }
        text = replace(#"\b(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\b"#, in: text) { duration(hours: $0[1], minutes: $0[2], seconds: $0[3]) }
        text = replace(#"\b(\d+)(st|nd|rd|th)\b"#, in: text) { ordinal(number($0[1])) }
        text = replace(#"(?<![\d,.])\b(1[89]\d{2}|20\d{2})\b(?![\d,]|\.\d)"#, in: text) { year($0[1]) }
        text = replace(#"(-)?\b(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?\b"#, in: text) { match in
            (match[1].isEmpty ? "" : "minus ") + number(match[2] + match[3])
        }
        return text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static let symbols: [(String, String)] = [
        ("°C", " degrees Celsius"), ("°F", " degrees Fahrenheit"), ("°", " degrees"),
        ("±", " plus or minus "), ("×", " times "), ("≈", " about "), ("~", " about "),
        ("−", "-"), ("→", " to "), ("&", " and "),
    ]

    private static func money(dollars: String, cents: String, scale: String, negative: Bool) -> String {
        let whole = Int(dollars.filter(\.isNumber)) ?? 0
        let pennies = cents.isEmpty ? 0 : Int(cents.count == 1 ? cents + "0" : cents) ?? 0
        var parts: [String] = []
        if !scale.isEmpty {
            parts.append("\(number(dollars + (cents.isEmpty ? "" : "." + cents)))\(scale.lowercased()) dollars")
        } else {
            if whole > 0 || pennies == 0 { parts.append("\(number(String(whole))) dollar\(whole == 1 ? "" : "s")") }
            if pennies > 0 { parts.append("\(number(String(pennies))) cent\(pennies == 1 ? "" : "s")") }
        }
        return (negative ? "minus " : "") + parts.joined(separator: " and ")
    }

    private static func duration(hours: String, minutes: String, seconds: String) -> String {
        var parts: [String] = []
        if let h = Int(hours), h > 0 { parts.append("\(number(hours)) hour\(h == 1 ? "" : "s")") }
        if let m = Int(minutes), m > 0 { parts.append("\(number(minutes)) minute\(m == 1 ? "" : "s")") }
        if let s = Int(seconds), s > 0 || parts.isEmpty { parts.append("\(number(seconds)) second\(s == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }

    /// "twenty twenty-one", "nineteen ninety-nine", "two thousand five".
    private static func year(_ digits: String) -> String {
        guard let value = Int(digits) else { return digits }
        if (2000...2009).contains(value) { return number(digits) }
        let (first, last) = (value / 100, value % 100)
        let tail = last == 0 ? "hundred" : last < 10 ? "oh \(number(String(last)))" : number(String(last))
        return "\(number(String(first))) \(tail)"
    }

    /// "27,956" → "twenty-seven thousand nine hundred fifty-six"; "0.031" → "zero point zero three one".
    private static func number(_ digits: String) -> String {
        let plain = digits.replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX")) else { return digits }
        return spellOut.string(from: value as NSDecimalNumber) ?? digits
    }

    private static let spellOut: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .spellOut
        formatter.maximumFractionDigits = 6
        return formatter
    }()

    /// "twenty-three" → "twenty-third".
    private static func ordinal(_ words: String) -> String {
        let irregular = ["one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth",
                         "nine": "ninth", "twelve": "twelfth"]
        guard let end = words.range(of: #"[a-z]+$"#, options: .regularExpression) else { return words }
        let last = String(words[end])
        let spoken = irregular[last] ?? (last.hasSuffix("y") ? String(last.dropLast()) + "ieth" : last + "th")
        return words.replacingCharacters(in: end, with: spoken)
    }

    /// Replaces every match of `pattern`, given its groups (0 is the whole match; a missing group is "").
    private static func replace(_ pattern: String, in text: String, with make: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { index in
                match.range(at: index).location == NSNotFound ? "" : source.substring(with: match.range(at: index))
            }
            result += make(groups)
            last = match.range.location + match.range.length
        }
        return result + source.substring(from: last)
    }
}
